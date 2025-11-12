/**
 * LingAI HTTP客户端
 * 处理与LingAI服务的HTTP通信
 */

import http from '@ohos.net.http';
import { LingAIConfig, LingAIError, LingAIErrorCode, StreamCallback, ErrorDetails } from '../types/LingAITypes';

/**
 * 数据块类型（替代内联对象类型声明）
 */
interface DataChunk {
  toString(): string;
}

/**
 * 错误详情初始化类型
 */
class ErrorDetailsInit {
  statusCode?: number;
  originalError?: string;
  requestId?: string;
  timestamp?: number;
}

/**
 * 明确的错误详情实现，避免直接使用对象字面量
 */
class ErrorDetailsImpl implements ErrorDetails {
  statusCode?: number;
  originalError?: string;
  requestId?: string;
  timestamp?: number;
  constructor(init?: ErrorDetailsInit) {
    if (init) {
      this.statusCode = init.statusCode;
      this.originalError = init.originalError;
      this.requestId = init.requestId;
      this.timestamp = init.timestamp;
    }
  }
}

/**
 * 流式事件类型定义，避免对 JSON.parse 结果使用 any
 */
class StreamDelta { content?: string }
class StreamChoice { delta?: StreamDelta }
class StreamEvent { choices?: StreamChoice[] }

/**
 * HTTP请求参数类型（避免索引签名）
 */
type HttpRequestParams = object;

/**
 * HTTP请求数据类型（避免索引签名）
 */
export type HttpRequestData = object;

/**
 * HTTP响应接口
 */
interface HttpResponseData<T> {
  data: T;
  status: number;
  headers: object;
}

/**
 * LingAI HTTP客户端类
 */
export class LingAIHttpClient {
  private config: LingAIConfig;
  private httpRequest: http.HttpRequest;

  constructor(config: LingAIConfig) {
    this.config = config;
    this.httpRequest = http.createHttp();
  }

  /**
   * GET请求
   */
  async get<T>(url: string, params?: HttpRequestParams): Promise<T> {
    const fullUrl = this.buildUrl(url, params);
    
    try {
      const response = await this.makeRequest<T>('GET', fullUrl);
      return response.data;
    } catch (error) {
      throw this.handleError(error);
    }
  }

  /**
   * POST请求
   */
  async post<T>(url: string, data?: HttpRequestData): Promise<T> {
    const fullUrl = this.buildUrl(url);
    
    try {
      const response = await this.makeRequest<T>('POST', fullUrl, data);
      return response.data;
    } catch (error) {
      throw this.handleError(error);
    }
  }

  /**
   * PUT请求
   */
  async put<T>(url: string, data?: HttpRequestData): Promise<T> {
    const fullUrl = this.buildUrl(url);
    
    try {
      const response = await this.makeRequest<T>('PUT', fullUrl, data);
      return response.data;
    } catch (error) {
      throw this.handleError(error);
    }
  }

  /**
   * DELETE请求
   */
  async delete<T>(url: string): Promise<T> {
    const fullUrl = this.buildUrl(url);
    
    try {
      const response = await this.makeRequest<T>('DELETE', fullUrl);
      return response.data;
    } catch (error) {
      throw this.handleError(error);
    }
  }

