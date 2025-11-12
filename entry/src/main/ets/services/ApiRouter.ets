import { rpc } from '@kit.IPCKit';
import { ModelManager } from './ModelManager';
import { InferenceEngine } from './InferenceEngine';
import { AppAuthManager } from './AppAuthManager';
import { DatabaseManager } from './DatabaseManager';
import { common } from '@kit.AbilityKit';
import { MessageRole, ChatCompletionResponse, EmbeddingResponse, ChatMessage, ChatCompletionRequest, EmbeddingRequest, AppRegistrationRequest, ModelDownloadRequest } from '../sdk/types/LingAITypes';

// API请求类型枚举
export enum ApiRequestType {
  // 认证相关
  REGISTER_APP = 1001,
  VALIDATE_API_KEY = 1002,
  
  // 模型管理
  LIST_MODELS = 2001,
  DOWNLOAD_MODEL = 2002,
  DELETE_MODEL = 2003,
  GET_MODEL_INFO = 2004,
  GET_DOWNLOAD_PROGRESS = 2005,
  
  // 推理相关
  CHAT_COMPLETION = 3001,
  CHAT_COMPLETION_STREAM = 3002,
  TEXT_EMBEDDING = 3003,
  
  // 系统信息
  GET_SYSTEM_INFO = 4001,
  GET_USAGE_STATS = 4002
}

// API数据载体类（显式声明可能返回的字段，避免结构类型与未类型对象字面量）
export class ApiData {
  appId?: string;
  apiKey?: string;
  valid?: boolean;
  permissions?: string[];
  models?: string;
  model?: string;
  // 请求相关的显式字段声明，避免未声明对象字面量/结构类型
  modelId?: string;
  huggingFaceId?: string;
  taskId?: string;
  messages?: ChatMessage[];
  temperature?: number;
  maxTokens?: number;
  input?: string | string[];
  progress?: string;
  result?: string;
  systemInfo?: string;
  usage?: string;
  message?: string;
}

// 模型删除请求数据接口
interface DeleteModelData {
  modelId: string;
}

// 获取模型信息请求数据接口
interface GetModelInfoData {
  modelId: string;
}

// 获取下载进度请求数据接口
interface GetDownloadProgressData {
  modelId?: string;
  taskId?: string;
}

// 应用注册请求数据接口（替代 Record 类型）
interface AppRegistrationRequestData {
  appName?: string;
  packageName?: string;
  description?: string;
  permissions?: string[] | string;
}

// 聊天完成请求数据接口
interface ChatCompletionRequestData {
  model: string;
  messages: ChatMessage[];
  temperature?: number;
  maxTokens?: number;
}

// 文本嵌入请求数据接口
interface TextEmbeddingRequestData {
  model: string;
  input: string | string[];
}

// 系统信息接口
interface SystemInfoData {
  version: string;
  supportedModels: string[];
  storage: StorageStats;
  capabilities: SystemCapabilities;
}

// 存储统计接口
interface StorageStats {
  totalModels: number;
  totalSize: number;
  availableSpace: number;
  usedSpace: number;
}

// 系统能力接口
interface SystemCapabilities {
  chatCompletion: boolean;
  streaming: boolean;
  embedding: boolean;
  modelDownload: boolean;
}

// API响应接口
export interface ApiResponse {
  success: boolean;
  data?: ApiData;
  error?: string;
  code?: number;
}

// 为避免 ArkTS 对对象字面量的限制，提供一个具体实现类
class ApiResponseImpl implements ApiResponse {
  success: boolean;
  data?: ApiData;
  error?: string;
  code?: number;

  constructor(success: boolean) {
    this.success = success;
  }
}

// API请求接口
export interface ApiRequest {
  type: ApiRequestType;
  apiKey?: string;
  data?: ApiData;
}

// 聊天消息接口

// 兼容形状：部分调用可能传入 modelId 替代 huggingFaceId
interface ModelIdParam {
  modelId: string;
}

// 为避免 ArkTS 对对象字面量的限制，提供具体的请求实现类
class ChatCompletionRequestImpl implements ChatCompletionRequest {
  model: string;
  messages: ChatMessage[];
  temperature?: number;
  maxTokens?: number;
  stream?: boolean;

