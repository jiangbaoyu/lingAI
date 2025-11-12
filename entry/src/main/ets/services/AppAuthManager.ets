/**
 * 应用认证管理器
 * 负责应用注册、API Key管理、权限验证和配额控制
 */

import common from '@ohos.app.ability.common';
import {
  AppRegistration,
  AppQuota,
  LingAIError,
  LingAIErrorCode,
  ErrorDetails
} from '../sdk/types/LingAITypes';
import { DatabaseManager, ExtendedUsageStats, SaveApiKeyParams } from './DatabaseManager';

/**
 * API Key信息接口
 */
interface ApiKeyInfo {
  keyId: string;
  appId: string;
  keyHash: string;
  keyPrefix: string;
  permissions: string[];
  isActive: boolean;
  createdAt: number;
  lastUsedAt?: number;
  expiresAt?: number;
  rateLimit: RateLimitConfig;
}

/**
 * 扩展的API Key信息接口
 */
interface ExtendedApiKeyInfo extends ApiKeyInfo {
  expiresAt?: number;
  rateLimit: RateLimitConfig;
}
/**
 * 使用统计接口
 */
interface UsageStats {
  appId: string;
  date: string;
  requests: number;
  tokens: number;
  errors: number;
  lastUpdated: number;
}

/**
 * 应用注册结果接口
 */
interface AppRegistrationResult extends AppRegistration {
  apiKey: string;
}

/**
 * 速率限制信息接口
 */
interface RateLimitInfo {
  count: number;
  resetTime: number;
}

/**
 * 速率限制配置接口
 */
interface RateLimitConfig {
  requestsPerMinute: number;
  requestsPerHour: number;
  requestsPerDay: number;
}

/**
 * 权限类型枚举
 */
enum Permission {
  CHAT_COMPLETION = 'chat.completion',
  EMBEDDING = 'embedding',
  MODEL_LIST = 'model.list',
  MODEL_INFO = 'model.info',
  STREAM_CHAT = 'chat.stream'
}

/**
 * 应用认证管理器类
 */
export class AppAuthManager {
  private context: common.Context;
  private databaseManager: DatabaseManager;
  private apiKeyCache: Map<string, ExtendedApiKeyInfo> = new Map();
  private usageCache: Map<string, UsageStats> = new Map();
  private rateLimitCache: Map<string, RateLimitInfo> = new Map();

  constructor(context: common.Context, databaseManager: DatabaseManager) {
    this.context = context;
    this.databaseManager = databaseManager;
    
    // 启动定期清理任务
    this.startCleanupTimer();
  }

  /**
   * 注册新应用
   */
  async registerApp(
    appName: string,
    packageName: string,
    description?: string,
    permissions?: string[]
  ): Promise<AppRegistrationResult> {
    try {
      console.log(`[AppAuthManager] 注册应用: ${appName} (${packageName})`);

      // 检查应用是否已存在
      const existingApp = await this.databaseManager.getAppByPackageName(packageName);
      if (existingApp) {
        throw new LingAIError(
          LingAIErrorCode.APP_ALREADY_EXISTS,
          '应用已存在'
        );
      }

      // 生成应用ID
      const appId = this.generateAppId();

      // 创建默认配额
      const defaultQuota: AppQuota = {
        dailyRequests: 10000,
        requestsPerMinute: 60,
        requestsPerHour: 1000,
        requestsPerDay: 10000,
        tokensPerDay: 100000,
        maxConcurrentRequests: 5,
        maxTokens: 100000
      };

      // 设置默认权限
      const defaultPermissions = permissions || [
        Permission.CHAT_COMPLETION,
        Permission.EMBEDDING,
        Permission.MODEL_LIST,
        Permission.MODEL_INFO
      ];

      // 创建应用注册信息
      const registration: AppRegistration = {
        appId: appId,
        appName: appName,
        bundleName: packageName,
        packageName: packageName,
        description: description || '',
        permissions: defaultPermissions,
        quota: defaultQuota,
        registeredAt: Date.now(),
        lastActiveAt: Date.now(),
        createdAt: Date.now(),
        lastUsedAt: Date.now(),
        isActive: true,
        status: 'active'
      };

      // 保存到数据库
      await this.databaseManager.saveApp(registration);

      // 生成初始API Key
      const apiKey = await this.generateApiKey(appId, defaultPermissions);

      console.log(`[AppAuthManager] 应用注册成功: ${appId}`);
      
      const result: AppRegistrationResult = {
        appId: registration.appId,
        appName: registration.appName,
        bundleName: registration.bundleName,
        packageName: registration.packageName,
        description: registration.description,
        permissions: registration.permissions,
        quota: registration.quota,
        registeredAt: registration.registeredAt,
        lastActiveAt: registration.lastActiveAt,
        createdAt: registration.createdAt,
        lastUsedAt: registration.lastUsedAt,
        isActive: registration.isActive,
        status: registration.status,
        apiKey: apiKey
      };
      return result;

    } catch (error) {
      console.error('[AppAuthManager] 注册应用失败:', error);
      throw new LingAIError(
        LingAIErrorCode.APP_REGISTRATION_FAILED,
        '注册应用失败',
        this.toErrorDetails(error, '注册应用失败')
      );
    }
  }

