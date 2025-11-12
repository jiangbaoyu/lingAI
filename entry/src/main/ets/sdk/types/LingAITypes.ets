/**
 * LingAI SDK 核心类型定义
 * 提供AI模型推理、聊天对话、文本向量化等功能的类型接口
 */

/**
 * LingAI SDK 配置
 */
export interface LingAIConfig {
  /** API密钥，用于身份验�?*/
  apiKey: string;
  /** 服务基础URL，默认为本地服务 */
  baseUrl?: string;
  /** 请求超时时间（毫秒），默�?0000 */
  timeout?: number;
  /** 重试次数，默�?�?*/
  retryAttempts?: number;
  /** 是否启用调试模式 */
  debug?: boolean;
}

/**
 * 聊天消息角色
 */
export enum MessageRole {
  SYSTEM = 'system',
  USER = 'user',
  ASSISTANT = 'assistant'
}

/**
 * 聊天消息
 */
export interface ChatMessage {
  /** 消息角色 */
  role: MessageRole;
  /** 消息内容 */
  content: string;
  /** 消息时间�?*/
  timestamp?: number;
  /** 消息ID */
  id?: string;
}

/**
 * 聊天完成请求参数
 */
export interface ChatCompletionRequest {
  /** 使用的模型名�?*/
  model: string;
  /** 对话消息列表 */
  messages: ChatMessage[];
  /** 生成文本的随机性，0-2之间，默�?.7 */
  temperature?: number;
  /** 核采样参数，0-1之间，默�?.9 */
  topP?: number;
  /** 最大生成token数量，默�?048 */
  maxTokens?: number;
  /** 是否流式返回，默认false */
  stream?: boolean;
  /** 停止生成的标�?*/
  stop?: string[];
  /** 会话ID，用于上下文管理 */
  sessionId?: string;
}

/**
 * 聊天完成响应
 */
export interface ChatCompletionResponse {
  /** 响应ID */
  id: string;
  /** 对象类型 */
  object: string;
  /** 创建时间�?*/
  created: number;
  /** 使用的模�?*/
  model: string;
  /** 选择列表 */
  choices: ChatChoice[];
  /** 使用情况统计 */
  usage?: TokenUsage;
}

/**
 * 聊天选择
 */
export interface ChatChoice {
  /** 选择索引 */
  index: number;
  /** 消息内容 */
  message: ChatMessage;
  /** 完成原因 */
  finishReason: string;
}

/**
 * Token使用统计
 */
export interface TokenUsage {
  /** 提示token数量 */
  promptTokens: number;
  /** 完成token数量 */
  completionTokens: number;
  /** 总token数量 */
  totalTokens: number;
}

/**
 * 文本嵌入请求
 */
export interface EmbeddingRequest {
  /** 使用的模型名�?*/
  model: string;
  /** 要嵌入的文本或文本数�?*/
  input: string | string[];
  /** 编码格式，默�?float' */
  encodingFormat?: string;
}

/**
 * 文本嵌入响应
 */
export interface EmbeddingResponse {
  /** 对象类型 */
  object: string;
  /** 嵌入数据列表 */
  data: EmbeddingData[];
  /** 使用的模�?*/
  model: string;
  /** 使用情况统计 */
  usage: TokenUsage;
}

/**
 * 嵌入数据
 */
export interface EmbeddingData {
  /** 对象类型 */
  object: string;
  /** 嵌入向量 */
  embedding: number[];
  /** 索引 */
  index: number;
}

/**
 * 模型信息
 */
export interface ModelInfo {
  /** 模型ID */
  id: string;
  /** 模型名称 */
  name: string;
  /** 模型描述 */
  description?: string;
  /** 模型大小（字节） */
  size: number;
  /** 模型类型 */
  type: ModelType;
  /** 模型状�?*/
  status: ModelStatus;
  /** 下载进度�?-100�?*/
  downloadProgress?: number;
  /** 模型文件路径 */
  filePath?: string;
  /** 创建时间 */
  createdAt: number;
  /** 更新时间 */
  updatedAt: number;
  /** HuggingFace仓库ID */
  huggingFaceId?: string;
  /** 模型参数配置 */
  config?: ModelConfig;
}

