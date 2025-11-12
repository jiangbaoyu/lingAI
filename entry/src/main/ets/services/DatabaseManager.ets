/**
 * 数据库管理器
 * 负责数据库的创建、连接和数据操作
 */

import relationalStore from '@ohos.data.relationalStore';
import common from '@ohos.app.ability.common';
import {
  ModelInfo,
  ModelStatus,
  ModelType,
  ModelConfig,
  AppRegistration,
  AppQuota,
  LingAIError,
  LingAIErrorCode
} from '../sdk/types/LingAITypes';

/**
 * 数据库配置接口
 */
interface DatabaseConfig {
  name: string;
  version: number;
  encrypt: boolean;
}

/**
 * 系统配置接口
 */
interface SystemConfig {
  key: string;
  value: string;
  updated_at?: number;
}
/**
 * 数据库配置
 */
const DATABASE_CONFIG: DatabaseConfig = {
  name: 'LingAI.db',
  version: 1,
  encrypt: false
};

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
  rateLimit: RateLimit;
}

/**
 * 速率限制接口
 */
export interface RateLimit {
  requestsPerMinute: number;
  requestsPerHour: number;
  requestsPerDay: number;
}

/**
 * 数据库应用配额接口
 */
interface DatabaseAppQuota {
  requestsPerMinute: number;
  requestsPerHour: number;
  requestsPerDay: number;
  tokensPerDay: number;
  maxConcurrentRequests: number;
}

class LegacyAppQuota {
  dailyRequests: number = 0;
  requestsPerMinute: number = 0;
  maxConcurrentRequests: number = 0;
  maxTokens: number = 0;
}

/**
 * 扩展的 API Key 信息接口
 */
interface ExtendedApiKeyInfo extends ApiKeyInfo {
  expiresAt?: number;
  rateLimit: RateLimit;
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
}

/**
 * 扩展的使用统计接口
 */
export interface ExtendedUsageStats extends UsageStats {
  requestCount: number;
  tokenCount: number;
  errorCount: number;
  lastUpdated: number;
}

/**
 * 使用统计存储值接口
 */
interface UsageStatsValues {
  app_id: string;
  date: string;
  requests: number;
  tokens: number;
  errors: number;
  last_updated: number;
}

/**
 * 模型更新值接口
 */
interface ModelUpdateValues {
  status: ModelStatus;
  updated_at?: number;
  download_progress?: number;
}

/**
 * 应用注册值接口
 */
interface AppRegistrationValues {
  app_id: string;
  app_name: string;
  api_key: string;
  bundle_name: string;
  permissions: string;
  quota_daily_requests: number;
  quota_requests_per_minute: number;
  quota_requests_per_hour: number;
  quota_requests_per_day: number;
  quota_tokens_per_day: number;
  quota_max_concurrent: number;
  quota_max_tokens: number;
  registered_at: number;
  last_active_at: number;
  status: string;
}

/**
 * 应用存储值接口
 */
interface AppSaveValues {
  app_id: string;
  app_name: string;
  package_name: string;
  description: string;
  permissions: string;
  quota_requests_per_minute: number;
  quota_requests_per_hour: number;
  quota_requests_per_day: number;
  quota_tokens_per_day: number;
  quota_max_concurrent: number;
  is_active: number;
  created_at: number;
  last_used_at?: number;
}

/**
 * 数据库应用配额更新值接口
 */
interface DatabaseAppQuotaUpdateValues {
  quota_daily_requests: number;
  quota_requests_per_minute: number;
  quota_requests_per_hour: number;
  quota_requests_per_day: number;
  quota_tokens_per_day: number;
  quota_max_concurrent: number;
  quota_max_tokens: number;
}

/**
 * 模型数据库插入值接口
 */
interface ModelInsertValues {
  id: string;
  name: string;
  description: string;
  size: number;
  type: string;
  status: string;
  download_progress: number;
  file_path: string;
  created_at: number;
  updated_at: number;
  hugging_face_id: string;
  config: string;
}

/**
 * API Key 插入值接口
 */
interface ApiKeyInsertValues {
  key_id: string;
  app_id: string;
  key_hash: string;
  key_prefix: string;
  permissions: string;
  is_active: number;
  created_at: number;
  last_used_at: number | null;
  expires_at: number | null;
  rate_limit_per_minute: number;
  rate_limit_per_hour: number;
  rate_limit_per_day: number;
}

interface LastActiveUpdateValues {
  last_active_at: number;
}

interface ApiKeyLastUsedUpdateValues {
  last_used_at: number;
}

interface ApiKeyStatusUpdateValues {
  is_active: number;
}

/**
 * 保存API Key信息的参数接口
 */
export interface SaveApiKeyParams {
  keyId: string;
  appId: string;
  keyHash: string;
  keyPrefix: string;
  permissions: string[];
  isActive: boolean;
  createdAt: number;
  lastUsedAt?: number;
  expiresAt?: number;
  rateLimit: RateLimit;
}

/**
 * 聊天会话接口
 */
interface ChatSession {
  id: string;
  appId: string;
  modelId: string;
  title: string;
  createdAt: number;
  updatedAt: number;
  messageCount: number;
}

/**
 * 聊天消息接口
 */
interface ChatMessage {
  id: string;
  sessionId: string;
  role: string;
  content: string;
  timestamp: number;
  tokenCount?: number;
}

/**
 * 推理任务接口
 */
interface InferenceTask {
  id: string;
  appId: string;
  modelId: string;
  type: string;
  status: string;
  createdAt: number;
  completedAt?: number;
  inputTokens?: number;
  outputTokens?: number;
}