  /**
   * 流式POST请求
   */
  async postStream(
    url: string,
    data: HttpRequestData,
    callback: StreamCallback
  ): Promise<void> {
    const fullUrl = this.buildUrl(url);
    
    try {
      const httpRequest = http.createHttp();
      
      // 设置请求头（避免对对象进行索引赋值）
      const headers = this.buildSSEHeaders();
      
      // 配置请求选项
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.POST,
        header: headers,
        extraData: JSON.stringify(data),
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: this.config.timeout || 30000,
        readTimeout: this.config.timeout || 30000
      };

      // 监听响应
      httpRequest.on('headerReceive', (header: object) => {
        if (this.config.debug) {
          console.log('[LingAI] 流式响应头:', JSON.stringify(header));
        }
      });

      // 监听数据
      httpRequest.on('dataReceive', (data: DataChunk) => {
        try {
          const chunk = data.toString();
          if (chunk.trim()) {
            // 处理Server-Sent Events格式
            const lines = chunk.split('\n');
            for (const line of lines) {
              if (line.startsWith('data: ')) {
                const jsonData = line.substring(6).trim();
                if (jsonData === '[DONE]') {
                  if (callback.onComplete) {
                    callback.onComplete();
                  }
                  return;
                }
                
                try {
                  const parsed = JSON.parse(jsonData) as StreamEvent;
                  if (parsed && parsed.choices && parsed.choices.length > 0) {
                    const first = parsed.choices[0] as StreamChoice;
                    const delta = first.delta;
                    const content = delta ? delta.content : undefined;
                    if (content && callback.onData) {
                      callback.onData(content);
                    }
                  }
                } catch (parseError) {
                  if (this.config.debug) {
                    const err = parseError as Error;
                    console.warn('[LingAI] 解析流式数据失败:', err.message);
                  }
                }
              }
            }
          }
        } catch (error) {
          if (callback.onError) {
            // 创建明确的ErrorDetails对象
            const errorDetails: ErrorDetails = new ErrorDetailsImpl(new ErrorDetailsInit());
            errorDetails.originalError = (error as Error).message;
            
            callback.onError(new LingAIError(
              LingAIErrorCode.UNKNOWN_ERROR,
              '处理流式数据失败',
              errorDetails
            ));
          }
        }
      });

      // 监听完成
      httpRequest.on('dataEnd', () => {
        if (callback.onComplete) {
          callback.onComplete();
        }
        httpRequest.destroy();
      });

      // 发送请求
      await httpRequest.request(fullUrl, options);
      
    } catch (error) {
      if (callback.onError) {
        callback.onError(this.handleError(error));
      }
    }
  }

  /**
   * 执行HTTP请求
   */
  private async makeRequest<T>(
    method: string,
    url: string,
    data?: HttpRequestData
  ): Promise<HttpResponseData<T>> {
    return new Promise((resolve, reject) => {
      const httpRequest = http.createHttp();
      
      // 构建请求选项
      const options: http.HttpRequestOptions = {
        method: this.getHttpMethod(method),
        header: this.buildHeaders(),
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: this.config.timeout || 30000,
        readTimeout: this.config.timeout || 30000
      };

      // 添加请求数据
      if (data && (method === 'POST' || method === 'PUT')) {
        options.extraData = JSON.stringify(data);
      }

      // 发送请求
      httpRequest.request(url, options)
        .then((response: http.HttpResponse) => {
          try {
            // 检查响应状态
            if (response.responseCode >= 400) {
              reject(this.createHttpError(response));
              httpRequest.destroy();
              return;
            }

            // 解析响应数据
            let responseData: T;
            if (typeof response.result === 'string') {
              try {
                responseData = JSON.parse(response.result);
              } catch {
                responseData = response.result as T;
              }
            } else {
              responseData = response.result as T;
            }

            // 构建响应对象
            const httpResponse: HttpResponseData<T> = {
              data: responseData,
              status: response.responseCode,
              headers: response.header as object
            };

            resolve(httpResponse);
          } catch (error) {
            // 创建明确的ErrorDetails对象
            const errorDetails: ErrorDetails = new ErrorDetailsImpl(new ErrorDetailsInit());
            errorDetails.originalError = (error as Error).message;
            
            reject(new LingAIError(
              LingAIErrorCode.UNKNOWN_ERROR,
              '解析响应数据失败',
              errorDetails
            ));
          } finally {
            httpRequest.destroy();
          }
        })
        .catch((error: Error | string | object) => {
          httpRequest.destroy();
          reject(this.handleError(error));
        });
    });
  }

  /**
   * 构建完整URL
   */
  private buildUrl(path: string, params?: HttpRequestParams): string {
    let url = `${this.config.baseUrl}${path}`;
    
    if (params) {
      const parts: string[] = [];
      const entries = Object.entries(params as object);
      for (let i = 0; i < entries.length; i++) {
        const key = entries[i][0];
        const value = entries[i][1];
        if (value !== undefined && value !== null) {
          parts.push(`${encodeURIComponent(key)}=${encodeURIComponent(String(value))}`);
        }
      }
      const queryString = parts.join('&');
      if (queryString) {
        url += `?${queryString}`;
      }
    }
    
    return url;
  }

  /**
   * 构建请求头
   */
  private buildHeaders(): object {
    const headersJson = `{"Content-Type":"application/json","Accept":"application/json","User-Agent":"LingAI-SDK/1.0.0 (HarmonyOS)","Authorization":"Bearer ${this.config.apiKey}"}`;
    return JSON.parse(headersJson);
  }

  /**
   * SSE请求头
   */
  private buildSSEHeaders(): object {
    const headersJson = `{"Content-Type":"application/json","Accept":"text/event-stream","Cache-Control":"no-cache","User-Agent":"LingAI-SDK/1.0.0 (HarmonyOS)","Authorization":"Bearer ${this.config.apiKey}"}`;
    return JSON.parse(headersJson);
  }

  /**
   * 获取HTTP方法枚举
   */
  private getHttpMethod(method: string): http.RequestMethod {
    switch (method.toUpperCase()) {
      case 'GET':
        return http.RequestMethod.GET;
      case 'POST':
        return http.RequestMethod.POST;
      case 'PUT':
        return http.RequestMethod.PUT;
      case 'DELETE':
        return http.RequestMethod.DELETE;
      // PATCH可能不被支持，使用POST作为替代
      case 'PATCH':
        return http.RequestMethod.POST;
      case 'HEAD':
        return http.RequestMethod.HEAD;
      case 'OPTIONS':
        return http.RequestMethod.OPTIONS;
      case 'TRACE':
        return http.RequestMethod.TRACE;
      case 'CONNECT':
        return http.RequestMethod.CONNECT;
      default:
        return http.RequestMethod.GET;
    }
  }

  /**
   * 创建HTTP错误
   */
  private createHttpError(response: http.HttpResponse): LingAIError {
    let errorMessage = `HTTP ${response.responseCode}`;
    let errorCode = LingAIErrorCode.UNKNOWN_ERROR;

    // 尝试解析错误响应
    try {
      if (typeof response.result === 'string') {
        const errorData = JSON.parse(response.result);
        if (errorData.message) {
          errorMessage = errorData.message;
        }
        if (errorData.code) {
          errorCode = errorData.code;
        }
      }
    } catch {
      // 忽略解析错误，使用默认错误信息
    }

    // 根据状态码确定错误类型
    switch (response.responseCode) {
      case 400:
        errorCode = LingAIErrorCode.INVALID_REQUEST;
        break;
      case 401:
        errorCode = LingAIErrorCode.AUTHENTICATION_ERROR;
        break;
      case 403:
        errorCode = LingAIErrorCode.PERMISSION_DENIED;
        break;
      case 404:
        errorCode = LingAIErrorCode.MODEL_NOT_FOUND;
        break;
      case 429:
        errorCode = LingAIErrorCode.RATE_LIMIT_EXCEEDED;
        break;
      case 500:
      case 502:
      case 503:
      case 504:
        errorCode = LingAIErrorCode.SERVICE_UNAVAILABLE;
        break;
    }

    const details = new ErrorDetailsImpl(new ErrorDetailsInit());
    details.statusCode = response.responseCode as number;
    return new LingAIError(errorCode, errorMessage, details);
  }

  /**
   * 处理错误
   */
  private handleError(error: Error | string | object): LingAIError {
    if (error instanceof LingAIError) {
      return error;
    }

    // 使用类型守卫检查error对象的属性
    const errorMessage = (error as Error).message || (typeof error === 'string' ? error : '未知错误');

    // 网络错误
    if (error && typeof error === 'object') {
      // 使用显式类型而非 in 操作符
      class ErrorWithCode { code?: string | number }
      const withCode = error as ErrorWithCode;
      const errorCode = withCode.code;
      if (errorCode !== undefined) {
        if (errorCode === 'NETWORK_ERROR' || errorMessage.includes('network')) {
          const errorDetails: ErrorDetails = new ErrorDetailsImpl(new ErrorDetailsInit());
          errorDetails.originalError = errorMessage;
          return LingAIError.networkError('网络连接失败', errorDetails);
        }

        // 超时错误
        if (errorCode === 'TIMEOUT' || errorMessage.includes('timeout')) {
          const errorDetails: ErrorDetails = new ErrorDetailsImpl(new ErrorDetailsInit());
          errorDetails.originalError = errorMessage;
          return LingAIError.networkError('请求超时', errorDetails);
        }
      }
    }

    // 其他未知错误
    const errorDetails: ErrorDetails = new ErrorDetailsImpl(new ErrorDetailsInit());
    errorDetails.originalError = errorMessage;
    
    return new LingAIError(
      LingAIErrorCode.UNKNOWN_ERROR,
      errorMessage,
      errorDetails
    );
  }

  /**
   * 销毁HTTP客户端
   */
  destroy(): void {
    if (this.httpRequest) {
      this.httpRequest.destroy();
    }
  }
}