/**
 * 模型类型
 */
export enum ModelType {
  CHAT = 'chat',
  EMBEDDING = 'embedding',
  COMPLETION = 'completion'
}

/**
 * 模型状�? */
export enum ModelStatus {
  AVAILABLE = 'available',
  DOWNLOADING = 'downloading',
  LOADING = 'loading',
  READY = 'ready',
  LOADED = 'loaded',
  ERROR = 'error',
  NOT_FOUND = 'not_found'
}

/**
 * 模型配置
 */
export interface ModelConfig {
  /** 上下文长�?*/
  contextLength?: number;
  /** 词汇表大�?*/
  vocabSize?: number;
  /** 隐藏层大�?*/
  hiddenSize?: number;
  /** 注意力头数量 */
  numAttentionHeads?: number;
  /** 层数 */
  numLayers?: number;
  /** 最大生成长�?*/
  maxLength?: number;
  /** 温度参数 */
  temperature?: number;
  /** Top-P 采样参数 */
  topP?: number;
  /** Top-K 采样参数 */
  topK?: number;
  /** 重复惩罚 */
  repetitionPenalty?: number;
  /** 停止�?*/
  stopTokens?: string[];
  /** 批处理大�?*/
  batchSize?: number;
}

/**
 * 模型下载请求
 */
export interface ModelDownloadRequest {
  /** HuggingFace模型ID */
  huggingFaceId: string;
  /** 本地模型名称 */
  localName?: string;
  /** 模型类型 */
  type: ModelType;
  /** 是否强制重新下载 */
  forceRedownload?: boolean;
}

/**
 * 模型下载响应
 */
export interface ModelDownloadResponse {
  /** 下载任务ID */
  taskId: string;
  /** 模型信息 */
  model: ModelInfo;
  /** 下载状�?*/
  status: 'started' | 'in_progress' | 'completed' | 'failed';
  /** 错误信息 */
  error?: string;
}

/**
 * 错误详情类型
 */
export interface ErrorDetails {
  /** HTTP状态码 */
  statusCode?: number;
  /** 原始错误信息 */
  originalError?: string;
  /** 请求ID */
  requestId?: string;
  /** 时间�?*/
  timestamp?: number;
  /** 额外的错误上下文 */
  context?: Record<string, string | number | boolean>;
}

/**
 * 错误代码枚举
 */
export enum LingAIErrorCode {
  UNKNOWN_ERROR = 'UNKNOWN_ERROR',
  NETWORK_ERROR = 'NETWORK_ERROR',
  AUTHENTICATION_ERROR = 'AUTHENTICATION_ERROR',
  MODEL_NOT_FOUND = 'MODEL_NOT_FOUND',
  MODEL_LOADING_ERROR = 'MODEL_LOADING_ERROR',
  MODEL_NOT_READY = 'MODEL_NOT_READY',
  MODEL_FILE_NOT_FOUND = 'MODEL_FILE_NOT_FOUND',
  INVALID_REQUEST = 'INVALID_REQUEST',
  INVALID_API_KEY = 'INVALID_API_KEY',
  RATE_LIMIT_EXCEEDED = 'RATE_LIMIT_EXCEEDED',
  SERVICE_UNAVAILABLE = 'SERVICE_UNAVAILABLE',
  PERMISSION_DENIED = 'PERMISSION_DENIED',
  QUOTA_EXCEEDED = 'QUOTA_EXCEEDED',
  EXTERNAL_API_ERROR = 'EXTERNAL_API_ERROR',
  DOWNLOAD_FAILED = 'DOWNLOAD_FAILED',
  INFERENCE_FAILED = 'INFERENCE_FAILED',
  APP_ALREADY_EXISTS = 'APP_ALREADY_EXISTS',
  APP_REGISTRATION_FAILED = 'APP_REGISTRATION_FAILED',
  APP_NOT_FOUND = 'APP_NOT_FOUND',
  API_KEY_GENERATION_FAILED = 'API_KEY_GENERATION_FAILED',
  API_KEY_INACTIVE = 'API_KEY_INACTIVE',
  API_KEY_EXPIRED = 'API_KEY_EXPIRED',
  API_KEY_VALIDATION_FAILED = 'API_KEY_VALIDATION_FAILED',
  API_KEY_REVOCATION_FAILED = 'API_KEY_REVOCATION_FAILED',
  QUOTA_UPDATE_FAILED = 'QUOTA_UPDATE_FAILED',
  MODEL_LOAD_FAILED = 'MODEL_LOAD_FAILED'
}