  constructor(model: string, messages: ChatMessage[], temperature?: number, maxTokens?: number, stream?: boolean) {
    this.model = model;
    this.messages = messages;
    this.temperature = temperature;
    this.maxTokens = maxTokens;
    this.stream = stream;
  }
}

class EmbeddingRequestImpl implements EmbeddingRequest {
  model: string;
  input: string | string[];

  constructor(model: string, input: string | string[]) {
    this.model = model;
    this.input = input;
  }
}

/**
 * API路由管理器
 * 负责处理所有API请求的路由和分发
 */
export class ApiRouter {
  private modelManager: ModelManager;
  private inferenceEngine: InferenceEngine;
  private authManager: AppAuthManager;
  private dbManager: DatabaseManager;

  constructor(context: common.Context) {
    this.dbManager = new DatabaseManager(context);
    this.modelManager = new ModelManager(context, this.dbManager);
    this.inferenceEngine = new InferenceEngine(context, this.dbManager);
    this.authManager = new AppAuthManager(context, this.dbManager);
  }

  /**
   * 处理API请求
   */
  async handleRequest(request: ApiRequest): Promise<ApiResponse> {
    try {
      // 验证API Key（除了注册应用请求）
      if (request.type !== ApiRequestType.REGISTER_APP) {
        if (!request.apiKey) {
          return this.createErrorResponse('API Key is required', 401);
        }

        const authResult = await this.authManager.validateApiKey(request.apiKey);
        if (!authResult.isActive) {
          return this.createErrorResponse('Invalid API Key', 401);
        }

        // 检查权限
        const hasPermission = await this.checkPermission(request.type, authResult.appId!);
        if (!hasPermission) {
          return this.createErrorResponse('Insufficient permissions', 403);
        }

        // 检查速率限制
        const allowed = await this.authManager.checkRateLimit(request.apiKey!);
        if (!allowed) {
          return this.createErrorResponse('Rate limit exceeded', 429);
        }
      }

      // 路由到具体的处理方法
      switch (request.type) {
        case ApiRequestType.REGISTER_APP:
          return await this.handleAppRegistration(request.data as ApiData);
        
        case ApiRequestType.VALIDATE_API_KEY:
          return await this.handleApiKeyValidation(request.apiKey!);
        
        case ApiRequestType.LIST_MODELS:
          return await this.handleListModels();
        
        case ApiRequestType.DOWNLOAD_MODEL:
          return await this.handleDownloadModel(request.data as (ModelDownloadRequest | ModelIdParam));
        
        case ApiRequestType.DELETE_MODEL:
          return await this.handleDeleteModel(request.data as DeleteModelData);
        
        case ApiRequestType.GET_MODEL_INFO:
          return await this.handleGetModelInfo(request.data as GetModelInfoData);
        
        case ApiRequestType.GET_DOWNLOAD_PROGRESS:
          return await this.handleGetDownloadProgress(request.data as GetDownloadProgressData | undefined);
        
        case ApiRequestType.CHAT_COMPLETION:
          return await this.handleChatCompletion(request.data as ChatCompletionRequestData, request.apiKey!);
        
        case ApiRequestType.CHAT_COMPLETION_STREAM:
          return await this.handleChatCompletionStream(request.data as ChatCompletionRequestData, request.apiKey!);
        
        case ApiRequestType.TEXT_EMBEDDING:
          return await this.handleTextEmbedding(request.data as TextEmbeddingRequestData, request.apiKey!);
        
        case ApiRequestType.GET_SYSTEM_INFO:
          return await this.handleGetSystemInfo();
        
        case ApiRequestType.GET_USAGE_STATS:
          return await this.handleGetUsageStats(request.apiKey!);
        
        default:
          return this.createErrorResponse('Unknown API request type', 400);
      }
    } catch (error) {
      console.error('API request handling error:', error);
      return this.createErrorResponse('Internal server error', 500);
    }
  }

