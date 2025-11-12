/**
 * ��������
 * ���𱾵�ģ�͵��������㣬�����ı����ɺ�������
 */

import fs from '@ohos.file.fs';
import worker from '@ohos.worker';
import common from '@ohos.app.ability.common';
import {
  ModelInfo,
  ModelStatus,
  ChatMessage,
  ChatCompletionRequest,
  ChatCompletionResponse,
  ChatChoice,
  EmbeddingRequest,
  EmbeddingResponse,
  EmbeddingData,
  StreamCallback,
  TokenUsage,
  LingAIError,
  LingAIErrorCode,
  MessageRole,
  ErrorDetails
} from '../sdk/types/LingAITypes';
import { DatabaseManager } from './DatabaseManager';

/**
 * �������ýӿ�
 */
interface InferenceConfig {
  maxTokens?: number;
  temperature?: number;
  topP?: number;
  topK?: number;
  repetitionPenalty?: number;
  stopTokens?: string[];
  seed?: number;
  contextLength?: number;
  batchSize?: number;
}

/**
 * Worker消息：加载模型
 */
interface WorkerLoadMessage {
  type: 'loadModel';
  modelPath: string;
  config: InferenceConfig;
}

/**
 * Embedding������ӿ�
 */
// 使用 SDK 中的 EmbeddingData 类型，避免本地结构类型

/**
 * ʹ��ͳ�ƽӿ�
 */
interface UsageStats {
  promptTokens: number;
  completionTokens?: number;
  totalTokens: number;
}

/**
 * ����״̬�ӿ�
 */
interface EngineStatus {
  loadedModels: number;
  runningTasks: number;
  maxConcurrentTasks: number;
  maxLoadedModels: number;
}

/**
 * Token使用统计接口
 */
interface TokenUsageStats {
  promptTokens: number;
  completionTokens: number;
  totalTokens: number;
}

/**
 * 推理结果接口
 */
interface InferenceResult {
  content: string;
  finishReason: string;
  usage: TokenUsageStats;
}

/**
 * ��ʽ��ӦDelta�ӿ�
 */
interface StreamDelta {
  content?: string;
}

/**
 * ��ʽ��Ӧѡ��ӿ�
 */
interface StreamChoice {
  index: number;
  delta: StreamDelta;
  finishReason: string | null;
}

/**
 * ��ʽ��Ӧ��ӿ�
 */
interface StreamChunk {
  id: string;
  object: string;
  created: number;
  model: string;
  choices: StreamChoice[];
}

/**
 * ��������ӿ�
 */
interface InferenceTask {
  id: string;
  type: 'chat' | 'embedding';
  modelId: string;
  status: 'pending' | 'running' | 'completed' | 'failed';
  startTime: number;
  endTime?: number;
  inputTokens?: number;
  outputTokens?: number;
  error?: string;
}

/**
 * ģ��ʵ���ӿ�
 */
interface ModelInstance {
  modelId: string;
  modelInfo: ModelInfo;
  loadTime: number;
  lastUsedTime: number;
  isLoaded: boolean;
  worker?: worker.ThreadWorker;
  config: InferenceConfig;
}

/**
 * ����������
 */
export class InferenceEngine {
  private context: common.Context;
  private databaseManager: DatabaseManager;
  private loadedModels: Map<string, ModelInstance> = new Map();
  private runningTasks: Map<string, InferenceTask> = new Map();
  private maxConcurrentTasks: number = 3;
  private maxLoadedModels: number = 2;
  private modelCleanupInterval: number = 30 * 60 * 1000; // 30����

  constructor(context: common.Context, databaseManager: DatabaseManager) {
    this.context = context;
    this.databaseManager = databaseManager;
    
    // ����������������
    this.startCleanupTimer();
  }

