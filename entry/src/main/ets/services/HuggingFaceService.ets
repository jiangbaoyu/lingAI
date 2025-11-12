/**
 * HuggingFace 服务（离线本地实现，符合 ArkTS18 规范）
 * 该实现提供固定的数据集和文件生成逻辑，便于在严格类型环境下调试业务流程。
 */

import fs from '@ohos.file.fs';
import { LingAIError, LingAIErrorCode, ErrorDetails } from '../sdk/types/LingAITypes';

/**
 * 模型文件信息
 */
export interface HuggingFaceFile {
  rfilename: string;
  size: number;
}

/**
 * 模型信息
 */
export interface HuggingFaceModelInfo {
  id: string;
  modelId: string;
  author?: string;
  sha: string;
  lastModified: string;
  isPrivate: boolean;
  isDisabled: boolean;
  isGated: boolean;
  downloads: number;
  likes: number;
  tags: string[];
  pipeline_tag?: string;
  createdAt: string;
  siblings?: HuggingFaceFile[];
}

/**
 * LFS 信息（兼容旧结构）
 */
export interface LfsInfo {
  oid: string;
  size: number;
  pointerSize: number;
}

/**
 * 搜索参数
 */
export interface SearchParams {
  search?: string;
  author?: string;
  filter?: string;
  sort?: 'downloads' | 'likes' | 'updated' | 'created';
  direction?: 'asc' | 'desc';
  limit?: number;
}

/**
 * 下载进度监听器
 */
export interface DownloadProgressListener {
  onProgress(progress: number, downloaded: number, total: number): void;
}

/**
 * 下载进度监听器实现类
 */
export class DownloadProgressListenerImpl implements DownloadProgressListener {
  private callback: (progress: number, downloaded: number, total: number) => void;

  constructor(callback: (progress: number, downloaded: number, total: number) => void) {
    this.callback = callback;
  }

  onProgress(progress: number, downloaded: number, total: number): void {
    this.callback(progress, downloaded, total);
  }
}

/**
 * 默认模型数据源
 */
class DefaultModelProvider {
  static build(): HuggingFaceModelInfo[] {
    const chatFile: HuggingFaceFile = {
      rfilename: 'model.gguf',
      size: 4 * 1024 * 1024
    };

    const chatModel: HuggingFaceModelInfo = {
      id: 'lingai_example_chat',
      modelId: 'lingai/example-chat',
      author: 'LingAI',
      sha: '0000000000000000000000000000000000000000',
      lastModified: '2024-01-01T00:00:00Z',
      isPrivate: false,
      isDisabled: false,
      isGated: false,
      downloads: 1200,
      likes: 540,
      tags: ['text-generation', 'chat'],
      pipeline_tag: 'text-generation',
      createdAt: '2024-01-01T00:00:00Z',
      siblings: [chatFile]
    };

    const embeddingFile: HuggingFaceFile = {
      rfilename: 'model.onnx',
      size: 2 * 1024 * 1024
    };

    const embeddingModel: HuggingFaceModelInfo = {
      id: 'lingai_example_embedding',
      modelId: 'lingai/example-embedding',
      author: 'LingAI',
      sha: '1111111111111111111111111111111111111111',
      lastModified: '2024-02-01T00:00:00Z',
      isPrivate: false,
      isDisabled: false,
      isGated: false,
      downloads: 860,
      likes: 320,
      tags: ['feature-extraction'],
      pipeline_tag: 'feature-extraction',
      createdAt: '2024-02-01T00:00:00Z',
      siblings: [embeddingFile]
    };

    return [chatModel, embeddingModel];
  }
}

/**
 * 目录处理工具
 */
class DirectoryHelper {
  static ensureDirectory(path: string): void {
    try {
      // 使用 try/catch 判断目录是否存在，避免将 accessSync 当作布尔值
      fs.accessSync(path);
    } catch (_e) {
      fs.mkdirSync(path, true);
    }
  }

  static ensureParent(filePath: string): void {
    const index = filePath.lastIndexOf('/');
    if (index <= 0) {
      return;
    }
    const dir = filePath.substring(0, index);
    DirectoryHelper.ensureDirectory(dir);
  }
}

/**
 * 下载工具
 */
class DownloadWriter {
  static writePlaceholder(path: string, size: number, listener?: DownloadProgressListener): void {
    DirectoryHelper.ensureParent(path);
    const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.WRITE_ONLY);
    const chunkSize = 32 * 1024;
    let written = 0;

    while (written < size) {
      const remain = size - written;
      const current = remain > chunkSize ? chunkSize : remain;
      const buffer = new Uint8Array(current);
      fs.writeSync(file.fd, buffer);
      written += current;

      const progress = size === 0 ? 100 : Math.min(100, Math.floor((written * 100) / size));
      if (listener) {
        listener.onProgress(progress, written, size);
      }
    }

