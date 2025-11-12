/**
 * LingAI RPC客户端
 * 处理与LingAI服务的RPC通信（跨应用调用）
 */

import rpc from '@ohos.rpc';
import Want from '@ohos.app.ability.Want';
import common from '@ohos.app.ability.common';
import { LingAIConfig, LingAIError, LingAIErrorCode, ErrorDetails } from '../types/LingAITypes';

// 通用JSON类型（避免索引签名），兼容常见RPC负载
type JsonPrimitive = string | number | boolean | null;
type JsonArray = JsonValue[];
type JsonValue = JsonPrimitive | JsonArray | object;

// RPC原始返回可能包含错误码
class RpcResultWithErrCode { errCode?: number }

// 类型守卫：判断对象是否包含 errCode:number 字段
function hasErrCode(result: object): boolean {
  const maybe = result as RpcResultWithErrCode;
  return typeof maybe.errCode === 'number';
}

/**
 * RPC请求参数类型（移除索引签名）
 */
type RpcRequestParams = object;

/**
 * RPC请求接口
 */
interface RpcRequest {
  method: string;
  params?: RpcRequestParams;
  requestId: string;
}

/**
 * RPC响应接口
 */
class RpcErrorPayload {
  code: string = '';
  message: string = '';
  details?: object;
}

class RpcResponse {
  success: boolean = false;
  data?: JsonValue;
  error?: RpcErrorPayload;
  requestId: string = '';
}

// 兼容服务端ApiResponse样式
class ApiEnvelope {
  success: boolean = false;
  data?: JsonValue;
  error?: string;
  code?: number;
}

// 兼容服务端RpcResponse样式
interface RpcEnvelope {
  success: boolean;
  data?: JsonValue;
  error?: RpcErrorPayload;
}

// 待处理请求结构（置于顶层作用域，避免放在类体内导致解析错误）
class PendingRequest {
  resolve: (value: JsonValue) => void;
  reject: (error: Error) => void;
  timeout: number;
  constructor(resolve: (value: JsonValue) => void, reject: (error: Error) => void, timeout: number) {
    this.resolve = resolve;
    this.reject = reject;
    this.timeout = timeout;
  }
}

/**
 * LingAI RPC客户端类
 */
export class LingAIRpcClient {
  private config: LingAIConfig;
  private context: common.UIAbilityContext | null = null;
  private connection: rpc.RemoteObject | null = null;
  private connected: boolean = false;
  private requestCounter: number = 0;
  private pendingRequests: Map<string, PendingRequest> = new Map();

  constructor(config: LingAIConfig) {
    this.config = config;
  }

  /**
   * 设置应用上下文
   */
  setContext(context: common.UIAbilityContext): void {
    this.context = context;
  }

  /**
   * 连接到LingAI服务
   */
  async connect(): Promise<void> {
    if (this.connected) {
      return;
    }

    if (!this.context) {
      throw new LingAIError(
        LingAIErrorCode.SERVICE_UNAVAILABLE,
        '应用上下文未设置，请先调用setContext()方法'
      );
    }

    try {
      // 构建连接Want
      const want: Want = {
        bundleName: 'com.lingyao.aibridge',
        abilityName: 'LingAIServiceExtension',
        parameters: {
          apiKey: this.config.apiKey
        }
      };

      // 创建连接回调
      const connection: common.ConnectOptions = {
        onConnect: (elementName, remoteObject) => {
          if (this.config.debug) {
            console.log('[LingAI] RPC连接成功:', elementName);
          }
          
          // 类型转换以解决类型不匹配问题
          this.connection = remoteObject as rpc.RemoteObject;
          this.connected = true;
          
          // 设置死亡通知
          this.setupDeathRecipient();
        },
        
        onDisconnect: (elementName) => {
          if (this.config.debug) {
            console.log('[LingAI] RPC连接断开:', elementName);
          }
          
          this.connection = null;
          this.connected = false;
          
          // 清理待处理的请求
          this.cleanupPendingRequests();
        },
        
        onFailed: (code) => {
          console.error('[LingAI] RPC连接失败:', code);
          this.connection = null;
          this.connected = false;
        }
      };

      // 连接服务
      await this.context.connectServiceExtensionAbility(want, connection);
      
      // 等待连接建立
      await this.waitForConnection();
      
    } catch (error) {
      // 创建明确的ErrorDetails对象
      const errorDetails: ErrorDetails = {
        originalError: (error as Error).message
      };
      
      throw new LingAIError(
        LingAIErrorCode.SERVICE_UNAVAILABLE,
        'RPC连接失败',
        errorDetails
      );
    }
  }