  /**
   * ����ģ��
   */
  async loadModel(modelId: string): Promise<void> {
    try {
      console.log(`[InferenceEngine] ��ʼ����ģ��: ${modelId}`);

      // ���ģ���Ƿ��Ѽ���
      if (this.loadedModels.has(modelId)) {
        const instance = this.loadedModels.get(modelId)!;
        instance.lastUsedTime = Date.now();
        console.log(`[InferenceEngine] ģ���Ѽ���: ${modelId}`);
        return;
      }

      // ��ȡģ����Ϣ
      const modelInfo = await this.databaseManager.getModel(modelId);
      if (!modelInfo) {
        throw new LingAIError(
          LingAIErrorCode.MODEL_NOT_FOUND,
          'ģ�Ͳ�����'
        );
      }

      if (modelInfo.status !== ModelStatus.READY) {
        throw new LingAIError(
          LingAIErrorCode.MODEL_NOT_READY,
          'ģ��δ׼������'
        );
      }

      // ���ģ���ļ�
      if (!modelInfo.filePath) {
        throw new LingAIError(
          LingAIErrorCode.MODEL_FILE_NOT_FOUND,
          'ģ���ļ�������'
        );
      }
      let fileExists: boolean = false;
      try {
        fs.accessSync(modelInfo.filePath);
        fileExists = true;
      } catch (_e) {
        fileExists = false;
      }
      if (!fileExists) {
        throw new LingAIError(
          LingAIErrorCode.MODEL_FILE_NOT_FOUND,
          'ģ���ļ�������'
        );
      }

      // ����Ƿ���Ҫж������ģ��
      if (this.loadedModels.size >= this.maxLoadedModels) {
        await this.unloadLeastRecentlyUsedModel();
      }

      // �������ݿ�״̬
      await this.databaseManager.updateModelStatus(modelId, ModelStatus.LOADING);

      // ������������
      const config: InferenceConfig = {
        maxTokens: modelInfo.config?.maxLength || 2048,
        temperature: modelInfo.config?.temperature || 0.7,
        topP: modelInfo.config?.topP || 0.9,
        topK: modelInfo.config?.topK || 40,
        repetitionPenalty: modelInfo.config?.repetitionPenalty || 1.1,
        contextLength: modelInfo.config?.contextLength || 4096,
        batchSize: modelInfo.config?.batchSize || 1,
        seed: -1
      };

      // ����Worker����ģ�ͼ��أ�ģ�⣩
      const workerInstance = new worker.ThreadWorker('entry/ets/workers/InferenceWorker.ts');
      
      // ����Worker��Ϣ����
      workerInstance.onmessage = (_event: object) => {
        console.log('[InferenceEngine] Worker message received');
      };

      workerInstance.onerror = (_event: object) => {
        console.error('[InferenceEngine] Worker encountered an error');
      };

      // ���ͼ���ģ�����Worker
      const loadMessage: WorkerLoadMessage = {
        type: 'loadModel',
        modelPath: modelInfo.filePath!,
        config: config
      };
      workerInstance.postMessage(loadMessage);

      // ����ģ��ʵ��
      const instance: ModelInstance = {
        modelId: modelId,
        modelInfo: modelInfo,
        loadTime: Date.now(),
        lastUsedTime: Date.now(),
        isLoaded: true,
        worker: workerInstance,
        config: config
      };

      this.loadedModels.set(modelId, instance);

      // �������ݿ�״̬
      await this.databaseManager.updateModelStatus(modelId, ModelStatus.LOADED);

      console.log(`[InferenceEngine] ģ�ͼ������: ${modelId}`);

    } catch (error) {
      console.error('[InferenceEngine] ����ģ��ʧ��:', error);
      
      // �ָ�ģ��״̬
      try {
        await this.databaseManager.updateModelStatus(modelId, ModelStatus.READY);
      } catch (updateError) {
        console.error('[InferenceEngine] �ָ�ģ��״̬ʧ��:', updateError);
      }
      
      throw new LingAIError(
        LingAIErrorCode.MODEL_LOAD_FAILED,
        '加载模型失败',
        this.toErrorDetails(error, '加载模型失败')
      );
    }
  }

  /**
   * ж��ģ��
   */
  async unloadModel(modelId: string): Promise<void> {
    try {
      const instance = this.loadedModels.get(modelId);
      if (!instance) {
        console.log(`[InferenceEngine] ģ��δ����: ${modelId}`);
        return;
      }

      console.log(`[InferenceEngine] ��ʼж��ģ��: ${modelId}`);

      // ��ֹWorker
      if (instance.worker) {
        instance.worker.terminate();
      }

      // ���ڴ����Ƴ�
      this.loadedModels.delete(modelId);

      // �������ݿ�״̬
      await this.databaseManager.updateModelStatus(modelId, ModelStatus.READY);

      console.log(`[InferenceEngine] ģ��ж�����: ${modelId}`);

    } catch (error) {
      console.error('[InferenceEngine] ж��ģ��ʧ��:', error);
      throw new LingAIError(
        LingAIErrorCode.UNKNOWN_ERROR,
        'ж��ģ��ʧ��',
        this.toError(error)
      );
    }
  }

