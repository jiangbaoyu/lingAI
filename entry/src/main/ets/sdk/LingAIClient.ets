/**
 * LingAI SDK 客户端
 * 提供AI模型推理、聊天对话、文本向量化等功能的主要接口
 */

import {
  LingAIConfig,
  ChatCompletionRequest,
  ChatCompletionResponse,
  EmbeddingRequest,
  EmbeddingResponse,
  ModelInfo,
  ModelDownloadRequest,
  ModelDownloadResponse,
  LingAIError,
  LingAIErrorCode,
  StreamCallback,
  AppRegistration,
  ErrorDetails
} from './types/LingAITypes';
import { LingAIHttpClient, HttpRequestData } from './http/LingAIHttpClient';
import { LingAIRpcClient } from './rpc/LingAIRpcClient';
// 验证API密钥接口响应类型（使用明确的类，避免结构化类型）
class ApiValidateData { isActive: boolean = false }
class ApiValidateResponse { success: boolean = false; data?: ApiValidateData }

// 明确的错误详情类，避免未声明对象字面量
class ClientErrorDetails implements ErrorDetails {
  statusCode?: number;
  originalError?: string;
  requestId?: string;
  timestamp?: number;
  context?: object;
}

// 明确的请求负载类，避免对象字面量
class ChatCompletionPayload {
  model: string = '';
  messages?: object;
  temperature?: number;
  topP?: number;
  maxTokens?: number;
  stream?: boolean;
  stop?: string[] | undefined | null;
  sessionId?: string;
}

class EmbeddingPayload {
  model: string = '';
  input?: string | object;
  encodingFormat?: string;
}

class ModelDownloadPayload {
  huggingFaceId?: string;
  localName?: string;
  type?: string;
  forceRedownload?: boolean;
}

class AppRegisterPayload {
  appName: string = '';
  bundleName: string = '';
  permissions?: object;
}

// 明确的响应数据类，替代内联对象类型
class ModelsResponse { models: ModelInfo[] = [] }
class DownloadProgressResponse { progress: number = 0; status: string = '' }

/**
 * LingAI SDK 主客户端类
 */
export class LingAIClient {
  private config: LingAIConfig;
  private httpClient: LingAIHttpClient;
  private rpcClient: LingAIRpcClient;
  private initialized: boolean = false;

  constructor(config: LingAIConfig) {
    // 避免对象展开（arkts-no-spread），使用显式赋值
    this.config = {
      apiKey: config.apiKey,
      baseUrl: config.baseUrl !== undefined ? config.baseUrl : 'http://localhost:8080',
      timeout: config.timeout !== undefined ? config.timeout : 30000,
      retryAttempts: config.retryAttempts !== undefined ? config.retryAttempts : 3,
      debug: config.debug !== undefined ? config.debug : false
    };
    
    this.httpClient = new LingAIHttpClient(this.config);
    this.rpcClient = new LingAIRpcClient(this.config);
  }

  /**
   * 初始化SDK
   */
  async initialize(): Promise<void> {
    try {
      // 验证API密钥
      await this.validateApiKey();
      
      // 初始化RPC连接
      await this.rpcClient.connect();
      
      this.initialized = true;
      
      if (this.config.debug) {
        console.log('[LingAI] SDK初始化成功');
      }
    } catch (error) {
      // 创建明确的ErrorDetails对象
      const errorDetails: ErrorDetails = new ClientErrorDetails();
      errorDetails.originalError = (error as Error).message;
      
      throw new LingAIError(
        LingAIErrorCode.SERVICE_UNAVAILABLE,
        'SDK初始化失败',
        errorDetails
      );
    }
  }

  /**
   * 验证API密钥
   */
  private async validateApiKey(): Promise<void> {
    try {
      const response = await this.httpClient.get<ApiValidateResponse>('/api/v1/auth/validate');
      if (!response.success || !response.data?.isActive) {
        throw LingAIError.authenticationError('API密钥无效');
      }
    } catch (error) {
      if (error instanceof LingAIError) {
        throw error;
      }
      throw LingAIError.authenticationError('API密钥验证失败');
    }
  }

  /**
   * 检查初始化状态
   */
  private ensureInitialized(): void {
    if (!this.initialized) {
      throw new LingAIError(
        LingAIErrorCode.SERVICE_UNAVAILABLE,
        'SDK未初始化，请先调用initialize()方法'
      );
    }
  }

  /**
   * 聊天完成 - 非流式
   */
  async chatCompletion(request: ChatCompletionRequest): Promise<ChatCompletionResponse> {
    this.ensureInitialized();
    
    try {
      // 验证请求参数
      this.validateChatRequest(request);
      
      // 发送请求：使用明确的类实例
      const requestData = new ChatCompletionPayload();
      requestData.model = request.model;
      requestData.messages = request.messages as object;
      requestData.temperature = request.temperature;
      requestData.topP = request.topP;
      requestData.maxTokens = request.maxTokens;
      requestData.stream = request.stream;
      requestData.stop = request.stop as string[] | undefined | null;
      requestData.sessionId = request.sessionId;
      
      const response = await this.httpClient.post<ChatCompletionResponse>(
        '/api/v1/chat/completions',
        requestData
      );
      
      return response;
    } catch (error) {
      if (error instanceof LingAIError) {
        throw error;
      }
      
      // 创建明确的ErrorDetails对象
      const errorDetails: ErrorDetails = new ClientErrorDetails();
      errorDetails.originalError = (error as Error).message;
      
      throw new LingAIError(
        LingAIErrorCode.UNKNOWN_ERROR,
        '聊天完成请求失败',
        errorDetails
      );
    }
  }

