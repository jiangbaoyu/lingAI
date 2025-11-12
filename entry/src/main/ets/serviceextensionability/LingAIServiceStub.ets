/**
 * LingAI 服务桩
 * 处理 RPC 调用的具体实现
 */

import rpc from '@ohos.rpc';
import { ApiRouter, ApiRequest, ApiResponse, ApiData } from '../services/ApiRouter';
import { common } from '@kit.AbilityKit';
import {
  LingAIError,
  LingAIErrorCode
} from '../sdk/types/LingAITypes';

/**
 * RPC 参数类型
 */
type RpcParamValue = string | number | boolean;

/**
 * RPC 请求接口
 */
interface RpcRequest {
  method: string;
  params: Record<string, RpcParamValue>;
  requestId: string;
}

/**
 * RPC 错误信息接口
 */
interface RpcError {
  code: string;
  message: string;
  details?: Record<string, RpcParamValue>;
}

/**
 * RPC 响应接口
 */
interface RpcResponse {
  success: boolean;
  data?: Record<string, RpcParamValue>;
  error?: RpcError;
  requestId: string;
}

/**
 * LingAI 服务桩类
 */
export class LingAIServiceStub extends rpc.RemoteObject {
  private apiRouter: ApiRouter;

  constructor(context: common.Context) {
    super('LingAIService');
    this.apiRouter = new ApiRouter(context);
  }

  /**
   * 处理 RPC 请求
   */
  onRemoteRequest(
    code: number,
    data: rpc.MessageParcel,
    reply: rpc.MessageParcel,
    options: rpc.MessageOption
  ): boolean {
    try {
      console.log('[LingAI] 收到 RPC 请求, code:', code);
      
      // 读取请求数据
      const requestStr = data.readString();
      const apiRequest: ApiRequest = JSON.parse(requestStr as string) as ApiRequest;
      
      console.log('[LingAI] API 请求类型:', apiRequest.type);
      
      // 使用 ApiRouter 处理请求（异步写入reply，同步返回boolean）
      // 同步处理并返回，避免返回Promise<boolean>
      // 注意：在真实环境中可能需要异步队列，这里保持同步写入reply
      try {
        // 将异步结果写入reply，但保持同步返回boolean
        this.apiRouter.handleRequest(apiRequest).then((response: ApiResponse) => {
          reply.writeString(JSON.stringify(response));
        }).catch(() => {
          const errorResponse: ApiResponse = { success: false, error: 'API请求处理失败', code: 500 };
          reply.writeString(JSON.stringify(errorResponse));
        });
        return true;
      } catch (e) {
        const errorResponse: ApiResponse = { success: false, error: 'API请求处理失败', code: 500 };
        reply.writeString(JSON.stringify(errorResponse));
        return false;
      }
      
    } catch (error) {
      console.error('[LingAI] RPC 请求处理失败:', error);
      
      // 写入错误响应
      const errorResponse: ApiResponse = {
        success: false,
        error: 'RPC请求处理失败',
        code: 500
      };
      
      reply.writeString(JSON.stringify(errorResponse));
      return false;
    }
  }

  /**
   * 娓呯悊璧勬簮
   */
  async cleanup(): Promise<void> {
    await this.apiRouter.cleanup();
  }
}