  /**
   * ���첹ȫ
   */
  async chatCompletion(request: ChatCompletionRequest): Promise<ChatCompletionResponse> {
    try {
      console.log(`[InferenceEngine] ��ʼ���첹ȫ: ${request.model}`);

      // ��֤����
      this.validateChatRequest(request);

      // ȷ��ģ���Ѽ���
      await this.loadModel(request.model);
      const instance = this.loadedModels.get(request.model)!;
      instance.lastUsedTime = Date.now();

      // ������������
      const task: InferenceTask = {
        id: this.generateTaskId(),
        type: 'chat',
        modelId: request.model,
        status: 'running',
        startTime: Date.now()
      };

      this.runningTasks.set(task.id, task);

      // ������ʾ�ı�
      const prompt = this.buildPrompt(request.messages);
      
      // �ϲ�����
      const config: InferenceConfig = {
        maxTokens: request.maxTokens || instance.config.maxTokens,
        temperature: request.temperature || instance.config.temperature,
        topP: request.topP || instance.config.topP,
        topK: instance.config.topK,
        repetitionPenalty: instance.config.repetitionPenalty,
        stopTokens: request.stop || instance.config.stopTokens,
        seed: instance.config.seed,
        contextLength: instance.config.contextLength,
        batchSize: instance.config.batchSize
      };

      // ִ��������ģ�⣩
      const response = await this.performInference(instance, prompt, config, task);

      // ��������״̬
      task.status = 'completed';
      task.endTime = Date.now();
      task.inputTokens = this.countTokens(prompt);
      task.outputTokens = this.countTokens(response.content);

      // ������Ӧ
      const choice: ChatChoice = {
        index: 0,
        message: {
          role: MessageRole.ASSISTANT,
          content: response.content
        },
        finishReason: response.finishReason || 'stop'
      };

      const chatResponse: ChatCompletionResponse = {
        id: `chatcmpl_${task.id}`,
        object: 'chat.completion',
        created: Math.floor(task.startTime / 1000),
        model: request.model,
        choices: [choice],
        usage: {
          promptTokens: task.inputTokens!,
          completionTokens: task.outputTokens!,
          totalTokens: task.inputTokens! + task.outputTokens!
        }
      };

      console.log(`[InferenceEngine] ���첹ȫ���: ${task.id}`);
      return chatResponse;

    } catch (error) {
      console.error('[InferenceEngine] ���첹ȫʧ��:', error);
      throw new LingAIError(
        LingAIErrorCode.INFERENCE_FAILED,
        '推理失败',
        this.toErrorDetails(error, '推理失败')
      );
    }
  }

  /**
   * ��ʽ���첹ȫ
   */
  async chatCompletionStream(
    request: ChatCompletionRequest,
    onChunk: StreamCallback
  ): Promise<void> {
    try {
      console.log(`[InferenceEngine] ��ʼ��ʽ���첹ȫ: ${request.model}`);

      // ��֤����
      this.validateChatRequest(request);

      // ȷ��ģ���Ѽ���
      await this.loadModel(request.model);
      const instance = this.loadedModels.get(request.model)!;
      instance.lastUsedTime = Date.now();

      // ������������
      const task: InferenceTask = {
        id: this.generateTaskId(),
        type: 'chat',
        modelId: request.model,
        status: 'running',
        startTime: Date.now()
      };

      this.runningTasks.set(task.id, task);

      // ������ʾ�ı�
      const prompt = this.buildPrompt(request.messages);
      
      // �ϲ�����
      const config: InferenceConfig = {
        maxTokens: request.maxTokens || instance.config.maxTokens,
        temperature: request.temperature || instance.config.temperature,
        topP: request.topP || instance.config.topP,
        topK: instance.config.topK,
        repetitionPenalty: instance.config.repetitionPenalty,
        stopTokens: request.stop || instance.config.stopTokens,
        seed: instance.config.seed,
        contextLength: instance.config.contextLength,
        batchSize: instance.config.batchSize
      };

      // ִ����ʽ������ģ�⣩
      await this.performStreamInference(instance, prompt, config, task, onChunk);

      // ��������״̬
      task.status = 'completed';
      task.endTime = Date.now();

      console.log(`[InferenceEngine] ��ʽ���첹ȫ���: ${task.id}`);

    } catch (error) {
      console.error('[InferenceEngine] ��ʽ���첹ȫʧ��:', error);
      throw new LingAIError(
        LingAIErrorCode.INFERENCE_FAILED,
        '推理失败',
        this.toErrorDetails(error, '推理失败')
      );
    }
  }