/**
 * 数据库管理器类
 */
export class DatabaseManager {
  private context: common.Context;
  private store: relationalStore.RdbStore | null = null;
  private connected: boolean = false;

  constructor(context: common.Context) {
    this.context = context;
    this.initialize();
  }

  /**
   * 初始化数据库
   */
  private async initialize(): Promise<void> {
    try {
      const config: relationalStore.StoreConfig = {
        name: DATABASE_CONFIG.name,
        securityLevel: relationalStore.SecurityLevel.S1,
        encrypt: DATABASE_CONFIG.encrypt
      };

      this.store = await relationalStore.getRdbStore(this.context, config);

      // 创建表
      await this.createTables();

      // 初始化系统配置
      await this.initializeSystemConfig();
      
      this.connected = true;
      console.log('[DatabaseManager] 数据库初始化成功');
      
    } catch (error) {
      console.error('[DatabaseManager] 数据库初始化失败:', error);
      throw new LingAIError(
        LingAIErrorCode.SERVICE_UNAVAILABLE,
        '数据库初始化失败',
        error
      );
    }
  }

  /**
   * 创建数据库表
   */
  private async createTables(): Promise<void> {
    if (!this.store) {
      throw new Error('数据库连接未建立');
    }

    const tables: string[] = [
      `CREATE TABLE IF NOT EXISTS models (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT,
        size INTEGER NOT NULL,
        type TEXT NOT NULL,
        status TEXT NOT NULL,
        download_progress INTEGER DEFAULT 0,
        file_path TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        hugging_face_id TEXT,
        config TEXT
      )`,
      `CREATE TABLE IF NOT EXISTS registered_apps (
        app_id TEXT PRIMARY KEY,
        app_name TEXT NOT NULL,
        package_name TEXT NOT NULL UNIQUE,
        description TEXT,
        permissions TEXT NOT NULL,
        quota_requests_per_minute INTEGER DEFAULT 60,
        quota_requests_per_hour INTEGER DEFAULT 1000,
        quota_requests_per_day INTEGER DEFAULT 10000,
        quota_tokens_per_day INTEGER DEFAULT 100000,
        quota_max_concurrent INTEGER DEFAULT 5,
        is_active INTEGER DEFAULT 1,
        created_at INTEGER NOT NULL,
        last_used_at INTEGER NOT NULL
      )`,
      `CREATE TABLE IF NOT EXISTS api_keys (
        key_id TEXT PRIMARY KEY,
        app_id TEXT NOT NULL,
        key_hash TEXT NOT NULL UNIQUE,
        key_prefix TEXT NOT NULL,
        permissions TEXT NOT NULL,
        is_active INTEGER DEFAULT 1,
        created_at INTEGER NOT NULL,
        last_used_at INTEGER,
        expires_at INTEGER,
        rate_limit_per_minute INTEGER DEFAULT 60,
        rate_limit_per_hour INTEGER DEFAULT 1000,
        rate_limit_per_day INTEGER DEFAULT 10000,
        FOREIGN KEY (app_id) REFERENCES registered_apps (app_id)
      )`,
      `CREATE TABLE IF NOT EXISTS usage_stats (
        app_id TEXT NOT NULL,
        date TEXT NOT NULL,
        requests INTEGER DEFAULT 0,
        tokens INTEGER DEFAULT 0,
        errors INTEGER DEFAULT 0,
        last_updated INTEGER NOT NULL,
        PRIMARY KEY (app_id, date),
        FOREIGN KEY (app_id) REFERENCES registered_apps (app_id)
      )`,
      `CREATE TABLE IF NOT EXISTS inference_tasks (
        id TEXT PRIMARY KEY,
        app_id TEXT NOT NULL,
        model_id TEXT NOT NULL,
        type TEXT NOT NULL,
        status TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        completed_at INTEGER,
        input_tokens INTEGER,
        output_tokens INTEGER,
        FOREIGN KEY (app_id) REFERENCES registered_apps (app_id),
        FOREIGN KEY (model_id) REFERENCES models (id)
      )`,
      `CREATE TABLE IF NOT EXISTS chat_sessions (
        id TEXT PRIMARY KEY,
        app_id TEXT NOT NULL,
        model_id TEXT NOT NULL,
        title TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        message_count INTEGER DEFAULT 0,
        FOREIGN KEY (app_id) REFERENCES registered_apps (app_id),
        FOREIGN KEY (model_id) REFERENCES models (id)
      )`,
      `CREATE TABLE IF NOT EXISTS chat_messages (
        id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL,
        role TEXT NOT NULL,
        content TEXT NOT NULL,
        timestamp INTEGER NOT NULL,
        token_count INTEGER,
        FOREIGN KEY (session_id) REFERENCES chat_sessions (id)
      )`,
      `CREATE TABLE IF NOT EXISTS system_config (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL,
        updated_at INTEGER NOT NULL
      )`
    ];

    for (const sql of tables) {
      await this.store.executeSql(sql);
    }

    // 创建索引
    const indexes = [
      'CREATE INDEX IF NOT EXISTS idx_models_status ON models (status)',
      'CREATE INDEX IF NOT EXISTS idx_models_type ON models (type)',
      'CREATE INDEX IF NOT EXISTS idx_apps_package_name ON registered_apps (package_name)',
      'CREATE INDEX IF NOT EXISTS idx_apps_is_active ON registered_apps (is_active)',
      'CREATE INDEX IF NOT EXISTS idx_api_keys_app_id ON api_keys (app_id)',
      'CREATE INDEX IF NOT EXISTS idx_api_keys_hash ON api_keys (key_hash)',
      'CREATE INDEX IF NOT EXISTS idx_api_keys_active ON api_keys (is_active)',
      'CREATE INDEX IF NOT EXISTS idx_usage_stats_date ON usage_stats (date)',
      'CREATE INDEX IF NOT EXISTS idx_tasks_app_id ON inference_tasks (app_id)',
      'CREATE INDEX IF NOT EXISTS idx_tasks_model_id ON inference_tasks (model_id)',
      'CREATE INDEX IF NOT EXISTS idx_sessions_app_id ON chat_sessions (app_id)',
      'CREATE INDEX IF NOT EXISTS idx_messages_session_id ON chat_messages (session_id)'
    ];

    for (const sql of indexes) {
      await this.store.executeSql(sql);
    }
  }

