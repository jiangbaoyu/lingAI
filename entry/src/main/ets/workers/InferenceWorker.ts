/**
 * 推理Worker
 * 在独立线程中处理模型推理任务，避免阻塞主线程
 */

import worker, { MessageEvents, ErrorEvent } from '@ohos.worker';

// 通用JSON类型，避免使用unknown/any
type JsonPrimitive = string | number | boolean | null;
interface JsonObject { [key: string]: JsonValue }
type JsonArray = JsonValue[];
type JsonValue = JsonPrimitive | JsonObject | JsonArray;

interface GlobalWithStatus {
  getWorkerStatus: () => { modelLoaded: boolean; modelPath?: string; loadTime?: number; uptime: number };
}

/**
 * Worker消息接口
 */
interface WorkerMessage {
  type: 'loadModel' | 'unloadModel' | 'inference' | 'embedding' | 'streamInference';
  id?: string;
  modelPath?: string;
  config?: JsonObject;
  prompt?: string;
  text?: string;
  data?: JsonObject;
}

/**
 * Worker响应接口
 */
interface WorkerResponse {
  type: 'modelLoaded' | 'modelUnloaded' | 'inferenceResult' | 'embeddingResult' | 'streamChunk' | 'error';
  id?: string;
  success: boolean;
  data?: string;
  error?: string;
}

/**
 * 模型状态接口
 */
interface ModelState {
  isLoaded: boolean;
  modelPath?: string;
  config?: JsonObject;
  loadTime?: number;
}

interface InferenceResult {
  content: string;
  finishReason: string;
  usage: {
    promptTokens: number;
    completionTokens: number;
    totalTokens: number;
  };
}

/**
 * 推理Worker类
 */
class InferenceWorker {
  private modelState: ModelState = { isLoaded: false };
  private workerPort: typeof worker.workerPort;

  constructor() {
    this.workerPort = worker.workerPort;
    this.setupMessageHandler();
    console.log('[InferenceWorker] Worker初始化完成');
  }

  /**
   * 设置消息处理器
   */
  private setupMessageHandler(): void {
    this.workerPort.onmessage = (event: MessageEvents) => {
      this.handleMessage(event.data as WorkerMessage);
    };

    this.workerPort.onmessageerror = (event: ErrorEvent) => {
      console.error('[InferenceWorker] 消息错误:', event);
      this.sendResponse({
        type: 'error',
        success: false,
        error: '消息处理失败'
      });
    };
  }

  /**
   * 处理消息
   */
  private async handleMessage(message: WorkerMessage): Promise<void> {
    try {
      console.log(`[InferenceWorker] 收到消息: ${message.type}`);

      switch (message.type) {
        case 'loadModel':
          await this.handleLoadModel(message);
          break;
        case 'unloadModel':
          await this.handleUnloadModel(message);
          break;
        case 'inference':
          await this.handleInference(message);
          break;
        case 'embedding':
          await this.handleEmbedding(message);
          break;
        case 'streamInference':
          await this.handleStreamInference(message);
          break;
        default:
          throw new Error(`未知消息类型: ${message.type}`);
      }
    } catch (error) {
      console.error('[InferenceWorker] 处理消息失败:', error);
      this.sendResponse({
        type: 'error',
        id: message.id,
        success: false,
        error: error instanceof Error ? error.message : '未知错误'
      });
    }
  }

  /**
   * 加载模型
   */
  private async handleLoadModel(message: WorkerMessage): Promise<void> {
    try {
      if (!message.modelPath) {
        throw new Error('缺少模型路径');
      }

      console.log(`[InferenceWorker] 开始加载模型: ${message.modelPath}`);

      // 如果已有模型已加载，先卸载
      if (this.modelState.isLoaded) {
        await this.unloadCurrentModel();
      }

      // 模拟模型加载过程
      await this.simulateModelLoading(message.modelPath, message.config || {});

      // 更新模型状态
      this.modelState = {
        isLoaded: true,
        modelPath: message.modelPath,
        config: message.config,
        loadTime: Date.now()
      };

      this.sendResponse({
        type: 'modelLoaded',
        id: message.id,
        success: true,
        data: JSON.stringify({
          modelPath: message.modelPath,
          loadTime: this.modelState.loadTime
        })
      });

      console.log(`[InferenceWorker] 模型加载完成: ${message.modelPath}`);

    } catch (error) {
      console.error('[InferenceWorker] 加载模型失败:', error);
      this.sendResponse({
        type: 'error',
        id: message.id,
        success: false,
        error: error instanceof Error ? error.message : '加载模型失败'
      });
    }
  }