    if (size === 0 && listener) {
      listener.onProgress(100, 0, 0);
    }

    fs.closeSync(file);
  }
}

/**
 * HuggingFace 服务
 */
export class HuggingFaceService {
  private static readonly MODELS: HuggingFaceModelInfo[] = DefaultModelProvider.build();
  private accessToken?: string;

  constructor(accessToken?: string) {
    this.accessToken = accessToken;
  }

  async searchModels(params: SearchParams = {}): Promise<HuggingFaceModelInfo[]> {
    const matched: HuggingFaceModelInfo[] = [];
    for (const model of HuggingFaceService.MODELS) {
      if (this.matches(model, params)) {
        matched.push(this.clone(model));
      }
    }

    if (params.sort) {
      this.sortModels(matched, params.sort, params.direction || 'desc');
    }

    if (params.limit && params.limit > 0 && matched.length > params.limit) {
      return matched.slice(0, params.limit);
    }

    return matched;
  }

  async getModelInfo(modelId: string): Promise<HuggingFaceModelInfo> {
    const model = this.findModel(modelId);
    if (!model) {
      throw new LingAIError(
        LingAIErrorCode.MODEL_NOT_FOUND,
        `模型不存在: ${modelId}`
      );
    }
    return this.clone(model);
  }

  async getModelFiles(modelId: string, revision: string = 'main'): Promise<HuggingFaceFile[]> {
    const model = await this.getModelInfo(modelId);
    const siblings: HuggingFaceFile[] = [];
    if (model.siblings) {
      for (const file of model.siblings) {
        siblings.push({
          rfilename: file.rfilename,
          size: file.size
        });
      }
    }
    return siblings;
  }

  async downloadModelFile(
    modelId: string,
    filename: string,
    localPath: string,
    listener?: DownloadProgressListener,
    revision: string = 'main',
    expectedSize?: number
  ): Promise<void> {
    const files = await this.getModelFiles(modelId, revision);
    let targetSize = expectedSize || 0;
    for (const file of files) {
      if (file.rfilename === filename) {
        targetSize = file.size;
        break;
      }
    }

    try {
      DownloadWriter.writePlaceholder(localPath, targetSize, listener);
    } catch (error) {
      throw new LingAIError(
        LingAIErrorCode.DOWNLOAD_FAILED,
        '创建模型文件失败',
        this.toErrorDetails(error, '写入失败')
      );
    }
  }

  async downloadModel(
    modelId: string,
    localDir: string,
    listener?: DownloadProgressListener,
    revision: string = 'main',
    includePatterns?: string[],
    excludePatterns?: string[]
  ): Promise<string[]> {
    const files = await this.getModelFiles(modelId, revision);
    const targets: HuggingFaceFile[] = [];

    for (const file of files) {
      if (this.shouldInclude(file.rfilename, includePatterns, excludePatterns)) {
        targets.push(file);
      }
    }

    DirectoryHelper.ensureDirectory(localDir);
    const savedPaths: string[] = [];
    const totalFiles = targets.length;
    let completed = 0;

    for (const file of targets) {
      const targetPath = `${localDir}/${file.rfilename}`;
      let progressWrapper: DownloadProgressListener | undefined = undefined;
      if (listener) {
        const wrapperImpl = (progress: number, downloaded: number, total: number): void => {
          const base = totalFiles === 0 ? 100 : Math.floor((completed * 100) / totalFiles);
          const contribution = totalFiles === 0 ? 0 : Math.floor(progress / totalFiles);
          listener.onProgress(Math.min(100, base + contribution), downloaded, total);
        };
        progressWrapper = new DownloadProgressListenerImpl(wrapperImpl);
      }
      await this.downloadModelFile(
        modelId,
        file.rfilename,
        targetPath,
        progressWrapper,
        revision,
        file.size
      );
      completed += 1;
      savedPaths.push(targetPath);
      if (listener) {
        listener.onProgress(Math.min(100, Math.floor((completed * 100) / (totalFiles === 0 ? 1 : totalFiles))), file.size, file.size);
      }
    }

    if (listener) {
      listener.onProgress(100, 0, 0);
    }

    return savedPaths;
  }

  async getRecommendedModels(): Promise<HuggingFaceModelInfo[]> {
    return this.cloneList(HuggingFaceService.MODELS);
  }

  setAccessToken(token: string): void {
    this.accessToken = token;
  }

  clearAccessToken(): void {
    this.accessToken = undefined;
  }

  destroy(): void {
    // 离线实现无需销毁资源
  }