  /**
   * 初始化系统配置
   */
  private async initializeSystemConfig(): Promise<void> {
    if (!this.store) {
      return;
    }

    const defaultConfigs: SystemConfig[] = [
      { key: 'max_concurrent_requests', value: '10' },
      { key: 'default_model_timeout', value: '300000' },
      { key: 'cleanup_interval', value: '3600000' },
      { key: 'max_session_age', value: '86400000' },
      { key: 'enable_debug_logging', value: 'false' }
    ];

    for (const config of defaultConfigs) {
      try {
        const now = Date.now();
        // 使用 INSERT OR IGNORE 防止重复插入导致异常
        await this.store.executeSql(
          'INSERT OR IGNORE INTO system_config (key, value, updated_at) VALUES (?, ?, ?)',
          [String(config.key), String(config.value), Number(now)]
        );
      } catch (error) {
        // 配置可能已存在，忽略错误
      }
    }
  }

  /**
   * 保存模型信息
   */
  async saveModel(model: ModelInfo): Promise<void> {
    if (!this.store) {
      throw new Error('数据库连接未建立');
    }

    try {
      const configValue: ModelConfig = model.config ? model.config : {} as ModelConfig;
      const values: ModelInsertValues = {
        id: model.id,
        name: model.name,
        description: model.description || '',
        size: model.size,
        type: model.type,
        status: model.status,
        download_progress: model.downloadProgress || 0,
        file_path: model.filePath || '',
        created_at: model.createdAt,
        updated_at: model.updatedAt,
        hugging_face_id: model.huggingFaceId || '',
        config: JSON.stringify(configValue)
      };
      await this.store.executeSql(
        'INSERT INTO models (id, name, description, size, type, status, download_progress, file_path, created_at, updated_at, hugging_face_id, config) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          String(values.id),
          String(values.name),
          String(values.description),
          Number(values.size),
          String(values.type),
          String(values.status),
          Number(values.download_progress),
          String(values.file_path),
          Number(values.created_at),
          Number(values.updated_at),
          String(values.hugging_face_id),
          String(values.config)
        ]
      );
      console.log('[DatabaseManager] 模型信息保存成功:', model.id);
      
    } catch (error) {
      console.error('[DatabaseManager] 保存模型信息失败:', error);
      const errorDetails = error instanceof Error ? error : new Error(String(error));
      throw new LingAIError(
        LingAIErrorCode.UNKNOWN_ERROR,
        '保存模型信息失败',
        errorDetails
      );
    }
  }

  /**
   * 获取模型信息
   */
  async getModel(modelId: string): Promise<ModelInfo | null> {
    if (!this.store) {
      throw new Error('数据库连接未建立');
    }

    try {
      const predicates = new relationalStore.RdbPredicates('models');
      predicates.equalTo('id', modelId);
      
      const resultSet = await this.store.query(predicates);
      
      if (resultSet.rowCount === 0) {
        resultSet.close();
        return null;
      }
      
      resultSet.goToFirstRow();
      const model = this.parseModelFromResultSet(resultSet);
      resultSet.close();
      
      return model;
      
    } catch (error) {
      console.error('[DatabaseManager] 获取模型信息失败:', error);
      const errorDetails = error instanceof Error ? error : new Error(String(error));
      throw new LingAIError(
        LingAIErrorCode.UNKNOWN_ERROR,
        '获取模型信息失败',
        errorDetails
      );
    }
  }

  /**
   * 根据 HuggingFace ID 获取模型
   */
  async getModelByHuggingFaceId(huggingFaceId: string): Promise<ModelInfo | null> {
    if (!this.store) {
      throw new Error('数据库连接未建立');
    }

    try {
      const predicates = new relationalStore.RdbPredicates('models');
      predicates.equalTo('hugging_face_id', huggingFaceId);
      
      const resultSet = await this.store.query(predicates);
      
      if (resultSet.rowCount === 0) {
        resultSet.close();
        return null;
      }
      
      resultSet.goToFirstRow();
      const model = this.parseModelFromResultSet(resultSet);
      resultSet.close();
      
      return model;
      
    } catch (error) {
      console.error('[DatabaseManager] 根据 HuggingFace ID 获取模型失败:', error);
      return null;
    }
  }

  /**
   * 获取所有模型
   */
  async getModels(): Promise<ModelInfo[]> {
    if (!this.store) {
      throw new Error('数据库连接未建立');
    }

    try {
      const predicates = new relationalStore.RdbPredicates('models');
      predicates.orderByDesc('updated_at');
      
      const resultSet = await this.store.query(predicates);
      const models: ModelInfo[] = [];
      
      if (resultSet.rowCount > 0) {
        resultSet.goToFirstRow();
        do {
          models.push(this.parseModelFromResultSet(resultSet));
        } while (resultSet.goToNextRow());
      }
      
      resultSet.close();
      return models;
      
    } catch (error) {
      console.error('[DatabaseManager] 获取模型列表失败:', error);
      const errorDetails = error instanceof Error ? error : new Error(String(error));
      throw new LingAIError(
        LingAIErrorCode.UNKNOWN_ERROR,
        '获取模型列表失败',
        errorDetails
      );
    }
  }

  /**
   * 更新模型状态
   */
  async updateModelStatus(modelId: string, status: ModelStatus, progress?: number): Promise<void> {
    if (!this.store) {
      throw new Error('数据库连接未建立');
    }

    try {
      const values: ModelUpdateValues = {
        status: status,
        updated_at: Date.now()
      };
      
      if (progress !== undefined) {
        values.download_progress = progress;
      }
      
      if (values.download_progress !== undefined) {
        await this.store.executeSql(
          'UPDATE models SET status = ?, updated_at = ?, download_progress = ? WHERE id = ?',
          [String(values.status), Number(values.updated_at!), Number(values.download_progress), String(modelId)]
        );
      } else {
        await this.store.executeSql(
          'UPDATE models SET status = ?, updated_at = ? WHERE id = ?',
          [String(values.status), Number(values.updated_at!), String(modelId)]
        );
      }
      
    } catch (error) {
      console.error('[DatabaseManager] 更新模型状态失败:', error);
      const errorDetails = error instanceof Error ? error : new Error(String(error));
      throw new LingAIError(
        LingAIErrorCode.UNKNOWN_ERROR,
        '更新模型状态失败',
        errorDetails
      );
    }
  }

  /**
   * 更新模型进度
   */
  async updateModelProgress(modelId: string, progress: number): Promise<void> {
    await this.updateModelStatus(modelId, ModelStatus.DOWNLOADING, progress);
  }

  /**
   * 删除模型
   */
  async deleteModel(modelId: string): Promise<void> {
    if (!this.store) {
      throw new Error('数据库连接未建立');
    }

    try {
      const predicates = new relationalStore.RdbPredicates('models');
      predicates.equalTo('id', modelId);
      
      await this.store.delete(predicates);
      
    } catch (error) {
      console.error('[DatabaseManager] 删除模型失败:', error);
      const errorDetails = error instanceof Error ? error : new Error(String(error));
      throw new LingAIError(
        LingAIErrorCode.UNKNOWN_ERROR,
        '删除模型失败',
        errorDetails
      );
    }
  }

  /**
   * 娉ㄥ唽搴旂敤
   */
  async registerApp(
    appName: string,
    bundleName: string,
    permissions: string[],
    quota?: Partial<AppQuota>
  ): Promise<AppRegistration> {
    if (!this.store) {
      throw new Error('数据库连接未建立');
    }

    try {
      const appId = this.generateAppId();
      const apiKey = this.generateApiKey();
      const now = Date.now();
      
      const defaultQuota: AppQuota = {
        dailyRequests: quota?.dailyRequests ?? 1000,
        requestsPerMinute: quota?.requestsPerMinute ?? 60,
        requestsPerHour: quota?.requestsPerHour ?? 3600,
        requestsPerDay: quota?.requestsPerDay ?? 1000,
        tokensPerDay: quota?.tokensPerDay ?? 100000,
        maxConcurrentRequests: quota?.maxConcurrentRequests ?? 5,
        maxTokens: quota?.maxTokens ?? 100000
      };

      const values: AppRegistrationValues = {
        app_id: appId,
        app_name: appName,
        api_key: apiKey,
        bundle_name: bundleName,
        permissions: JSON.stringify(permissions),
        quota_daily_requests: defaultQuota.dailyRequests,
        quota_requests_per_minute: defaultQuota.requestsPerMinute,
        quota_requests_per_hour: defaultQuota.requestsPerHour,
        quota_requests_per_day: defaultQuota.requestsPerDay,
        quota_tokens_per_day: defaultQuota.tokensPerDay,
        quota_max_concurrent: defaultQuota.maxConcurrentRequests,
        quota_max_tokens: defaultQuota.maxTokens,
        registered_at: now,
        last_active_at: now,
        status: 'active'
      };
      await this.store.executeSql(
        'INSERT INTO registered_apps (app_id, app_name, api_key, bundle_name, permissions, quota_daily_requests, quota_requests_per_minute, quota_requests_per_hour, quota_requests_per_day, quota_tokens_per_day, quota_max_concurrent, quota_max_tokens, registered_at, last_active_at, status) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          String(values.app_id),
          String(values.app_name),
          String(values.api_key),
          String(values.bundle_name),
          String(values.permissions),
          Number(values.quota_daily_requests),
          Number(values.quota_requests_per_minute),
          Number(values.quota_requests_per_hour),
          Number(values.quota_requests_per_day),
          Number(values.quota_tokens_per_day),
          Number(values.quota_max_concurrent),
          Number(values.quota_max_tokens),
          Number(values.registered_at),
          Number(values.last_active_at),
          String(values.status)
        ]
      );

      const registration: AppRegistration = {
        appId: appId,
        appName: appName,
        apiKey: apiKey,
        bundleName: bundleName,
        permissions: permissions,
        quota: defaultQuota,
        registeredAt: now,
        lastActiveAt: now,
        status: 'active'
      };

      console.log('[DatabaseManager] 应用注册成功:', appId);
      return registration;
      
    } catch (error) {
      console.error('[DatabaseManager] 应用注册失败:', error);
      const errorDetails = error instanceof Error ? error : new Error(String(error));
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
  async getAppInfo(bundleName: string): Promise<AppRegistration | null> {
    if (!this.store) {
      throw new Error('数据库连接未建立');
    }

    try {
      const predicates = new relationalStore.RdbPredicates('registered_apps');
      predicates.equalTo('bundle_name', bundleName);
      
      const resultSet = await this.store.query(predicates);
      
      if (resultSet.rowCount === 0) {
        resultSet.close();
        return null;
      }
      
      resultSet.goToFirstRow();
      const app = this.parseAppFromResultSet(resultSet);
      resultSet.close();
      
      return app;
      
    } catch (error) {
      console.error('[DatabaseManager] 获取应用信息失败:', error);
      return null;
    }
  }

  /**
   * 验证 API 密钥
   */
  async validateApiKey(bundleName: string, apiKey: string): Promise<boolean> {
    const app = await this.getAppInfo(bundleName);
    return app !== null && app.apiKey === apiKey && app.status === 'active';
  }

  /**
   * 更新应用最后活跃时间
   */
  async updateLastActiveTime(bundleName: string): Promise<void> {
    if (!this.store) {
      return;
    }

    try {
      const lastActiveAt = Date.now();
      await this.store.executeSql(
        'UPDATE registered_apps SET last_active_at = ? WHERE bundle_name = ?',
        [Number(lastActiveAt), String(bundleName)]
      );
      
    } catch (error) {
      console.error('[DatabaseManager] 更新应用活跃时间失败:', error);
    }
  }

  /**
   * 清理过期会话
   */
  async cleanupExpiredSessions(): Promise<void> {
    if (!this.store) {
      return;
    }

    try {
      const expireTime = Date.now() - 24 * 60 * 60 * 1000; // 24小时前      
      const predicates = new relationalStore.RdbPredicates('chat_sessions');
      predicates.lessThan('updated_at', expireTime);
      
      await this.store.delete(predicates);
      
      console.log('[DatabaseManager] 过期会话清理完成');
    } catch (error) {
      console.error('[DatabaseManager] 清理过期会话失败:', error);
    }
  }

  /**
   * 从结果集解析模型信息
   */
  private parseModelFromResultSet(resultSet: relationalStore.ResultSet): ModelInfo {
    const configStrIndex = resultSet.getColumnIndex('config');
    const configStr = resultSet.getString(configStrIndex);
    const defaultConfig: ModelConfig = {};
    const parsedConfig: ModelConfig = configStr && configStr.length > 0
      ? (JSON.parse(configStr) as ModelConfig)
      : defaultConfig;

    return {
      id: resultSet.getString(resultSet.getColumnIndex('id')),
      name: resultSet.getString(resultSet.getColumnIndex('name')),
      description: resultSet.getString(resultSet.getColumnIndex('description')),
      size: resultSet.getLong(resultSet.getColumnIndex('size')),
      type: resultSet.getString(resultSet.getColumnIndex('type')) as ModelType,
      status: resultSet.getString(resultSet.getColumnIndex('status')) as ModelStatus,
      downloadProgress: resultSet.getLong(resultSet.getColumnIndex('download_progress')),
      filePath: resultSet.getString(resultSet.getColumnIndex('file_path')),
      createdAt: resultSet.getLong(resultSet.getColumnIndex('created_at')),
      updatedAt: resultSet.getLong(resultSet.getColumnIndex('updated_at')),
      huggingFaceId: resultSet.getString(resultSet.getColumnIndex('hugging_face_id')),
      config: parsedConfig
    };
  }

  /**
   * 从结果集解析应用信息
   */
  private parseAppFromResultSet(resultSet: relationalStore.ResultSet): AppRegistration {
    const quota: AppQuota = {
      dailyRequests: resultSet.getLong(resultSet.getColumnIndex('quota_daily_requests')),
      requestsPerMinute: resultSet.getLong(resultSet.getColumnIndex('quota_requests_per_minute')),
      requestsPerHour: resultSet.getLong(resultSet.getColumnIndex('quota_requests_per_hour')),
      requestsPerDay: resultSet.getLong(resultSet.getColumnIndex('quota_requests_per_day')),
      tokensPerDay: resultSet.getLong(resultSet.getColumnIndex('quota_tokens_per_day')),
      maxConcurrentRequests: resultSet.getLong(resultSet.getColumnIndex('quota_max_concurrent')),
      maxTokens: resultSet.getLong(resultSet.getColumnIndex('quota_max_tokens')) as number
    };

    const registration: AppRegistration = {
      appId: resultSet.getString(resultSet.getColumnIndex('app_id')),
      appName: resultSet.getString(resultSet.getColumnIndex('app_name')),
      apiKey: resultSet.getString(resultSet.getColumnIndex('api_key')),
      bundleName: resultSet.getString(resultSet.getColumnIndex('bundle_name')),
      permissions: JSON.parse(resultSet.getString(resultSet.getColumnIndex('permissions')) || '[]') as string[],
      quota: quota,
      registeredAt: resultSet.getLong(resultSet.getColumnIndex('registered_at')),
      lastActiveAt: resultSet.getLong(resultSet.getColumnIndex('last_active_at')),
      status: resultSet.getString(resultSet.getColumnIndex('status')) as 'active' | 'suspended' | 'revoked'
    };
    
    return registration;
  }

  /**
   * 生成应用 ID
   */
  private generateAppId(): string {
    return `app_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
  }

  /**
   * 生成 API 密钥
   */
  private generateApiKey(): string {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    let result = 'lk_';
    for (let i = 0; i < 48; i++) {
      result += chars.charAt(Math.floor(Math.random() * chars.length));
    }
    return result;
  }

  /**
   * 保存应用信息
   */
  async saveApp(app: AppRegistration): Promise<void> {
    if (!this.store) {
      throw new Error('数据库连接未建立');
    }

    try {
      const values: AppSaveValues = {
        app_id: app.appId,
        app_name: app.appName,
        package_name: app.packageName || app.bundleName,
        description: app.description || '',
        permissions: JSON.stringify(app.permissions),
        quota_requests_per_minute: app.quota.requestsPerMinute,
        quota_requests_per_hour: app.quota.requestsPerHour,
        quota_requests_per_day: app.quota.requestsPerDay,
        quota_tokens_per_day: app.quota.tokensPerDay,
        quota_max_concurrent: app.quota.maxConcurrentRequests,
        is_active: app.isActive ? 1 : 0,
        created_at: app.createdAt ?? Date.now(),
        last_used_at: app.lastUsedAt
      };
      if (values.last_used_at !== undefined) {
        await this.store.executeSql(
          'INSERT INTO registered_apps (app_id, app_name, package_name, description, permissions, quota_requests_per_minute, quota_requests_per_hour, quota_requests_per_day, quota_tokens_per_day, quota_max_concurrent, is_active, created_at, last_used_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
          [
            String(values.app_id),
            String(values.app_name),
            String(values.package_name),
            String(values.description),
            String(values.permissions),
            Number(values.quota_requests_per_minute),
            Number(values.quota_requests_per_hour),
            Number(values.quota_requests_per_day),
            Number(values.quota_tokens_per_day),
            Number(values.quota_max_concurrent),
            Number(values.is_active),
            Number(values.created_at),
            Number(values.last_used_at)
          ]
        );
      } else {
        await this.store.executeSql(
          'INSERT INTO registered_apps (app_id, app_name, package_name, description, permissions, quota_requests_per_minute, quota_requests_per_hour, quota_requests_per_day, quota_tokens_per_day, quota_max_concurrent, is_active, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
          [
            String(values.app_id),
            String(values.app_name),
            String(values.package_name),
            String(values.description),
            String(values.permissions),
            Number(values.quota_requests_per_minute),
            Number(values.quota_requests_per_hour),
            Number(values.quota_requests_per_day),
            Number(values.quota_tokens_per_day),
            Number(values.quota_max_concurrent),
            Number(values.is_active),
            Number(values.created_at)
          ]
        );
      }
      console.log('[DatabaseManager] 应用信息保存成功:', app.appId);
      
    } catch (error) {
      console.error('[DatabaseManager] 保存应用信息失败:', error);
      const errorDetails = error instanceof Error ? error : new Error(String(error));
      throw new LingAIError(
        LingAIErrorCode.UNKNOWN_ERROR,
        '保存应用信息失败',
        errorDetails
      );
    }
  }

  /**
   * 获取应用信息
   */
  async getApp(appId: string): Promise<AppRegistration | null> {
    if (!this.store) {
      throw new Error('数据库连接未建立');
    }

    try {
      const predicates = new relationalStore.RdbPredicates('registered_apps');
      predicates.equalTo('app_id', appId);
      
      const resultSet = await this.store.query(predicates);
      
      if (resultSet.rowCount === 0) {
        resultSet.close();
        return null;
      }
      
      resultSet.goToFirstRow();
      const app = this.parseAppRegistrationFromResultSet(resultSet);
      resultSet.close();
      
      return app;
      
    } catch (error) {
      console.error('[DatabaseManager] 获取应用信息失败:', error);
      return null;
    }
  }

  /**
   * 根据包名获取应用信息
   */
  async getAppByPackageName(packageName: string): Promise<AppRegistration | null> {
    if (!this.store) {
      throw new Error('数据库连接未建立');
    }

    try {
      const predicates = new relationalStore.RdbPredicates('registered_apps');
      predicates.equalTo('package_name', packageName);
      
      const resultSet = await this.store.query(predicates);
      
      if (resultSet.rowCount === 0) {
        resultSet.close();
        return null;
      }
      
      resultSet.goToFirstRow();
      const app = this.parseAppRegistrationFromResultSet(resultSet);
      resultSet.close();
      
      return app;
      
    } catch (error) {
      console.error('[DatabaseManager] 根据包名获取应用信息失败:', error);
      return null;
    }
  }

  /**
   * 保存API Key信息
   */
  async saveApiKey(keyInfo: SaveApiKeyParams): Promise<void> {
    if (!this.store) {
      throw new Error('数据库连接未建立');
    }

    try {
      const values: ApiKeyInsertValues = {
        key_id: String(keyInfo.keyId),
        app_id: String(keyInfo.appId),
        key_hash: String(keyInfo.keyHash),
        key_prefix: String(keyInfo.keyPrefix),
        permissions: JSON.stringify(Array.isArray(keyInfo.permissions) ? keyInfo.permissions : []),
        is_active: keyInfo.isActive ? 1 : 0,
        created_at: Number(keyInfo.createdAt),
        last_used_at: keyInfo.lastUsedAt !== undefined ? Number(keyInfo.lastUsedAt) : null,
        expires_at: keyInfo.expiresAt !== undefined ? Number(keyInfo.expiresAt) : null,
        rate_limit_per_minute: Number(keyInfo.rateLimit.requestsPerMinute),
        rate_limit_per_hour: Number(keyInfo.rateLimit.requestsPerHour),
        rate_limit_per_day: Number(keyInfo.rateLimit.requestsPerDay)
      };
      await this.store.executeSql(
        'INSERT INTO api_keys (key_id, app_id, key_hash, key_prefix, permissions, is_active, created_at, rate_limit_per_minute, rate_limit_per_hour, rate_limit_per_day, last_used_at, expires_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          String(values.key_id),
          String(values.app_id),
          String(values.key_hash),
          String(values.key_prefix),
          String(values.permissions),
          Number(values.is_active),
          Number(values.created_at),
          Number(values.rate_limit_per_minute),
          Number(values.rate_limit_per_hour),
          Number(values.rate_limit_per_day),
          values.last_used_at !== null && values.last_used_at !== undefined ? Number(values.last_used_at) : null,
          values.expires_at !== null && values.expires_at !== undefined ? Number(values.expires_at) : null
        ]
      );
      console.log('[DatabaseManager] API Key 信息保存成功:', keyInfo.keyId);
      
    } catch (error) {
      console.error('[DatabaseManager] 保存 API Key 信息失败:', error);
      const errorDetails = error instanceof Error ? error : new Error(String(error));
      throw new LingAIError(
        LingAIErrorCode.UNKNOWN_ERROR,
        '保存 API Key 信息失败',
        errorDetails
      );
    }
  }

  /**
   * 根据哈希获取API Key信息
   */
  async getApiKeyByHash(keyHash: string): Promise<ExtendedApiKeyInfo | null> {
    if (!this.store) {
      throw new Error('数据库连接未建立');
    }

    try {
      const predicates = new relationalStore.RdbPredicates('api_keys');
      predicates.equalTo('key_hash', keyHash);
      
      const resultSet = await this.store.query(predicates);
      
      if (resultSet.rowCount === 0) {
        resultSet.close();
        return null;
      }
      
      resultSet.goToFirstRow();
      const keyInfo = this.parseApiKeyFromResultSet(resultSet);
      resultSet.close();
      
      return keyInfo;
      
    } catch (error) {
      console.error('[DatabaseManager] 根据哈希获取 API Key 失败:', error);
      return null;
    }
  }

  /**
   * 更新API Key最后使用时间
   */
  async updateApiKeyLastUsed(keyId: string, lastUsedAt: number): Promise<void> {
    if (!this.store) {
      return;
    }

    try {
      await this.store.executeSql(
        'UPDATE api_keys SET last_used_at = ? WHERE key_id = ?',
        [Number(lastUsedAt), String(keyId)]
      );
      
    } catch (error) {
      console.error('[DatabaseManager] 更新 API Key 使用时间失败:', error);
    }
  }

  /**
   * 更新API Key状态
   */
  async updateApiKeyStatus(keyId: string, isActive: boolean): Promise<void> {
    if (!this.store) {
      throw new Error('数据库连接未建立');
    }

    try {
      const activeNum = isActive ? 1 : 0;
      await this.store.executeSql(
        'UPDATE api_keys SET is_active = ? WHERE key_id = ?',
        [Number(activeNum), String(keyId)]
      );
      
    } catch (error) {
      console.error('[DatabaseManager] 更新 API Key 状态失败:', error);
      const errorDetails = error instanceof Error ? error : new Error(String(error));
      throw new LingAIError(
        LingAIErrorCode.UNKNOWN_ERROR,
        '更新 API Key 状态失败',
        errorDetails
      );
    }
  }

  /**
   * 更新应用配额
   */
  async updateAppQuota(appId: string, quota: AppQuota): Promise<void> {
    if (!this.store) {
      throw new Error('数据库连接未建立');
    }

    try {
      await this.store.executeSql(
        'UPDATE registered_apps SET quota_daily_requests = ?, quota_requests_per_minute = ?, quota_requests_per_hour = ?, quota_requests_per_day = ?, quota_tokens_per_day = ?, quota_max_concurrent = ?, quota_max_tokens = ? WHERE app_id = ?',
        [
          Number(quota.dailyRequests),
          Number(quota.requestsPerMinute),
          Number(quota.requestsPerHour),
          Number(quota.requestsPerDay),
          Number(quota.tokensPerDay),
          Number(quota.maxConcurrentRequests),
          Number(quota.maxTokens),
          String(appId)
        ]
      );
      
    } catch (error) {
      console.error('[DatabaseManager] 更新应用配额失败:', error);
      const errorDetails = error instanceof Error ? error : new Error(String(error));
      throw new LingAIError(
        LingAIErrorCode.UNKNOWN_ERROR,
        '更新应用配额失败',
        errorDetails
      );
    }
  }

  /**
   * 保存使用统计
   */
  async saveUsageStats(stats: ExtendedUsageStats): Promise<void> {
    if (!this.store) {
      throw new Error('数据库连接未建立');
    }

    try {
      const values: UsageStatsValues = {
        app_id: stats.appId,
        date: stats.date,
        requests: stats.requests,
        tokens: stats.tokens,
        errors: stats.errors,
        last_updated: stats.lastUpdated
      };

      // 使用 REPLACE 语句处理重复记录
      await this.store.executeSql(
        'REPLACE INTO usage_stats (app_id, date, requests, tokens, errors, last_updated) VALUES (?, ?, ?, ?, ?, ?)',
        [stats.appId, stats.date, stats.requests, stats.tokens, stats.errors, stats.lastUpdated]
      );
      
    } catch (error) {
      console.error('[DatabaseManager] 保存使用统计失败:', error);
      const errorDetails = error instanceof Error ? error : new Error(String(error));
      throw new LingAIError(
        LingAIErrorCode.UNKNOWN_ERROR,
        '保存使用统计失败',
        errorDetails
      );
    }
  }

  /**
   * 获取使用统计
   */
  async getUsageStats(appId: string, days: number): Promise<ExtendedUsageStats[]> {
    if (!this.store) {
      throw new Error('数据库连接未建立');
    }

    try {
      const startDate = new Date();
      startDate.setDate(startDate.getDate() - days);
      const startDateStr = startDate.toISOString().split('T')[0];

      const predicates = new relationalStore.RdbPredicates('usage_stats');
      predicates.equalTo('app_id', appId)
        .and()
        .greaterThanOrEqualTo('date', startDateStr)
        .orderByDesc('date');
      
      const resultSet = await this.store.query(predicates);
      const stats: ExtendedUsageStats[] = [];
      
      if (resultSet.rowCount > 0) {
        resultSet.goToFirstRow();
        do {
          stats.push(this.parseUsageStatsFromResultSet(resultSet));
        } while (resultSet.goToNextRow());
      }
      
      resultSet.close();
      return stats;
      
    } catch (error) {
      console.error('[DatabaseManager] 获取使用统计失败:', error);
      return [];
    }
  }

  /**
   * 从结果集解析应用注册信息
   */
  private parseAppRegistrationFromResultSet(resultSet: relationalStore.ResultSet): AppRegistration {
    const quota: AppQuota = {
      dailyRequests: resultSet.getLong(resultSet.getColumnIndex('quota_daily_requests')) as number,
      requestsPerMinute: resultSet.getLong(resultSet.getColumnIndex('quota_requests_per_minute')) as number,
      requestsPerHour: resultSet.getLong(resultSet.getColumnIndex('quota_requests_per_hour')) as number,
      requestsPerDay: resultSet.getLong(resultSet.getColumnIndex('quota_requests_per_day')) as number,
      tokensPerDay: resultSet.getLong(resultSet.getColumnIndex('quota_tokens_per_day')) as number,
      maxConcurrentRequests: resultSet.getLong(resultSet.getColumnIndex('quota_max_concurrent')) as number,
      maxTokens: resultSet.getLong(resultSet.getColumnIndex('quota_max_tokens')) as number
    };

    const registration: AppRegistration = {
      appId: resultSet.getString(resultSet.getColumnIndex('app_id')),
      appName: resultSet.getString(resultSet.getColumnIndex('app_name')),
      bundleName: resultSet.getString(resultSet.getColumnIndex('bundle_name')),
      packageName: resultSet.getString(resultSet.getColumnIndex('package_name')),
      description: resultSet.getString(resultSet.getColumnIndex('description')),
      permissions: JSON.parse(resultSet.getString(resultSet.getColumnIndex('permissions')) || '[]') as string[],
      quota: quota,
      registeredAt: resultSet.getLong(resultSet.getColumnIndex('registered_at')),
      lastActiveAt: resultSet.getLong(resultSet.getColumnIndex('last_active_at')),
      createdAt: resultSet.getLong(resultSet.getColumnIndex('created_at')),
      lastUsedAt: resultSet.getLong(resultSet.getColumnIndex('last_used_at')),
      isActive: resultSet.getLong(resultSet.getColumnIndex('is_active')) === 1,
      status: resultSet.getString(resultSet.getColumnIndex('status')) as 'active' | 'suspended' | 'revoked'
    };
    
    return registration;
  }

  /**
   * 从结果集解析 API Key 信息
   */
  private parseApiKeyFromResultSet(resultSet: relationalStore.ResultSet): ExtendedApiKeyInfo {
    return {
      keyId: resultSet.getString(resultSet.getColumnIndex('key_id')),
      appId: resultSet.getString(resultSet.getColumnIndex('app_id')),
      keyHash: resultSet.getString(resultSet.getColumnIndex('key_hash')),
      keyPrefix: resultSet.getString(resultSet.getColumnIndex('key_prefix')),
      permissions: JSON.parse(resultSet.getString(resultSet.getColumnIndex('permissions')) || '[]') as string[],
      isActive: resultSet.getLong(resultSet.getColumnIndex('is_active')) === 1,
      createdAt: resultSet.getLong(resultSet.getColumnIndex('created_at')),
      lastUsedAt: resultSet.getLong(resultSet.getColumnIndex('last_used_at')),
      expiresAt: resultSet.getLong(resultSet.getColumnIndex('expires_at')) || undefined,
      rateLimit: {
        requestsPerMinute: resultSet.getLong(resultSet.getColumnIndex('rate_limit_per_minute')),
        requestsPerHour: resultSet.getLong(resultSet.getColumnIndex('rate_limit_per_hour')),
        requestsPerDay: resultSet.getLong(resultSet.getColumnIndex('rate_limit_per_day'))
      } as RateLimit
    };
  }

  /**
   * 从结果集解析使用统计信息
   */
  private parseUsageStatsFromResultSet(resultSet: relationalStore.ResultSet): ExtendedUsageStats {
    return {
      appId: resultSet.getString(resultSet.getColumnIndex('app_id')),
      date: resultSet.getString(resultSet.getColumnIndex('date')),
      requestCount: 0, // 基础字段
      tokenCount: 0,   // 基础字段
      errorCount: 0,   // 基础字段
      requests: resultSet.getLong(resultSet.getColumnIndex('requests')),
      tokens: resultSet.getLong(resultSet.getColumnIndex('tokens')),
      errors: resultSet.getLong(resultSet.getColumnIndex('errors')),
      lastUpdated: resultSet.getLong(resultSet.getColumnIndex('last_updated'))
    };
  }

  /**
   * 检查连接状态
   */
  isConnected(): boolean {
    return this.connected && this.store !== null;
  }

  /**
   * 关闭数据库连接
   */
  async close(): Promise<void> {
    if (this.store) {
      // 注意：RdbStore没有显式的close方法，由系统自动管理
      this.store = null;
      this.connected = false;
      console.log('[DatabaseManager] 数据库连接已关闭');
    }
  }
}