  /**
   * 生成API Key
   */
  async generateApiKey(appId: string, permissions: string[]): Promise<string> {
    try {
      // 检查应用是否存在
      const app = await this.databaseManager.getApp(appId);
      if (!app) {
        throw new LingAIError(
          LingAIErrorCode.APP_NOT_FOUND,
          '应用不存在'
        );
      }

      // 生成随机密钥
      const keyData = this.generateRandomBytes(32);
      const keyString = this.bytesToHex(keyData);
      
      // 创建API Key（格式：ling_开头 + 32位随机字符）
      const apiKey = `ling_${keyString}`;
      
      // 计算密钥哈希
      const keyHash = await this.hashApiKey(apiKey);
      
      // 生成密钥ID
      const keyId = this.generateKeyId();
      
      // 创建密钥信息
      const keyInfo: ApiKeyInfo = {
        keyId: keyId,
        appId: appId,
        keyHash: keyHash,
        keyPrefix: apiKey.substring(0, 12) + '...',
        permissions: permissions,
        isActive: true,
        createdAt: Date.now(),
        rateLimit: {
          requestsPerMinute: app.quota.requestsPerMinute,
          requestsPerHour: app.quota.requestsPerHour,
          requestsPerDay: app.quota.requestsPerDay
        }
      };

      // 保存到数据库 - 通过辅助方法构造符合 DatabaseManager.SaveApiKeyParams 的对象
      await this.saveApiKeyToDatabase(
        keyInfo.keyId,
        keyInfo.appId,
        keyInfo.keyHash,
        keyInfo.keyPrefix,
        keyInfo.permissions,
        keyInfo.isActive,
        keyInfo.createdAt,
        keyInfo.lastUsedAt,
        keyInfo.expiresAt,
        keyInfo.rateLimit.requestsPerMinute,
        keyInfo.rateLimit.requestsPerHour,
        keyInfo.rateLimit.requestsPerDay
      );
      
      // 更新缓存
      const normalizedKey = this.normalizeApiKey(keyInfo);
      this.apiKeyCache.set(apiKey, normalizedKey);

      console.log(`[AppAuthManager] API Key生成成功: ${keyId}`);
      return apiKey;

    } catch (error) {
      console.error('[AppAuthManager] 生成API Key失败:', error);
      throw new LingAIError(
        LingAIErrorCode.API_KEY_GENERATION_FAILED,
        '生成API Key失败',
        this.toErrorDetails(error, '生成API Key失败')
      );
    }
  }