  /**
   * �ı�������
   */
  async createEmbedding(request: EmbeddingRequest): Promise<EmbeddingResponse> {
    try {
      console.log(`[InferenceEngine] ��ʼ�ı�������: ${request.model}`);

      // ȷ��ģ���Ѽ���
      await this.loadModel(request.model);
      const instance = this.loadedModels.get(request.model)!;
      instance.lastUsedTime = Date.now();

      // ������������
      const task: InferenceTask = {
        id: this.generateTaskId(),
        type: 'embedding',
        modelId: request.model,
        status: 'running',
        startTime: Date.now()
      };

      this.runningTasks.set(task.id, task);

      // ���������ı�
      const inputs: string[] = Array.isArray(request.input) ? request.input : [request.input];
      const embeddings: number[][] = [];

      for (const input of inputs) {
        // ִ����������ģ�⣩
        const embedding = await this.performEmbedding(instance, input, task);
        embeddings.push(embedding);
      }

      // ��������״̬
      task.status = 'completed';
      task.endTime = Date.now();
      task.inputTokens = inputs.reduce((sum, input) => sum + this.countTokens(input), 0);

      // ������Ӧ
      const embeddingData: EmbeddingData[] = embeddings.map((embedding, index) => {
        const item: EmbeddingData = {
          object: 'embedding',
          embedding: embedding,
          index: index
        };
        return item;
      });

      const usage: TokenUsage = {
        promptTokens: task.inputTokens!,
        completionTokens: 0,
        totalTokens: task.inputTokens!
      };

      const response: EmbeddingResponse = {
        object: 'list',
        data: embeddingData,
        model: request.model,
        usage: usage
      };

      console.log(`[InferenceEngine] �ı����������: ${task.id}`);
      return response;

    } catch (error) {
      console.error('[InferenceEngine] �ı�������ʧ��:', error);
      throw new LingAIError(
        LingAIErrorCode.INFERENCE_FAILED,
        '推理失败',
        this.toErrorDetails(error, '推理失败')
      );
    }
  }

  /**
   * ��֤��������
   */
  private validateChatRequest(request: ChatCompletionRequest): void {
    if (!request.model) {
      throw new LingAIError(
        LingAIErrorCode.INVALID_REQUEST,
        'ȱ��ģ�Ͳ���'
      );
    }

    if (!request.messages || request.messages.length === 0) {
      throw new LingAIError(
        LingAIErrorCode.INVALID_REQUEST,
        'ȱ����Ϣ����'
      );
    }

    if (request.maxTokens && (request.maxTokens < 1 || request.maxTokens > 8192)) {
      throw new LingAIError(
        LingAIErrorCode.INVALID_REQUEST,
        'maxTokens����������Χ'
      );
    }

    if (request.temperature && (request.temperature < 0 || request.temperature > 2)) {
      throw new LingAIError(
        LingAIErrorCode.INVALID_REQUEST,
        'temperature����������Χ'
      );
    }
  }

  /**
   * ������ʾ�ı�
   */
  private buildPrompt(messages: ChatMessage[]): string {
    let prompt = '';
    
    for (const message of messages) {
      switch (message.role) {
        case MessageRole.SYSTEM:
          prompt += `System: ${message.content}\n\n`;
          break;
        case MessageRole.USER:
          prompt += `Human: ${message.content}\n\n`;
          break;
        case MessageRole.ASSISTANT:
          prompt += `Assistant: ${message.content}\n\n`;
          break;
      }
    }
    
    prompt += 'Assistant: ';
    return prompt;
  }