  private matches(model: HuggingFaceModelInfo, params: SearchParams): boolean {
    if (params.search && params.search.trim().length > 0) {
      const keyword = params.search.toLowerCase();
      const matchName = model.modelId.toLowerCase().includes(keyword);
      const matchAuthor = model.author ? model.author.toLowerCase().includes(keyword) : false;
      if (!matchName && !matchAuthor) {
        return false;
      }
    }

    if (params.author && params.author.trim().length > 0) {
      if (!model.author || model.author.toLowerCase() !== params.author.toLowerCase()) {
        return false;
      }
    }

    if (params.filter && params.filter.trim().length > 0) {
      let matched = false;
      const filterValue = params.filter.toLowerCase();
      for (const tag of model.tags) {
        if (tag.toLowerCase() === filterValue) {
          matched = true;
          break;
        }
      }
      if (!matched) {
        return false;
      }
    }

    return true;
  }

  private sortModels(models: HuggingFaceModelInfo[], sort: 'downloads' | 'likes' | 'updated' | 'created', direction: 'asc' | 'desc'): void {
    models.sort((first: HuggingFaceModelInfo, second: HuggingFaceModelInfo) => {
      let value = 0;
      switch (sort) {
        case 'downloads':
          value = first.downloads - second.downloads;
          break;
        case 'likes':
          value = first.likes - second.likes;
          break;
        case 'updated':
          value = this.compareDate(first.lastModified, second.lastModified);
          break;
        case 'created':
          value = this.compareDate(first.createdAt, second.createdAt);
          break;
      }
      return direction === 'asc' ? value : -value;
    });
  }

  private compareDate(first: string, second: string): number {
    const firstTime = Date.parse(first);
    const secondTime = Date.parse(second);
    if (firstTime === secondTime) {
      return 0;
    }
    return firstTime > secondTime ? 1 : -1;
  }

  private shouldInclude(filename: string, includePatterns?: string[], excludePatterns?: string[]): boolean {
    if (includePatterns && includePatterns.length > 0) {
      let matched = false;
      for (const pattern of includePatterns) {
        if (this.matchPattern(filename, pattern)) {
          matched = true;
          break;
        }
      }
      if (!matched) {
        return false;
      }
    }

    if (excludePatterns && excludePatterns.length > 0) {
      for (const pattern of excludePatterns) {
        if (this.matchPattern(filename, pattern)) {
          return false;
        }
      }
    }

    if (!includePatterns && !excludePatterns) {
      const lower = filename.toLowerCase();
      return lower.endsWith('.gguf') ||
        lower.endsWith('.bin') ||
        lower.endsWith('.onnx') ||
        lower.endsWith('.json') ||
        lower === 'config.json' ||
        lower === 'tokenizer.json';
    }

    return true;
  }

  private matchPattern(filename: string, pattern: string): boolean {
    let regexSource = '';
    for (let i = 0; i < pattern.length; i++) {
      const char = pattern.charAt(i);
      if (char === '.') {
        regexSource += '\\.';
      } else if (char === '*') {
        regexSource += '.*';
      } else if (char === '?') {
        regexSource += '.';
      } else {
        regexSource += char;
      }
    }
    const regex = new RegExp(`^${regexSource}$`);
    return regex.test(filename);
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
      try { original = JSON.stringify(error); } catch (_) { /* noop */ }
    }
    return {
      originalError: original,
      timestamp: Date.now()
    } as ErrorDetails;
  }

  private findModel(modelId: string): HuggingFaceModelInfo | undefined {
    for (const model of HuggingFaceService.MODELS) {
      if (model.modelId === modelId || model.id === modelId) {
        return model;
      }
    }
    return undefined;
  }

  private cloneList(source: HuggingFaceModelInfo[]): HuggingFaceModelInfo[] {
    const result: HuggingFaceModelInfo[] = [];
    for (const item of source) {
      result.push(this.clone(item));
    }
    return result;
  }

  private clone(model: HuggingFaceModelInfo): HuggingFaceModelInfo {
    const copy: HuggingFaceModelInfo = {
      id: model.id,
      modelId: model.modelId,
      author: model.author,
      sha: model.sha,
      lastModified: model.lastModified,
      isPrivate: model.isPrivate,
      isDisabled: model.isDisabled,
      isGated: model.isGated,
      downloads: model.downloads,
      likes: model.likes,
      tags: [],
      pipeline_tag: model.pipeline_tag,
      createdAt: model.createdAt,
      siblings: undefined
    };

    for (const tag of model.tags) {
      copy.tags.push(tag);
    }

    if (model.siblings) {
      copy.siblings = [];
      for (const file of model.siblings) {
        copy.siblings.push({
          rfilename: file.rfilename,
          size: file.size
        });
      }
    }

    return copy;
  }
}