  /**
   * 验证API Key
   */
  async validateApiKey(apiKey: string): Promise<ExtendedApiKeyInfo> {
    try {
      // 检查缓存
      if (this.apiKeyCache.has(apiKey)) {
        const keyInfo = this.apiKeyCache.get(apiKey)!;
        
        // 检查密钥是否有效
        if (!keyInfo.isActive) {
          throw new LingAIError(
            LingAIErrorCode.API_KEY_INACTIVE,
            'API Key已禁用'
          );
        }

        // 检查是否过期
        if (keyInfo.expiresAt && Date.now() > keyInfo.expiresAt) {
          throw new LingAIError(
            LingAIErrorCode.API_KEY_EXPIRED,
            'API Key已过期'
          );
        }

        // 规范化返回对象中的可选与数组类型
        return this.normalizeApiKey(keyInfo);
      }

      // 从数据库查询
      const keyHash = await this.hashApiKey(apiKey);
      const keyInfo = await this.databaseManager.getApiKeyByHash(keyHash);
      
      if (!keyInfo) {
        throw new LingAIError(
          LingAIErrorCode.INVALID_API_KEY,
          '无效的API Key'
        );
      }

      // 检查密钥状态
      if (!keyInfo.isActive) {
        throw new LingAIError(
          LingAIErrorCode.API_KEY_INACTIVE,
          'API Key已禁用'
        );
      }

      if (keyInfo.expiresAt && Date.now() > keyInfo.expiresAt) {
        throw new LingAIError(
          LingAIErrorCode.API_KEY_EXPIRED,
          'API Key已过期'
        );
      }

      // 更新缓存 - 将 DatabaseManager.ExtendedApiKeyInfo 转换为 AppAuthManager.ApiKeyInfo
      const appKeyInfo: ApiKeyInfo = {
        keyId: keyInfo.keyId,
        appId: keyInfo.appId,
        keyHash: keyInfo.keyHash,
        keyPrefix: keyInfo.keyPrefix,
        permissions: Array.isArray(keyInfo.permissions) ? keyInfo.permissions : [],
        isActive: keyInfo.isActive,
        createdAt: keyInfo.createdAt,
        lastUsedAt: keyInfo.lastUsedAt,
        expiresAt: keyInfo.expiresAt,
        rateLimit: {
          requestsPerMinute: keyInfo.rateLimit.requestsPerMinute,
          requestsPerHour: keyInfo.rateLimit.requestsPerHour,
          requestsPerDay: keyInfo.rateLimit.requestsPerDay
        }
      };
      const normalized: ExtendedApiKeyInfo = this.normalizeApiKey(appKeyInfo);
      this.apiKeyCache.set(apiKey, normalized);
      return normalized;

    } catch (error) {
      if (error instanceof LingAIError) {
        throw error;
      }
      
      console.error('[AppAuthManager] 验证API Key失败:', error);
      throw new LingAIError(
        LingAIErrorCode.API_KEY_VALIDATION_FAILED,
        '验证API Key失败',
        this.toErrorDetails(error, '验证API Key失败')
      );
    }
  }

  /**
   * 检查权限
   */
  async checkPermission(apiKey: string, permission: string | Permission): Promise<boolean> {
    try {
      const keyInfo = await this.validateApiKey(apiKey);
      const permStr = String(permission);
      return Array.isArray(keyInfo.permissions) && keyInfo.permissions.includes(permStr);
    } catch (error) {
      console.error('[AppAuthManager] 检查权限失败:', error);
      return false;
    }
  }

  /**
   * 检查速率限制
   */
  async checkRateLimit(apiKey: string): Promise<boolean> {
    try {
      const keyInfo = await this.validateApiKey(apiKey);
      const now = Date.now();
      const cacheKey = `${keyInfo.appId}_${Math.floor(now / 60000)}`; // 按分钟分组

      // 检查缓存中的速率限制
      const rateLimitInfo: RateLimitInfo | undefined = this.rateLimitCache.get(cacheKey);
      const perMinute: number = Number(keyInfo.rateLimit.requestsPerMinute);
      
      if (rateLimitInfo) {
        if (rateLimitInfo.count >= perMinute) {
          return false; // 超出速率限制
        }
        
        // 增加计数
        rateLimitInfo.count++;
      } else {
        // 创建新的速率限制记录
        const newRateLimit: RateLimitInfo = {
          count: 1,
          resetTime: Math.floor(now / 60000) * 60000 + 60000 // 下一分钟的开始时间
        };
        this.rateLimitCache.set(cacheKey, newRateLimit);
      }

      return true;

    } catch (error) {
      console.error('[AppAuthManager] 检查速率限制失败:', error);
      return false;
    }
  }