  /**
   * ִ��������ģ��ʵ�֣�
   */
  private async performInference(
    instance: ModelInstance,
    prompt: string,
    config: InferenceConfig,
    task: InferenceTask
  ): Promise<InferenceResult> {
    // ģ�������ӳ�
    await new Promise<void>(resolve => setTimeout(resolve, 1000 + Math.random() * 2000));

    // ģ��������Ӧ
    const responses = [
      '感谢使用 LingAI，欢迎告诉我您的问题，我会尽力提供帮助。',
      '这是一个很有意思的问题，让我们从几个角度来分析。',
      '根据现有的数据，我可以为你提供以下几点建议供参考。',
      '非常感谢你的提问，我可以分享一些实际可行的解决办法。',
      '我已经整理了与该话题相关的资料，以下是综合性的说明。'
    ];

    const content = responses[Math.floor(Math.random() * responses.length)];
    
    const usage: TokenUsageStats = {
      promptTokens: this.countTokens(prompt),
      completionTokens: this.countTokens(content),
      totalTokens: this.countTokens(prompt) + this.countTokens(content)
    };
    
    const result: InferenceResult = {
      content: content,
      finishReason: 'stop',
      usage: usage
    };
    
    return result;
  }

  /**
   * ִ����ʽ������ģ��ʵ�֣�
   */
  private async performStreamInference(
    instance: ModelInstance,
    prompt: string,
    config: InferenceConfig,
    task: InferenceTask,
    onChunk: StreamCallback
  ): Promise<void> {
    const fullResponse = '����LingAI���֣��ܸ���Ϊ��������ʲô�ҿ��԰���������';
    const words = fullResponse.split('');
    
    for (let i = 0; i < words.length; i++) {
      // 模拟生成延迟
      await new Promise<void>(resolve => setTimeout(resolve, 50 + Math.random() * 100));
      
      const deltaContent: string = words[i];
      const delta: StreamDelta = {
        content: deltaContent
      };
      
      const choice: StreamChoice = {
        index: 0,
        delta: delta,
        finishReason: null
      };
      
      const chunk: StreamChunk = {
        id: `chatcmpl_${task.id}`,
        object: 'chat.completion.chunk',
        created: Math.floor(Date.now() / 1000),
        model: instance.modelId,
        choices: [choice]
      };
      
      onChunk.onData?.(JSON.stringify(chunk));
    }
    
    // 发送结束块
    const endDelta: StreamDelta = {};
    
    const endChoice: StreamChoice = {
      index: 0,
      delta: endDelta,
      finishReason: 'stop'
    };
    
    const endChunk: StreamChunk = {
      id: `chatcmpl_${task.id}`,
      object: 'chat.completion.chunk',
      created: Math.floor(Date.now() / 1000),
      model: instance.modelId,
      choices: [endChoice]
    };
    
    onChunk.onData?.(JSON.stringify(endChunk));
    onChunk.onComplete?.();
  }

  /**
   * ִ����������ģ��ʵ�֣�
   */
  private async performEmbedding(
    instance: ModelInstance,
    text: string,
    task: InferenceTask
  ): Promise<number[]> {
    // ģ���������ӳ�
    await new Promise<void>(resolve => setTimeout(resolve, 200 + Math.random() * 500));

    // ����ģ��������384ά��
    const embedding: number[] = [];
    for (let i = 0; i < 384; i++) {
      embedding.push((Math.random() - 0.5) * 2);
    }
    
    // ��һ������
    const norm = Math.sqrt(embedding.reduce((sum, val) => sum + val * val, 0));
    return embedding.map(val => val / norm);
  }

  /**
   * ����Token��������ʵ�֣�
   */
  private countTokens(text: string): number {
    // �򵥵�Token���㣺���ո�ͱ��ָ�
    return text.split(/\s+|[.,!?;:]/).filter(token => token.length > 0).length;
  }

  /**
   * ж���������ʹ�õ�ģ��
   */
  private async unloadLeastRecentlyUsedModel(): Promise<void> {
    let oldestTime = Date.now();
    let oldestModelId = '';
    
    const modelEntries: Array<[string, ModelInstance]> = Array.from(this.loadedModels.entries());
    for (let i = 0; i < modelEntries.length; i++) {
      const modelId = modelEntries[i][0];
      const instance = modelEntries[i][1];
      if (instance.lastUsedTime < oldestTime) {
        oldestTime = instance.lastUsedTime;
        oldestModelId = modelId;
      }
    }
    
    if (oldestModelId) {
      await this.unloadModel(oldestModelId);
    }
  }