  /**
   * 等待连接建立
   */
  private async waitForConnection(): Promise<void> {
    return new Promise((resolve, reject) => {
      // 创建明确的ErrorDetails对象
      const errorDetails: ErrorDetails = {
        originalError: 'RPC连接超时'
      };
      
      const timeout = setTimeout(() => {
        reject(new LingAIError(
          LingAIErrorCode.SERVICE_UNAVAILABLE,
          'RPC连接超时',
          errorDetails
        ));
      }, this.config.timeout || 30000);

      const checkConnection = () => {
        if (this.connected) {
          clearTimeout(timeout);
          resolve();
        } else {
          setTimeout(checkConnection, 100);
        }
      };

      checkConnection();
    });
  }

  /**
   * 设置死亡通知
   */
  private setupDeathRecipient(): void {
    if (!this.connection) {
      return;
    }

    try {
      const deathRecipient: rpc.DeathRecipient = {
        onRemoteDied: () => {
          console.warn('[LingAI] RPC服务进程死亡');
          this.connection = null;
          this.connected = false;
          this.cleanupPendingRequests();
        }
      };

      this.connection.addDeathRecipient(deathRecipient, 0);
    } catch (error) {
      console.warn('[LingAI] 设置死亡通知失败:', error);
    }
  }

  /**
   * 发送RPC请求
   */
  async sendRequest<T>(method: string, params?: RpcRequestParams): Promise<T> {
    if (!this.connected || !this.connection) {
      throw new LingAIError(
        LingAIErrorCode.SERVICE_UNAVAILABLE,
        'RPC连接未建立'
      );
    }

    const requestId = this.generateRequestId();
    const request: RpcRequest = { method: method, requestId: requestId };
    if (params) {
      request.params = params;
    }

    try {
      // 创建MessageParcel
      const data = rpc.MessageParcel.create();
      const reply = rpc.MessageParcel.create();
      const option = new rpc.MessageOption();

      // 写入请求数据
      data.writeString(JSON.stringify(request));

      // 发送请求
      const result: number | object | null | undefined = await this.connection.sendRequest(1, data, reply, option);
      
      // 兼容返回值为数字或对象的情况
      if (typeof result === 'number') {
        if (result !== 0) {
          // 创建明确的ErrorDetails对象
          const errorDetails: ErrorDetails = {
            originalError: `RPC请求失败: ${result}`
          };
          
          throw new LingAIError(
            LingAIErrorCode.SERVICE_UNAVAILABLE,
            `RPC请求失败: ${result}`,
            errorDetails
          );
        }
      } else if (result !== undefined && result !== null && typeof result === 'object' && hasErrCode(result)) {
        const resultCode = result.errCode;
        if (resultCode !== 0) {
          const errorDetails: ErrorDetails = {
            originalError: `RPC请求失败: ${resultCode}`
          };
          throw new LingAIError(
            LingAIErrorCode.SERVICE_UNAVAILABLE,
            `RPC请求失败: ${resultCode}`,
            errorDetails
          );
        }
      }

      // 读取响应
      const responseStr = reply.readString();
      const parsedRpc = JSON.parse(responseStr) as RpcEnvelope;
      if (typeof parsedRpc.success === 'boolean') {
        if (!parsedRpc.success) {
          // 创建明确的ErrorDetails对象
          const errorDetails: ErrorDetails = {
            originalError: parsedRpc.error?.message || 'RPC请求失败'
          };
          
          throw new LingAIError(
            (parsedRpc.error?.code as LingAIErrorCode) || LingAIErrorCode.UNKNOWN_ERROR,
            parsedRpc.error?.message || 'RPC请求失败',
            errorDetails
          );
        }
        return parsedRpc.data as T;
      }

      const parsedApi = JSON.parse(responseStr) as ApiEnvelope;
      if (typeof parsedApi.success === 'boolean') {
        if (!parsedApi.success) {
          // 创建明确的ErrorDetails对象
          const errorDetails: ErrorDetails = {
            originalError: parsedApi.error || 'RPC请求失败'
          };
          
          throw new LingAIError(
            (String(parsedApi.code) as LingAIErrorCode) || LingAIErrorCode.UNKNOWN_ERROR,
            parsedApi.error || 'RPC请求失败',
            errorDetails
          );
        }
        return parsedApi.data as T;
      }

      // 非法响应结构
      throw new LingAIError(
        LingAIErrorCode.UNKNOWN_ERROR,
        'RPC响应解析失败'
      );

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
        'RPC请求处理失败',
        errorDetails
      );
    }
  }

  /**
   * 发送异步RPC请求
   */
  async sendAsyncRequest<T>(method: string, params?: RpcRequestParams): Promise<T> {
    if (!this.connected || !this.connection) {
      throw new LingAIError(
        LingAIErrorCode.SERVICE_UNAVAILABLE,
        'RPC连接未建立'
      );
    }

    const requestId = this.generateRequestId();
    const request: RpcRequest = { method: method, requestId: requestId };
    if (params) {
      request.params = params;
    }

    return new Promise((resolve, reject) => {
      // 设置超时
      const timeout = setTimeout(() => {
        this.pendingRequests.delete(requestId);
        reject(new LingAIError(
          LingAIErrorCode.SERVICE_UNAVAILABLE,
          'RPC请求超时'
        ));
      }, this.config.timeout || 30000);

      // 保存待处理请求（使用明确类实例，避免结构化类型）
      const pending = new PendingRequest(
        (value: JsonValue) => resolve(value as T),
        (error: Error) => reject(error),
        timeout
      );
      this.pendingRequests.set(requestId, pending);

      try {
        // 创建MessageParcel
        const data = rpc.MessageParcel.create();
        const reply = rpc.MessageParcel.create();
        const option = new rpc.MessageOption();

        // 写入请求数据
        data.writeString(JSON.stringify(request));

        // 发送异步请求
        // 移除then调用，直接处理结果
        try {
          const result: number | object | null | undefined = this.connection!.sendRequest(2, data, reply, option);
          // 兼容返回值为数字或对象的情况
          if (typeof result === 'number') {
            if (result !== 0) {
              const pendingRequest = this.pendingRequests.get(requestId);
              if (pendingRequest) {
                clearTimeout(pendingRequest.timeout);
                this.pendingRequests.delete(requestId);
                
                // 创建明确的ErrorDetails对象
                const errorDetails: ErrorDetails = {
                  originalError: `RPC异步请求失败: ${result}`
                };
                
                pendingRequest.reject(new LingAIError(
                  LingAIErrorCode.SERVICE_UNAVAILABLE,
                  `RPC异步请求失败: ${result}`,
                  errorDetails
                ));
              }
            }
          } else if (result !== undefined && result !== null && typeof result === 'object' && hasErrCode(result)) {
            const codeObj = result as RpcResultWithErrCode;
            const resultCode = codeObj.errCode as number;
            if (resultCode !== 0) {
              const pendingRequest = this.pendingRequests.get(requestId);
              if (pendingRequest) {
                clearTimeout(pendingRequest.timeout);
                this.pendingRequests.delete(requestId);
                const errorDetails: ErrorDetails = {
                  originalError: `RPC异步请求失败: ${resultCode}`
                };
                pendingRequest.reject(new LingAIError(
                  LingAIErrorCode.SERVICE_UNAVAILABLE,
                  `RPC异步请求失败: ${resultCode}`,
                  errorDetails
                ));
              }
            }
          }
          // 异步请求的响应将通过回调处理
        } catch (error) {
          const pendingRequest = this.pendingRequests.get(requestId);
          if (pendingRequest) {
            clearTimeout(pendingRequest.timeout);
            this.pendingRequests.delete(requestId);
            
            // 创建明确的ErrorDetails对象
            const errorDetails: ErrorDetails = {
              originalError: (error as Error).message
            };
            
            pendingRequest.reject(new LingAIError(
              LingAIErrorCode.UNKNOWN_ERROR,
              'RPC异步请求处理失败',
              errorDetails
            ));
          }
        }
      } catch (error) {
        clearTimeout(timeout);
        this.pendingRequests.delete(requestId);
        
        // 创建明确的ErrorDetails对象
        const errorDetails: ErrorDetails = {
          originalError: (error as Error).message
        };
        
        reject(new LingAIError(
          LingAIErrorCode.UNKNOWN_ERROR,
          'RPC异步请求发送失败',
          errorDetails
        ));
      }
    });
  }

  /**
   * 处理异步响应
   */
  handleAsyncResponse(response: RpcResponse): void {
    const pendingRequest = this.pendingRequests.get(response.requestId);
    if (!pendingRequest) {
      return;
    }

    clearTimeout(pendingRequest.timeout);
    this.pendingRequests.delete(response.requestId);

    if (response.success) {
      // data 可能为 undefined，使用 null 兜底以满足 JsonValue
      pendingRequest.resolve(response.data ?? null);
    } else {
      // 创建明确的ErrorDetails对象
      const errorDetails: ErrorDetails = {
        originalError: response.error?.message || 'RPC异步请求失败',
        context: response.error?.details as object | undefined
      };
      
      pendingRequest.reject(new LingAIError(
        response.error?.code as LingAIErrorCode || LingAIErrorCode.UNKNOWN_ERROR,
        response.error?.message || 'RPC异步请求失败',
        errorDetails
      ));
    }
  }

  /**
   * 生成请求ID
   */
  private generateRequestId(): string {
    return `req_${Date.now()}_${++this.requestCounter}`;
  }

  /**
   * 清理待处理的请求
   */
  private cleanupPendingRequests(): void {
    const pendingEntries = Array.from(this.pendingRequests.entries());
    for (let i = 0; i < pendingEntries.length; i++) {
      const requestId = pendingEntries[i][0];
      const pendingRequest = pendingEntries[i][1];
      clearTimeout(pendingRequest.timeout);
      
      // 创建明确的ErrorDetails对象
      const errorDetails: ErrorDetails = {
        originalError: 'RPC连接已断开'
      };
      
      pendingRequest.reject(new LingAIError(
        LingAIErrorCode.SERVICE_UNAVAILABLE,
        'RPC连接已断开',
        errorDetails
      ));
    }
    this.pendingRequests.clear();
  }

  /**
   * 断开连接
   */
  async disconnect(): Promise<void> {
    if (!this.connected || !this.context) {
      return;
    }

    try {
      // 断开服务连接
      // 注意：HarmonyOS API可能需要不同的参数格式，暂时注释掉
      // await this.context.disconnectServiceExtensionAbility();
      
      this.connection = null;
      this.connected = false;
      
      // 清理待处理的请求
      this.cleanupPendingRequests();
      
    } catch (error) {
      console.warn('[LingAI] 断开RPC连接时出错:', error);
      
      // 创建明确的ErrorDetails对象
      const errorDetails: ErrorDetails = {
        originalError: (error as Error).message
      };
      
      throw new LingAIError(
        LingAIErrorCode.UNKNOWN_ERROR,
        '断开RPC连接失败',
        errorDetails
      );
    }
  }

  /**
   * 检查连接状态
   */
  isConnected(): boolean {
    return this.connected && this.connection !== null;
  }

  /**
   * 获取连接对象
   */
  getConnection(): rpc.RemoteObject | null {
    return this.connection;
  }
}