/**
 * LingAI错误�? */
export class LingAIError extends Error {
  public readonly code: LingAIErrorCode;
  public readonly details?: ErrorDetails;

  constructor(code: LingAIErrorCode, message: string, details?: ErrorDetails | Error) {
    super(message);
    this.name = 'LingAIError';
    this.code = code;
    if (details instanceof Error) {
      this.details = {
        originalError: details.message,
        timestamp: Date.now()
      };
    } else {
      this.details = details;
    }
  }

  /**
   * 创建网络错误
   */
  static networkError(message: string, details?: ErrorDetails): LingAIError {
    return new LingAIError(LingAIErrorCode.NETWORK_ERROR, message, details);
  }

  /**
   * 创建认证错误
   */
  static authenticationError(message: string = '认证失败'): LingAIError {
    return new LingAIError(LingAIErrorCode.AUTHENTICATION_ERROR, message);
  }

  /**
   * 创建模型未找到错�?   */
  static modelNotFound(modelId: string): LingAIError {
    return new LingAIError(LingAIErrorCode.MODEL_NOT_FOUND, `模型未找�? ${modelId}`);
  }

  /**
   * 创建无效请求错误
   */
  static invalidRequest(message: string): LingAIError {
    return new LingAIError(LingAIErrorCode.INVALID_REQUEST, message);
  }
}

/**
 * 流式响应回调
 */
export interface StreamCallback {
  onData?: (chunk: string) => void;
  onError?: (error: LingAIError) => void;
  onComplete?: () => void;
}

/**
 * 应用注册信息
 */
export interface AppRegistration {
  /** 应用ID */
  appId: string;
  /** 应用名称 */
  appName: string;
  /** API密钥 */
  apiKey?: string;
  /** 应用包名 */
  bundleName: string;
  /** 包名（兼容性） */
  packageName?: string;
  /** 描述 */
  description?: string;
  /** 权限列表 */
  permissions: string[];
  /** 配额限制 */
  quota: AppQuota;
  /** 注册时间 */
  registeredAt: number;
  /** 创建时间（兼容性） */
  createdAt?: number;
  /** 最后活跃时�?*/
  lastActiveAt: number;
  /** 最后使用时间（兼容性） */
  lastUsedAt?: number;
  /** 应用状�?*/
  status: 'active' | 'suspended' | 'revoked';
  /** 是否激活（兼容性） */
  isActive?: boolean;
}

/**
 * 应用注册请求
 */
export interface AppRegistrationRequest {
  /** 应用名称 */
  appName: string;
  /** 应用包名 */
  packageName: string;
  /** 描述信息 */
  description?: string;
  /** 权限列表 */
  permissions?: string[];
}

/**
 * 应用配额
 */
export interface AppQuota {
  /** 每日请求限制 */
  dailyRequests: number;
  /** 每分钟请求限�?*/
  requestsPerMinute: number;
  /** 每小时请求限�?*/
  requestsPerHour: number;
  /** 每天请求限制 */
  requestsPerDay: number;
  /** 每天token限制 */
  tokensPerDay: number;
  /** 最大并发请求数 */
  maxConcurrentRequests: number;
  /** 最大token数量 */
  maxTokens: number;
}