  /**
   * 卸载模型
   */
  private async handleUnloadModel(message: WorkerMessage): Promise<void> {
    try {
      console.log('[InferenceWorker] 开始卸载模型');

      await this.unloadCurrentModel();

      this.sendResponse({
        type: 'modelUnloaded',
        id: message.id,
        success: true
      });

      console.log('[InferenceWorker] 模型卸载完成');

    } catch (error) {
      console.error('[InferenceWorker] 卸载模型失败:', error);
      this.sendResponse({
        type: 'error',
        id: message.id,
        success: false,
        error: error instanceof Error ? error.message : '卸载模型失败'
      });
    }
  }

  /**
   * 文本推理
   */
  private async handleInference(message: WorkerMessage): Promise<void> {
    try {
      if (!this.modelState.isLoaded) {
        throw new Error('模型未加载');
      }

      if (!message.prompt) {
        throw new Error('缺少提示文本');
      }

      console.log('[InferenceWorker] 开始推理');

      // ִ������
      const content = await this.performInference(message.prompt, message.config || {});

      const result: InferenceResult = {
        content,
        finishReason: 'stop',
        usage: {
          promptTokens: this.countTokens(message.prompt),
          completionTokens: this.countTokens(content),
          totalTokens: this.countTokens(message.prompt) + this.countTokens(content)
        }
      };

      this.sendResponse({
        type: 'inferenceResult',
        id: message.id,
        success: true,
        data: JSON.stringify(result)
      });

      console.log('[InferenceWorker] 推理完成');

    } catch (error) {
      console.error('[InferenceWorker] 推理失败:', error);
      this.sendResponse({
        type: 'error',
        id: message.id,
        success: false,
        error: error instanceof Error ? error.message : '推理失败'
      });
    }
  }

  /**
   * 文本嵌入
   */
  private async handleEmbedding(message: WorkerMessage): Promise<void> {
    try {
      if (!this.modelState.isLoaded) {
        throw new Error('模型未加载');
      }

      if (!message.text) {
        throw new Error('缺少文本内容');
      }

      console.log('[InferenceWorker] 开始嵌入');

      // ִ��������
      const embedding = await this.performEmbedding(message.text);

      this.sendResponse({
        type: 'embeddingResult',
        id: message.id,
        success: true,
        data: JSON.stringify({ embedding })
      });

      console.log('[InferenceWorker] 嵌入完成');

    } catch (error) {
      console.error('[InferenceWorker] 嵌入失败:', error);
      this.sendResponse({
        type: 'error',
        id: message.id,
        success: false,
        error: error instanceof Error ? error.message : '嵌入失败'
      });
    }
  }

  /**
   * 流式推理
   */
  private async handleStreamInference(message: WorkerMessage): Promise<void> {
    try {
      if (!this.modelState.isLoaded) {
        throw new Error('模型未加载');
      }

      if (!message.prompt) {
        throw new Error('缺少提示文本');
      }

      console.log('[InferenceWorker] 开始流式推理');

      // ִ����ʽ����
      await this.performStreamInference(message.prompt, message.config || {}, message.id);

      console.log('[InferenceWorker] 流式推理完成');

    } catch (error) {
      console.error('[InferenceWorker] 流式推理失败:', error);
      this.sendResponse({
        type: 'error',
        id: message.id,
        success: false,
        error: error instanceof Error ? error.message : '流式推理失败'
      });
    }
  }

  /**
   * 模拟模型加载
   */
  private async simulateModelLoading(modelPath: string, config: JsonObject): Promise<void> {
    // 模拟加载时间（根据模型大小可调整）
    const loadingTime = 2000 + Math.random() * 3000; // 2-5秒
    
    console.log(`[InferenceWorker] 模拟加载模型，预计耗时: ${Math.round(loadingTime)}ms`);
    
    // 分阶段模拟加载步骤
    const stages = [
      '读取模型文件',
      '解析模型结构',
      '初始化运行环境',
      '加载模型参数',
      '优化计算图',
      '准备推理任务'
    ];

    const stageTime = loadingTime / stages.length;
    
    for (let i = 0; i < stages.length; i++) {
      await new Promise(resolve => setTimeout(resolve, stageTime));
      console.log(`[InferenceWorker] ${stages[i]}... (${i + 1}/${stages.length})`);
    }

    console.log('[InferenceWorker] 模型加载模拟完成');
  }

  /**
   * 卸载当前模型
   */
  private async unloadCurrentModel(): Promise<void> {
    if (this.modelState.isLoaded) {
      // 模拟卸载过程
      await new Promise(resolve => setTimeout(resolve, 500));
      
      this.modelState = { isLoaded: false };
      console.log('[InferenceWorker] 当前模型已卸载');
    }
  }