  /**
   * 处理应用注册
   */
  private async handleAppRegistration(data: ApiData): Promise<ApiResponse> {
    try {
      const d = data as AppRegistrationRequestData;
      const appName: string = String(d.appName ?? '');
      const packageName: string = String(d.packageName ?? '');
      const description: string = String(d.description ?? '');
      const permissionsRaw: string[] | string | undefined = d.permissions;
      const permissions: string[] = Array.isArray(permissionsRaw)
        ? permissionsRaw.map((v: string) => String(v))
        : typeof permissionsRaw === 'string'
          ? permissionsRaw.split(',').map((s: string) => s.trim()).filter(Boolean)
          : [];

      const result = await this.authManager.registerApp(
        appName,
        packageName,
        description,
        permissions
      );

      const responseData: ApiData = new ApiData();
      responseData.appId = String(result.appId);
      responseData.apiKey = String(result.apiKey);
      return this.createSuccessResponse(responseData);
    } catch (error) {
      const msg = this.getErrorMessage(error);
      return this.createErrorResponse(`Registration failed: ${msg}`, 400);
    }
  }

  /**
   * 处理API Key验证
   */
  private async handleApiKeyValidation(apiKey: string): Promise<ApiResponse> {
    const result = await this.authManager.validateApiKey(apiKey);
    const responseData: ApiData = new ApiData();
    responseData.valid = !!result.isActive;
    responseData.appId = String(result.appId || '');
    responseData.permissions = Array.isArray(result.permissions) ? result.permissions : [];
    return this.createSuccessResponse(responseData);
  }

  /**
   * 处理模型列表请求
   */
  private async handleListModels(): Promise<ApiResponse> {
    const models = await this.modelManager.getLocalModels();
    const responseData: ApiData = new ApiData();
    responseData.models = JSON.stringify(models);
    return this.createSuccessResponse(responseData);
  }

  /**
   * 处理模型下载请求
   */
  private async handleDownloadModel(data: ModelDownloadRequest | ModelIdParam): Promise<ApiResponse> {
    try {
      const d = data as (ModelDownloadRequest | ModelIdParam);
      let huggingFaceId: string = '';
      const modelDownloadRequest = d as ModelDownloadRequest;
      const modelIdParam = d as ModelIdParam;
      // 优先检查 huggingFaceId（ModelDownloadRequest 的属性）
      if (modelDownloadRequest.huggingFaceId !== undefined && modelDownloadRequest.huggingFaceId !== null && String(modelDownloadRequest.huggingFaceId).length > 0) {
        huggingFaceId = String(modelDownloadRequest.huggingFaceId);
      } else if (modelIdParam.modelId !== undefined && modelIdParam.modelId !== null && String(modelIdParam.modelId).length > 0) {
        // 否则使用 modelId（ModelIdParam 的属性）
        huggingFaceId = String(modelIdParam.modelId);
      }
      const modelInfo = await this.modelManager.downloadModel(huggingFaceId);
      const responseData: ApiData = new ApiData();
      const modelValue: string = typeof modelInfo === 'string' || typeof modelInfo === 'number' || typeof modelInfo === 'boolean' ? String(modelInfo) : JSON.stringify(modelInfo);
      responseData.model = modelValue;
      return this.createSuccessResponse(responseData);
    } catch (error) {
      const msg = this.getErrorMessage(error);
      return this.createErrorResponse(`Download failed: ${msg}`, 400);
    }
  }

  /**
   * 处理模型删除请求
   */
  private async handleDeleteModel(data: DeleteModelData): Promise<ApiResponse> {
    try {
      await this.modelManager.deleteModel(data.modelId);
      const responseData: ApiData = new ApiData();
      responseData.message = 'Model deleted successfully';
      return this.createSuccessResponse(responseData);
    } catch (error) {
      const msg = this.getErrorMessage(error);
      return this.createErrorResponse(`Delete failed: ${msg}`, 400);
    }
  }

  /**
   * 处理获取模型信息请求
   */
  private async handleGetModelInfo(data: GetModelInfoData): Promise<ApiResponse> {
    try {
      const modelInfo = await this.modelManager.getModelInfo(data.modelId);
      if (!modelInfo) {
        return this.createErrorResponse('Model not found', 404);
      }
      const responseData: ApiData = new ApiData();
      responseData.model = JSON.stringify(modelInfo);
      return this.createSuccessResponse(responseData);
    } catch (error) {
      const msg = this.getErrorMessage(error);
      return this.createErrorResponse(`Failed to get model info: ${msg}`, 400);
    }
  }