  /**
   * 聊天完成 - 流式
   */
  async chatCompletionStream(
    request: ChatCompletionRequest,
    callback: StreamCallback
  ): Promise<void> {
    this.ensureInitialized();
    
    try {
      // 验证请求参数
      this.validateChatRequest(request);
      
      // 设置流式请求（使用明确的类实例）
      const streamRequest = new ChatCompletionPayload();
      streamRequest.model = request.model;
      streamRequest.messages = request.messages as object;
      streamRequest.temperature = request.temperature;
      streamRequest.topP = request.topP;
      streamRequest.maxTokens = request.maxTokens;
      streamRequest.stream = true;
      streamRequest.stop = request.stop as string[] | undefined | null;
      streamRequest.sessionId = request.sessionId;
      
      // 发送流式请求
      await this.httpClient.postStream(
        '/api/v1/chat/completions',
        streamRequest,
        callback
      );
    } catch (error) {
      if (callback.onError) {
        const lingAIError = error instanceof LingAIError 
          ? error 
          : (() => {
              const details = new ClientErrorDetails();
              details.originalError = (error as Error).message;
              return new LingAIError(LingAIErrorCode.UNKNOWN_ERROR, '流式聊天请求失败', details);
            })();
        callback.onError(lingAIError);
      }
    }
  }

  /**
   * 文本嵌入
   */
  async createEmbedding(request: EmbeddingRequest): Promise<EmbeddingResponse> {
    this.ensureInitialized();
    
    try {
      // 验证请求参数
      this.validateEmbeddingRequest(request);
      
      // 发送请求
      const requestData = new EmbeddingPayload();
      requestData.model = request.model;
      requestData.input = (request.input as string) ?? (request.input as object);
      requestData.encodingFormat = request.encodingFormat;
      
      const response = await this.httpClient.post<EmbeddingResponse>(
        '/api/v1/embeddings',
        requestData
      );
      
      return response;
    } catch (error) {
      if (error instanceof LingAIError) {
        throw error;
      }
      
      // 创建明确的ErrorDetails对象
      const errorDetails: ErrorDetails = new ClientErrorDetails();
      errorDetails.originalError = (error as Error).message;
      
      throw new LingAIError(
        LingAIErrorCode.UNKNOWN_ERROR,
        '文本嵌入请求失败',
        errorDetails
      );
    }
  }

  /**
   * 获取可用模型列表
   */
  async listModels(): Promise<ModelInfo[]> {
    this.ensureInitialized();
    
    try {
      const response = await this.httpClient.get<ModelsResponse>('/api/v1/models');
      return response.models;
    } catch (error) {
      if (error instanceof LingAIError) {
        throw error;
      }
      
      // 创建明确的ErrorDetails对象
      const errorDetails: ErrorDetails = new ClientErrorDetails();
      errorDetails.originalError = (error as Error).message;
      
      throw new LingAIError(
        LingAIErrorCode.UNKNOWN_ERROR,
        '获取模型列表失败',
        errorDetails
      );
    }
  }

  /**
   * 获取模型信息
   */
  async getModel(modelId: string): Promise<ModelInfo> {
    this.ensureInitialized();
    
    try {
      const response = await this.httpClient.get<ModelInfo>(`/api/v1/models/${modelId}`);
      return response;
    } catch (error) {
      if (error instanceof LingAIError) {
        throw error;
      }
      
      // 创建明确的ErrorDetails对象
      const errorDetails: ErrorDetails = new ClientErrorDetails();
      errorDetails.originalError = (error as Error).message;
      
      throw LingAIError.modelNotFound(modelId);
    }
  }

  /**
   * 下载模型
   */
  async downloadModel(request: ModelDownloadRequest): Promise<ModelDownloadResponse> {
    this.ensureInitialized();
    
    try {
      // 验证请求参数
      this.validateDownloadRequest(request);
      
      // 发送下载请求：使用明确的类实例
      const requestData = new ModelDownloadPayload();
      requestData.huggingFaceId = request.huggingFaceId;
      requestData.localName = request.localName;
      requestData.type = request.type as string;
      requestData.forceRedownload = request.forceRedownload;
      
      const response = await this.httpClient.post<ModelDownloadResponse>(
        '/api/v1/models/download',
        requestData
      );
      
      return response;
    } catch (error) {
      if (error instanceof LingAIError) {
        throw error;
      }
      
      // 创建明确的ErrorDetails对象
      const errorDetails: ErrorDetails = new ClientErrorDetails();
      errorDetails.originalError = (error as Error).message;
      
      throw new LingAIError(
        LingAIErrorCode.UNKNOWN_ERROR,
        '模型下载请求失败',
        errorDetails
      );
    }
  }