  /**
   * 执行文本推理
   */
  private async performInference(prompt: string, config: JsonObject): Promise<string> {
    // 模拟推理时间
    const inferenceTime = 1000 + Math.random() * 2000; // 1-3秒
    await new Promise(resolve => setTimeout(resolve, inferenceTime));

    // 生成模拟响应
    const responses = [
      '你好，我是 LingAI。可以描述下你的问题吗？',
      '这是个很有意思的话题。我们可以从以下方面展开...',
      '针对你的问题，我建议可以考虑以下几步：\n1. 先分析问题的根因\n2. 制定详细的解决方案\n3. 实施后评估效果',
      '感谢你的详细描述。我们可以从系统、业务、运营三个角度来分析...',
      '为了更好地帮助你，我可以提供一些可执行的建议。首先明确目标，然后逐步推进实施计划。'
    ];

    const content = responses[Math.floor(Math.random() * responses.length)];
    
    return content;
  }

  /**
   * 执行文本嵌入
   */
  private async performEmbedding(text: string): Promise<number[]> {
    // 模拟嵌入计算时间
    const embeddingTime = 200 + Math.random() * 500; // 200-700ms
    await new Promise(resolve => setTimeout(resolve, embeddingTime));

    // 模拟生成 384 维嵌入
    const embedding: number[] = [];
    const seed = this.hashString(text); // 基于文本生成种子，确保相同文本得到相同结果
    
    for (let i = 0; i < 384; i++) {
      // 使用伪随机数生成，确保复现实验
      const value = this.seededRandom(seed + i) * 2 - 1; // -1 到 1 之间
      embedding.push(value);
    }
    
    // 归一化向量
    const norm = Math.sqrt(embedding.reduce((sum, val) => sum + val * val, 0));
    return embedding.map(val => val / norm);
  }

  /**
   * 执行流式推理
   */
  private async performStreamInference(prompt: string, config: JsonObject, requestId?: string): Promise<void> {
    const fullResponse = '你好，我是 LingAI。我可以帮助你，下面是详细的解释与建议。';
    const words = fullResponse.split('');
    
    for (let i = 0; i < words.length; i++) {
      // 模拟流式延迟
      await new Promise(resolve => setTimeout(resolve, 50 + Math.random() * 100));
      
      // 发送流式数据块
      this.sendResponse({
        type: 'streamChunk',
        id: requestId,
        success: true,
        data: JSON.stringify({
          content: words[i],
          index: i,
          isComplete: false
        })
      });
    }
    
    // ������ɱ��
    this.sendResponse({
      type: 'streamChunk',
      id: requestId,
      success: true,
      data: JSON.stringify({
        content: '',
        index: words.length,
        isComplete: true,
        finishReason: 'stop',
        usage: {
          promptTokens: this.countTokens(prompt),
          completionTokens: this.countTokens(fullResponse),
          totalTokens: this.countTokens(prompt) + this.countTokens(fullResponse)
        }
      })
    });
  }

  /**
   * 发送响应
   */
  private sendResponse(response: WorkerResponse): void {
    try {
      this.workerPort.postMessage(response);
    } catch (error) {
      console.error('[InferenceWorker] 发送响应失败:', error instanceof Error ? error.message : String(error));
    }
  }

  /**
   * 统计 Token 的简单实现
   */
  private countTokens(text: string): number {
    return text.split(/\s+|[.,!?;:]/).filter(token => token.length > 0).length;
  }

  /**
   * 字符串哈希实现
   */
  private hashString(str: string): number {
    let hash = 0;
    for (let i = 0; i < str.length; i++) {
      const char = str.charCodeAt(i);
      hash = ((hash << 5) - hash) + char;
      hash = hash & hash; // 转为 32 位整数
    }
    return Math.abs(hash);
  }

  /**
   * 伪随机数实现（基于种子）
   */
  private seededRandom(seed: number): number {
    const x = Math.sin(seed) * 10000;
    return x - Math.floor(x);
  }

  /**
   * 获取 Worker 状态
   */
  getWorkerStatus(): { modelLoaded: boolean; modelPath?: string; loadTime?: number; uptime: number } {
    return {
      modelLoaded: this.modelState.isLoaded,
      modelPath: this.modelState.modelPath,
      loadTime: this.modelState.loadTime,
      uptime: Date.now() - (this.modelState.loadTime || Date.now())
    };
  }
}

// 创建 Worker 实例
const inferenceWorker = new InferenceWorker();

// 挂载 Worker 状态查询到全局，便于调试
(globalThis as GlobalWithStatus).getWorkerStatus = () => inferenceWorker.getWorkerStatus();