  /**
   * 处理获取下载进度请求
   */
  private async handleGetDownloadProgress(data: GetDownloadProgressData | undefined): Promise<ApiResponse> {
    try {
      // 兼容 modelId / taskId，确保传入字符串类型
      const id: string = data?.modelId !== undefined && data.modelId !== null
        ? String(data.modelId)
        : data?.taskId !== undefined && data.taskId !== null
          ? String(data.taskId)
          : '';
      const progress = await this.modelManager.getDownloadTaskStatus(id);
      const responseData: ApiData = new ApiData();
      const progressValue: string = typeof progress === 'string' || typeof progress === 'number' || typeof progress === 'boolean' ? String(progress) : JSON.stringify(progress);
      responseData.progress = progressValue;
      return this.createSuccessResponse(responseData);
    } catch (error) {
      const msg = this.getErrorMessage(error);
      return this.createErrorResponse(`Failed to get progress: ${msg}`, 400);
    }
  }

  /**
   * 处理聊天完成请求
   */
  private async handleChatCompletion(data: ChatCompletionRequestData, apiKey: string): Promise<ApiResponse> {
    try {
      const authResult = await this.authManager.validateApiKey(apiKey);
      const requestData = data as ChatCompletionRequestData;
      const model = String(requestData.model ?? '');
      const normalizedMessages: ChatMessage[] = this.normalizeMessages(requestData.messages);
      const req = new ChatCompletionRequestImpl(model, normalizedMessages, requestData.temperature, requestData.maxTokens, false);
      const result = await this.inferenceEngine.chatCompletion(req);

      // 记录使用统计
      await this.authManager.recordUsage(apiKey, 'chat_completion', result.usage?.totalTokens || 0, true);

      const responseData: ApiData = new ApiData();
      responseData.result = JSON.stringify(result);
      return this.createSuccessResponse(responseData);
    } catch (error) {
      const msg = this.getErrorMessage(error);
      return this.createErrorResponse(`Chat completion failed: ${msg}`, 400);
    }
  }

  /**
   * 处理流式聊天完成请求
   */
  private async handleChatCompletionStream(data: ChatCompletionRequestData, apiKey: string): Promise<ApiResponse> {
    try {
      const authResult = await this.authManager.validateApiKey(apiKey);
      const requestData = data as ChatCompletionRequestData;
      const model = String(requestData.model ?? '');
      const normalizedMessages: ChatMessage[] = this.normalizeMessages(requestData.messages);
      const req = new ChatCompletionRequestImpl(model, normalizedMessages, requestData.temperature, requestData.maxTokens, true);
      const result = await this.inferenceEngine.chatCompletion(req);

      const responseData: ApiData = new ApiData();
      responseData.result = JSON.stringify(result);
      return this.createSuccessResponse(responseData);
    } catch (error) {
      const msg = this.getErrorMessage(error);
      return this.createErrorResponse(`Stream chat completion failed: ${msg}`, 400);
    }
  }

  /**
   * 处理文本嵌入请求
   */
  private async handleTextEmbedding(data: TextEmbeddingRequestData, apiKey: string): Promise<ApiResponse> {
    try {
      const authResult = await this.authManager.validateApiKey(apiKey);
      const requestData = data as TextEmbeddingRequestData;
      const model = String(requestData.model ?? '');
      const inputRaw = requestData.input;
      const input: string | string[] = Array.isArray(inputRaw)
        ? inputRaw.map(v => String(v))
        : String(inputRaw ?? '');
      const embedReq = new EmbeddingRequestImpl(model, input);
      const result: EmbeddingResponse = await this.inferenceEngine.createEmbedding(embedReq);

      // 记录使用统计
      const tokenCount: number = Array.isArray(input) ? 
        input.reduce((sum: number, text: string) => sum + String(text).length, 0) : 
        String(input).length;
      await this.authManager.recordUsage(apiKey, 'embedding', tokenCount, true);

      const responseData: ApiData = new ApiData();
      responseData.result = JSON.stringify(result);
      return this.createSuccessResponse(responseData);
    } catch (error) {
      const msg = this.getErrorMessage(error);
      return this.createErrorResponse(`Embedding failed: ${msg}`, 400);
    }
  }