  /**
   * 记录API使用情况
   */
  async recordUsage(
    apiKey: string,
    endpoint: string,
    tokens: number,
    success: boolean
  ): Promise<void> {
    try {
      const keyInfo = await this.validateApiKey(apiKey);
      const today = new Date().toISOString().split('T')[0]; // YYYY-MM-DD
      const cacheKey = `${keyInfo.appId}_${today}`;

      // 更新使用统计
      let stats = this.usageCache.get(cacheKey);
      if (!stats) {
        const newStats: UsageStats = {
          appId: keyInfo.appId,
          date: today,
          requests: 0,
          tokens: 0,
          errors: 0,
          lastUpdated: Date.now()
        };
        stats = newStats;
        this.usageCache.set(cacheKey, stats);
      }

      stats.requests++;
      stats.tokens += tokens;
      if (!success) {
        stats.errors++;
      }
      stats.lastUpdated = Date.now();

      // 更新API Key最后使用时间
      keyInfo.lastUsedAt = Date.now();
      await this.databaseManager.updateApiKeyLastUsed(keyInfo.keyId, Date.now());

      // 定期保存到数据库
      if (stats.requests % 10 === 0) { // 每10次请求保存一次
        const extendedStats: ExtendedUsageStats = {
          appId: stats.appId,
          date: stats.date,
          requests: stats.requests,
          tokens: stats.tokens,
          errors: stats.errors,
          requestCount: stats.requests,
          tokenCount: stats.tokens,
          errorCount: stats.errors,
          lastUpdated: stats.lastUpdated
        };
        await this.databaseManager.saveUsageStats(extendedStats);
      }

    } catch (error) {
      console.error('[AppAuthManager] 记录使用情况失败:', error);
    }
  }

  /**
   * 获取应用信息
   */
  async getAppInfo(appId: string): Promise<AppRegistration | null> {
    try {
      return await this.databaseManager.getApp(appId);
    } catch (error) {
      console.error('[AppAuthManager] 获取应用信息失败:', error);
      return null;
    }
  }

  /**
   * 获取应用使用统计
   */
  async getAppUsageStats(appId: string, days: number = 30): Promise<ExtendedUsageStats[]> {
    try {
      return await this.databaseManager.getUsageStats(appId, days);
    } catch (error) {
      console.error('[AppAuthManager] 获取使用统计失败:', error);
      return [];
    }
  }

  /**
   * 更新应用配额
   */
  async updateAppQuota(appId: string, quota: AppQuota): Promise<void> {
    try {
      await this.databaseManager.updateAppQuota(appId, quota);
      
      // 清除相关缓存
      this.clearAppCache(appId);
      
      console.log(`[AppAuthManager] 应用配额更新成功: ${appId}`);
    } catch (error) {
      console.error('[AppAuthManager] 更新应用配额失败:', error);
      throw new LingAIError(
        LingAIErrorCode.QUOTA_UPDATE_FAILED,
        '更新应用配额失败',
        this.toErrorDetails(error, '更新应用配额失败')
      );
    }
  }

  /**
   * 禁用API Key
   */
  async revokeApiKey(keyId: string): Promise<void> {
    try {
      await this.databaseManager.updateApiKeyStatus(keyId, false);
      
      // 从缓存中移除
      const cacheEntries: Array<[string, ExtendedApiKeyInfo]> = Array.from(this.apiKeyCache.entries());
      for (let i = 0; i < cacheEntries.length; i++) {
        const entry = cacheEntries[i];
        const apiKey = entry[0];
        const keyInfo = entry[1];
        if (keyInfo.keyId === keyId) {
          this.apiKeyCache.delete(apiKey);
          break;
        }
      }
      
      console.log(`[AppAuthManager] API Key已禁用: ${keyId}`);
    } catch (error) {
      console.error('[AppAuthManager] 禁用API Key失败:', error);
      throw new LingAIError(
        LingAIErrorCode.API_KEY_REVOCATION_FAILED,
        '禁用API Key失败',
        this.toErrorDetails(error, '禁用API Key失败')
      );
    }
  }