  /**
   * 获取下载进度
   */
  async getDownloadProgress(taskId: string): Promise<DownloadProgressResponse> {
    this.ensureInitialized();
    
    try {
      const response = await this.httpClient.get<DownloadProgressResponse>(
        `/api/v1/models/download/${taskId}/progress`
      );
      return response;
    } catch (error) {
      if (error instanceof LingAIError) {
        throw error;
      }
      
      // 创建明确的ErrorDetails对象
      const errorDetails: ErrorDetails = new ClientErrorDetails();
      errorDetails.originalError = (error as Error).message;
      
      throw new LingAIError(
        LingAIErrorCode.UNKNOWN_ERROR,
        '获取下载进度失败',
        errorDetails
      );
    }
  }

  /**
   * 删除模型
   */
  async deleteModel(modelId: string): Promise<void> {
    this.ensureInitialized();
    
    try {
      await this.httpClient.delete(`/api/v1/models/${modelId}`);
    } catch (error) {
      if (error instanceof LingAIError) {
        throw error;
      }
      
      // 创建明确的ErrorDetails对象
      const errorDetails: ErrorDetails = {
        originalError: (error as Error).message
      };
      
      throw new LingAIError(
        LingAIErrorCode.UNKNOWN_ERROR,
        '删除模型失败',
        errorDetails
      );
    }
  }

  /**
   * 注册应用
   */
  async registerApp(appInfo: {
    appName: string;
    bundleName: string;
    permissions: string[];
  }): Promise<AppRegistration> {
    this.ensureInitialized();
    
    try {
      // 创建明确的请求负载实例
      const requestData = new AppRegisterPayload();
      requestData.appName = appInfo.appName;
      requestData.bundleName = appInfo.bundleName;
      requestData.permissions = appInfo.permissions as object;
      
      const response = await this.httpClient.post<AppRegistration>(
        '/api/v1/apps/register',
        requestData
      );
      return response;
    } catch (error) {
      if (error instanceof LingAIError) {
        throw error;
      }
      
      // 创建明确的ErrorDetails对象
      const errorDetails: ErrorDetails = new ClientErrorDetails();
      errorDetails.originalError = (error as Error).message;
      
      throw new LingAIError(
        LingAIErrorCode.UNKNOWN_ERROR,
        '应用注册失败',
        errorDetails
      );
    }
  }

  /**
   * 获取应用信息
   */
  async getAppInfo(): Promise<AppRegistration> {
    this.ensureInitialized();
    
    try {
      const response = await this.httpClient.get<AppRegistration>('/api/v1/apps/info');
      return response;
    } catch (error) {
      if (error instanceof LingAIError) {
        throw error;
      }
      
      // 创建明确的ErrorDetails对象
      const errorDetails: ErrorDetails = new ClientErrorDetails();
      errorDetails.originalError = (error as Error).message;
      
      throw new LingAIError(
        LingAIErrorCode.UNKNOWN_ERROR,
        '获取应用信息失败',
        errorDetails
      );
    }
  }

  /**
   * 验证聊天请求参数
   */
  private validateChatRequest(request: ChatCompletionRequest): void {
    if (!request.model) {
      throw LingAIError.invalidRequest('模型名称不能为空');
    }
    
    if (!request.messages || request.messages.length === 0) {
      throw LingAIError.invalidRequest('消息列表不能为空');
    }
    
    if (request.temperature !== undefined && (request.temperature < 0 || request.temperature > 2)) {
      throw LingAIError.invalidRequest('temperature参数必须在0-2之间');
    }
    
    if (request.maxTokens !== undefined && request.maxTokens <= 0) {
      throw LingAIError.invalidRequest('maxTokens参数必须大于0');
    }
  }

  /**
   * 验证嵌入请求参数
   */
  private validateEmbeddingRequest(request: EmbeddingRequest): void {
    if (!request.model) {
      throw LingAIError.invalidRequest('模型名称不能为空');
    }
    
    if (!request.input) {
      throw LingAIError.invalidRequest('输入文本不能为空');
    }
  }

  /**
   * 验证下载请求参数
   */
  private validateDownloadRequest(request: ModelDownloadRequest): void {
    if (!request.huggingFaceId) {
      throw LingAIError.invalidRequest('HuggingFace模型ID不能为空');
    }
    
    if (!request.type) {
      throw LingAIError.invalidRequest('模型类型不能为空');
    }
  }

  /**
   * 销毁客户端
   */
  async destroy(): Promise<void> {
    try {
      await this.rpcClient.disconnect();
      this.initialized = false;
      
      if (this.config.debug) {
        console.log('[LingAI] SDK已销毁');
      }
    } catch (error) {
      console.error('[LingAI] SDK销毁时发生错误:', error);
    }
  }
}

/**
 * 创建LingAI客户端实例
 */
export function createLingAIClient(config: LingAIConfig): LingAIClient {
  return new LingAIClient(config);
}