  /**
   * ����������ʱ��
   */
  private startCleanupTimer(): void {
    setInterval(() => {
      this.cleanupUnusedModels();
      this.cleanupCompletedTasks();
    }, this.modelCleanupInterval);
  }

  /**
   * ����δʹ�õ�ģ��
   */
  private async cleanupUnusedModels(): Promise<void> {
    const now = Date.now();
    const modelsToUnload: string[] = [];
    
    const modelEntries2: Array<[string, ModelInstance]> = Array.from(this.loadedModels.entries());
    for (let i = 0; i < modelEntries2.length; i++) {
      const modelId = modelEntries2[i][0];
      const instance = modelEntries2[i][1];
      if (now - instance.lastUsedTime > this.modelCleanupInterval) {
        modelsToUnload.push(modelId);
      }
    }
    
    for (const modelId of modelsToUnload) {
      try {
        await this.unloadModel(modelId);
        console.log(`[InferenceEngine] �Զ�ж��δʹ��ģ��: ${modelId}`);
      } catch (error) {
        console.error(`[InferenceEngine] �Զ�ж��ģ��ʧ��: ${modelId}`, error);
      }
    }
  }

  /**
   * ��������ɵ�����
   */
  private cleanupCompletedTasks(): void {
    const now = Date.now();
    const tasksToRemove: string[] = [];
    
    const taskEntries: Array<[string, InferenceTask]> = Array.from(this.runningTasks.entries());
    for (let i = 0; i < taskEntries.length; i++) {
      const taskId = taskEntries[i][0];
      const task = taskEntries[i][1];
      if (task.status === 'completed' || task.status === 'failed') {
        if (task.endTime && now - task.endTime > 60000) { // 1���Ӻ�����
          tasksToRemove.push(taskId);
        }
      }
    }
    
    for (const taskId of tasksToRemove) {
      this.runningTasks.delete(taskId);
    }
  }

  /**
   * ��������ID
   */
  private generateTaskId(): string {
    return `inf_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
  }

  /**
   * ��ȡ����״̬
   */
  getEngineStatus(): EngineStatus {
    const status: EngineStatus = {
      loadedModels: this.loadedModels.size,
      runningTasks: Array.from(this.runningTasks.values())
        .filter((task: InferenceTask): boolean => task.status === 'running').length,
      maxConcurrentTasks: this.maxConcurrentTasks,
      maxLoadedModels: this.maxLoadedModels
    };
    return status;
  }

  /**
   * ��ȡ�Ѽ��ص�ģ���б�
   */
  getLoadedModels(): string[] {
    return Array.from(this.loadedModels.keys());
  }

  /**
   * ��ȡ�����е�����
   */
  getRunningTasks(): InferenceTask[] {
    return Array.from(this.runningTasks.values())
      .filter((task: InferenceTask) => task.status === 'running');
  }

  /**
   * ������Դ
   */
  async cleanup(): Promise<void> {
    try {
      // ж������ģ��
      const modelIds = Array.from(this.loadedModels.keys());
      for (const modelId of modelIds) {
        await this.unloadModel(modelId);
      }

      // ��������
      this.runningTasks.clear();

      console.log('[InferenceEngine] ��Դ�������');
    } catch (error) {
      console.error('[InferenceEngine] ��Դ����ʧ��:', error);
    }
  }

  /**
   * 统一将未知异常安全转为 Error
   */
  private toError(error: Error | string | object): Error {
    if (error instanceof Error) {
      return error;
    }
    if (typeof error === 'string') {
      return new Error(error);
    }
    try {
      return new Error(JSON.stringify(error));
    } catch (_e) {
      return new Error('Unknown error');
    }
  }

  /**
   * 将未知错误安全地转换为 ErrorDetails
   */
  private toErrorDetails(error: Error | string | object, fallbackMessage?: string): ErrorDetails {
    let original: string = fallbackMessage ?? 'Unknown error';
    if (typeof error === 'string') {
      original = error;
    } else if (error instanceof Error) {
      original = error.message;
    } else {
      try { original = JSON.stringify(error); } catch (_e) { /* noop */ }
    }
    return { originalError: original, timestamp: Date.now() } as ErrorDetails;
  }
}