  /**
   * 生成应用ID
   */
  private generateAppId(): string {
    const timestamp = Date.now().toString(36);
    const random = Math.random().toString(36).substr(2, 8);
    return `app_${timestamp}_${random}`;
  }

  /**
   * 生成密钥ID
   */
  private generateKeyId(): string {
    const timestamp = Date.now().toString(36);
    const random = Math.random().toString(36).substr(2, 8);
    return `key_${timestamp}_${random}`;
  }

  /**
   * 生成随机字节
   */
  private generateRandomBytes(length: number): Uint8Array {
    const bytes = new Uint8Array(length);
    for (let i = 0; i < length; i++) {
      bytes[i] = Math.floor(Math.random() * 256);
    }
    return bytes;
  }

  /**
   * 字节转十六进制
   */
  private bytesToHex(bytes: Uint8Array): string {
    const byteArray = Array.from(bytes);
    const hexArray: string[] = [];
    for (let i = 0; i < byteArray.length; i++) {
      const hex = byteArray[i].toString(16).padStart(2, '0');
      hexArray.push(hex);
    }
    return hexArray.join('');
  }

  /**
   * 计算API Key哈希
   */
  private async hashApiKey(apiKey: string): Promise<string> {
    try {
      // 使用简单的哈希算法（生产环境应使用更安全的方法）
      let hash = 0;
      for (let i = 0; i < apiKey.length; i++) {
        const char = apiKey.charCodeAt(i);
        hash = ((hash << 5) - hash) + char;
        hash = hash & hash; // 转换为32位整数
      }
      return Math.abs(hash).toString(16);
    } catch (error) {
      console.error('[AppAuthManager] 计算API Key哈希失败:', error);
      throw new Error('计算API Key哈希失败');
    }
  }

  /**
   * 清除应用缓存
   */
  private clearAppCache(appId: string): void {
    // 清除API Key缓存
    const cacheEntries: Array<[string, ExtendedApiKeyInfo]> = Array.from(this.apiKeyCache.entries());
    for (let i = 0; i < cacheEntries.length; i++) {
      const entry = cacheEntries[i];
      const apiKey = entry[0];
      const keyInfo = entry[1];
      if (keyInfo.appId === appId) {
        this.apiKeyCache.delete(apiKey);
      }
    }

    // 清除使用统计缓存
    const usageEntries: Array<[string, UsageStats]> = Array.from(this.usageCache.entries());
    for (let i = 0; i < usageEntries.length; i++) {
      const usageEntry = usageEntries[i];
      const cacheKey = usageEntry[0];
      const stats = usageEntry[1];
      if (stats.appId === appId) {
        this.usageCache.delete(cacheKey);
      }
    }
  }

  /**
   * 启动清理定时器
   */
  private startCleanupTimer(): void {
    // 每5分钟清理一次过期的缓存
    setInterval(() => {
      this.cleanupExpiredCache();
    }, 5 * 60 * 1000);

    // 每小时保存一次使用统计
    setInterval(() => {
      this.saveUsageStats();
    }, 60 * 60 * 1000);
  }

  /**
   * 清理过期缓存
   */
  private cleanupExpiredCache(): void {
    const now = Date.now();

    // 清理速率限制缓存
    const rateLimitEntries: Array<[string, RateLimitInfo]> = Array.from(this.rateLimitCache.entries());
    for (let i = 0; i < rateLimitEntries.length; i++) {
      const rateLimitEntry: [string, RateLimitInfo] = rateLimitEntries[i];
      const cacheKey: string = rateLimitEntry[0];
      const rateLimitInfo: RateLimitInfo = rateLimitEntry[1];
      if (now > rateLimitInfo.resetTime) {
        this.rateLimitCache.delete(cacheKey);
      }
    }

    console.log(`[AppAuthManager] 缓存清理完成，剩余速率限制记录: ${this.rateLimitCache.size}`);
  }

