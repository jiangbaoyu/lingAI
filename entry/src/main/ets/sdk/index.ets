/**
 * LingAI SDK 主入口文件
 * 提供统一的API接口导出
 */

// 核心客户端
export { LingAIClient, createLingAIClient } from './LingAIClient';

// 类型定义
export {
  // 配置和基础类型
  LingAIConfig,
  MessageRole,
  ChatMessage,
  
  // 聊天相关类型
  ChatCompletionRequest,
  ChatCompletionResponse,
  ChatChoice,
  TokenUsage,
  
  // 嵌入相关类型
  EmbeddingRequest,
  EmbeddingResponse,
  EmbeddingData,
  
  // 模型相关类型
  ModelInfo,
  ModelType,
  ModelStatus,
  ModelConfig,
  ModelDownloadRequest,
  ModelDownloadResponse,
  
  // 错误处理
  LingAIError,
  LingAIErrorCode,
  
  // 流式处理
  StreamCallback,
  
  // 应用注册
  AppRegistration,
  AppQuota
} from './types/LingAITypes';

// HTTP客户端
export { LingAIHttpClient } from './http/LingAIHttpClient';

// RPC客户端
export { LingAIRpcClient } from './rpc/LingAIRpcClient';

/**
 * SDK版本信息
 */
export const SDK_VERSION = '1.0.0';

/**
 * SDK默认配置
 */
export const DEFAULT_CONFIG: Partial<LingAIConfig> = {
  baseUrl: 'http://localhost:8080',
  timeout: 30000,
  retryAttempts: 3,
  debug: false
};

/**
 * 快速创建LingAI客户端的便捷方法
 * @param apiKey API密钥
 * @param options 可选配置
 * @returns LingAI客户端实例
 */
export function createQuickClient(
  apiKey: string,
  options?: Partial<LingAIConfig>
): LingAIClient {
  const config: LingAIConfig = {
    apiKey,
    ...DEFAULT_CONFIG,
    ...options
  };
  
  return createLingAIClient(config);
}

/**
 * 验证API密钥格式
 * @param apiKey API密钥
 * @returns 是否有效
 */
export function validateApiKey(apiKey: string): boolean {
  if (!apiKey || typeof apiKey !== 'string') {
    return false;
  }
  
  // API密钥应该是32位以上的字符串
  if (apiKey.length < 32) {
    return false;
  }
  
  // 检查是否包含有效字符
  const validPattern = /^[a-zA-Z0-9_-]+$/;
  return validPattern.test(apiKey);
}

/**
 * 获取SDK信息
 */
export function getSDKInfo(): {
  version: string;
  name: string;
  description: string;
  author: string;
} {
  return {
    version: SDK_VERSION,
    name: 'LingAI SDK',
    description: 'HarmonyOS AI推理SDK，提供本地大模型服务',
    author: 'LingYao Team'
  };
}