  /**
   * 处理获取系统信息请求
   */
  private async handleGetSystemInfo(): Promise<ApiResponse> {
    try {
      const storageStatsResult = await this.modelManager.getStorageStats();
      const storageStats: StorageStats = {
        totalModels: storageStatsResult.totalModels,
        totalSize: storageStatsResult.totalSize,
        availableSpace: storageStatsResult.availableSpace,
        usedSpace: storageStatsResult.usedSpace
      };
      const capabilities: SystemCapabilities = {
        chatCompletion: true,
        streaming: true,
        embedding: true,
        modelDownload: true
      };
      const supportedModels: string[] = ['llama', 'chatglm', 'baichuan'];
      const systemInfo: SystemInfoData = {
        version: '1.0.0',
        supportedModels: supportedModels,
        storage: storageStats,
        capabilities: capabilities
      };
      const responseData: ApiData = new ApiData();
      responseData.systemInfo = JSON.stringify(systemInfo);
      return this.createSuccessResponse(responseData);
    } catch (error) {
      const msg = this.getErrorMessage(error);
      return this.createErrorResponse(`Failed to get system info: ${msg}`, 500);
    }
  }

  /**
   * 处理获取使用统计请求
   */
  private async handleGetUsageStats(apiKey: string): Promise<ApiResponse> {
    try {
      const authResult = await this.authManager.validateApiKey(apiKey);
      const stats = await this.authManager.getAppUsageStats(authResult.appId!);
      const responseData: ApiData = new ApiData();
      responseData.usage = JSON.stringify(stats);
      return this.createSuccessResponse(responseData);
    } catch (error) {
      const msg = this.getErrorMessage(error);
      return this.createErrorResponse(`Failed to get usage stats: ${msg}`, 400);
    }
  }

  /**
   * 检查权限
   */
  private async checkPermission(requestType: ApiRequestType, appId: string): Promise<boolean> {
    const appInfo = await this.authManager.getAppInfo(appId);
    if (!appInfo) {
      return false;
    }
    const rawPerms = appInfo.permissions;
    let permissions: string[] = [];
    if (Array.isArray(rawPerms)) {
      permissions = rawPerms.map(p => String(p));
    } else if (typeof rawPerms === 'string') {
      const permStr: string = rawPerms;
      permissions = permStr.split(',').map((p: string) => p.trim()).filter(Boolean);
    }
    
    switch (requestType) {
      case ApiRequestType.CHAT_COMPLETION:
      case ApiRequestType.CHAT_COMPLETION_STREAM:
        return permissions.includes('CHAT_COMPLETION') || permissions.includes('chat.completion');
      
      case ApiRequestType.TEXT_EMBEDDING:
        return permissions.includes('TEXT_EMBEDDING') || permissions.includes('embedding');
      
      case ApiRequestType.DOWNLOAD_MODEL:
      case ApiRequestType.DELETE_MODEL:
        return permissions.includes('MODEL_MANAGEMENT') || permissions.includes('model.list') || permissions.includes('model.info');
      
      default:
        return permissions.includes('BASIC_ACCESS');
    }
  }

  /**
   * 创建成功响应
   */
  private createSuccessResponse(data: ApiData): ApiResponse {
    const resp = new ApiResponseImpl(true);
    resp.data = data;
    return resp;
  }

  /**
   * 创建错误响应
   */
  private createErrorResponse(error: string, code: number): ApiResponse {
    const resp = new ApiResponseImpl(false);
    resp.error = error;
    resp.code = code;
    return resp;
  }

  /**
   * 安全提取错误信息，避免 ArkTS 对 unknown 的限制
   */
  private getErrorMessage(error: Error | string | object): string {
    if (typeof error === 'string') {
      return error;
    }
    if (error instanceof Error) {
      return error.message;
    }
    try {
      return JSON.stringify(error);
    } catch (_) {
      return 'Unknown error';
    }
  }

  /**
   * 规范化消息列表，转换角色为枚举，并确保文本为字符串
   */
  private normalizeMessages(raw?: ChatMessage[]): ChatMessage[] {
    if (!Array.isArray(raw)) {
      return [];
    }
    const result: ChatMessage[] = [];
    for (let i = 0; i < raw.length; i++) {
      const m = raw[i] as ChatMessage;
      const roleEnum: MessageRole = m.role !== undefined ? m.role : MessageRole.USER;
      const content: string = String(m.content ?? '');
      result.push({ role: roleEnum, content });
    }
    return result;
  }

  /**
   * 清理资源
   */
  async cleanup(): Promise<void> {
    await this.modelManager.cleanup();
    await this.inferenceEngine.cleanup();
    await this.dbManager.close();
  }
}