  /**
   * 保存使用统计
   */
  private async saveUsageStats(): Promise<void> {
    try {
      const promises: Promise<void>[] = [];
      
      for (const stats of this.usageCache.values()) {
        const extendedStats: ExtendedUsageStats = {
          appId: stats.appId,
          date: stats.date,
          requests: stats.requests,
          tokens: stats.tokens,
          errors: stats.errors,
          requestCount: stats.requests,
          tokenCount: stats.tokens,
          errorCount: stats.errors,
          lastUpdated: stats.lastUpdated
        };
        promises.push(this.databaseManager.saveUsageStats(extendedStats));
      }
      
      await Promise.all(promises);
      console.log(`[AppAuthManager] 使用统计保存完成: ${promises.length}条记录`);
    } catch (error) {
      console.error('[AppAuthManager] 保存使用统计失败:', error);
    }
  }

  /**
   * 获取权限列表
   */
  static getAvailablePermissions(): string[] {
    return Object.values(Permission);
  }

  /**
   * 清理资源
   */
  async cleanup(): Promise<void> {
    try {
      // 保存所有缓存的使用统计
      await this.saveUsageStats();
      
      // 清空缓存
      this.apiKeyCache.clear();
      this.usageCache.clear();
      this.rateLimitCache.clear();
      
      console.log('[AppAuthManager] 资源清理完成');
    } catch (error) {
      console.error('[AppAuthManager] 资源清理失败:', error);
    }
  }

  private normalizeApiKey(info: ApiKeyInfo | ExtendedApiKeyInfo): ExtendedApiKeyInfo {
    const permissions = Array.isArray(info.permissions) ? info.permissions : [];
    const limit = info.rateLimit;
    return {
      keyId: info.keyId,
      appId: info.appId,
      keyHash: info.keyHash,
      keyPrefix: info.keyPrefix,
      permissions: permissions,
      isActive: info.isActive,
      createdAt: info.createdAt,
      lastUsedAt: info.lastUsedAt,
      expiresAt: info.expiresAt,
      rateLimit: {
        requestsPerMinute: limit.requestsPerMinute,
        requestsPerHour: limit.requestsPerHour,
        requestsPerDay: limit.requestsPerDay
      }
    };
  }

  /**
   * 将未知错误安全转换为 Error
   */
  private toError(details: Error | string | object): Error {
    return details instanceof Error ? details : new Error(typeof details === 'string' ? details : JSON.stringify(details));
  }

  /**
   * 将未知错误安全转换为 ErrorDetails
   */
  private toErrorDetails(error: Error | string | object, fallback?: string): ErrorDetails {
    const message = fallback || '发生未知错误';
    if (error instanceof LingAIError) {
      return error.details || { originalError: error.message, timestamp: Date.now() };
    }
    if (error instanceof Error) {
      return { originalError: error.message, timestamp: Date.now() };
    }
    return { originalError: typeof error === 'string' ? error : JSON.stringify(error ?? message), timestamp: Date.now() };
  }

  /**
   * 辅助方法：保存API Key到数据库
   * 避免结构类型问题，通过参数传递构造符合 DatabaseManager.SaveApiKeyParams 的对象
   */
  private async saveApiKeyToDatabase(
    keyId: string,
    appId: string,
    keyHash: string,
    keyPrefix: string,
    permissions: string[],
    isActive: boolean,
    createdAt: number,
    lastUsedAt: number | undefined,
    expiresAt: number | undefined,
    requestsPerMinute: number,
    requestsPerHour: number,
    requestsPerDay: number
  ): Promise<void> {
    // 构造符合 SaveApiKeyParams 接口的对象
    const dbKeyInfo: SaveApiKeyParams = {
      keyId: keyId,
      appId: appId,
      keyHash: keyHash,
      keyPrefix: keyPrefix,
      permissions: permissions,
      isActive: isActive,
      createdAt: createdAt,
      lastUsedAt: lastUsedAt,
      expiresAt: expiresAt,
      rateLimit: {
        requestsPerMinute: requestsPerMinute,
        requestsPerHour: requestsPerHour,
        requestsPerDay: requestsPerDay
      }
    };
    await this.databaseManager.saveApiKey(dbKeyInfo);
  }
}
