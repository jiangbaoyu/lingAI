/**
 * LingAI 服务扩展能力
 * 提供跨应用AI服务调用能力
 */

import { Want } from '@kit.AbilityKit';
import rpc from '@ohos.rpc';
import { LingAIServiceStub } from './LingAIServiceStub';
import common from '@ohos.app.ability.common';

/**
 * LingAI服务扩展能力类
 */
export default class LingAIServiceExtension {
  private serviceStub: rpc.RemoteObject | null = null;
  private stubRef: LingAIServiceStub | null = null;
  private context: common.AppServiceExtensionContext;

  constructor(context: common.AppServiceExtensionContext) {
    this.context = context;
  }

  /**
   * 服务创建时调用
   */
  onCreate(want: Want): void {
    console.log('[LingAI] ServiceExtension onCreate');
    
    try {
      // 创建服务存根（包含所有服务逻辑）
      // AppServiceExtensionContext 继承自 Context，可以直接使用
      this.stubRef = new LingAIServiceStub(this.context);
      // 直接使用 stub 作为 RemoteObject（LingAIServiceStub 继承自 rpc.RemoteObject）
      this.serviceStub = this.stubRef;
      
      console.log('[LingAI] ServiceExtension 初始化完成');
    } catch (error) {
      console.error('[LingAI] ServiceExtension 初始化失败:', error);
    }
  }

  /**
   * 客户端连接时调用
   */
  onConnect(want: Want): rpc.RemoteObject | null {
    console.log('[LingAI] ServiceExtension onConnect');
    
    try {
      // 验证连接请求
      const bundleName = want.bundleName;
      
      if (!bundleName) {
        console.error('[LingAI] 连接请求缺少bundleName');
        return null;
      }
      
      console.log('[LingAI] 客户端连接成功:', bundleName);
      // 返回存根的RemoteObject引用（确保为 rpc.RemoteObject 类型）
      return this.serviceStub as rpc.RemoteObject | null;
      
    } catch (error) {
      console.error('[LingAI] 处理连接请求失败:', error);
      return null;
    }
  }

  /**
   * 客户端断开连接时调用
   */
  onDisconnect(want: Want): void {
    console.log('[LingAI] ServiceExtension onDisconnect');
    
    const bundleName = want.bundleName;
    if (bundleName) {
      console.log('[LingAI] 客户端断开连接:', bundleName);
    }
  }

  /**
   * 服务销毁时调用
   */
  async onDestroy(): Promise<void> {
    console.log('[LingAI] ServiceExtension onDestroy');
    
    try {
      // 清理服务存根资源（使用具体类型引用）
      if (this.stubRef) {
        await this.stubRef.cleanup();
        this.stubRef = null;
        this.serviceStub = null;
      }
      
      console.log('[LingAI] ServiceExtension 资源清理完成');
    } catch (error) {
      console.error('[LingAI] ServiceExtension 资源清理失败:', error);
    }
  }

  /**
   * 服务请求处理
   */
  onRequest(want: Want, startId: number): void {
    console.log('[LingAI] ServiceExtension onRequest, startId:', startId);
    
    // 处理特殊的服务请求
    const action = want.action;
    
    switch (action) {
      case 'com.lingyao.aibridge.action.HEALTH_CHECK':
        this.handleHealthCheck(want);
        break;
        
      case 'com.lingyao.aibridge.action.CLEANUP':
        this.handleCleanup(want);
        break;
        
      default:
        console.log('[LingAI] 未知的服务请求:', action);
        break;
    }
  }

  /**
   * 处理健康检查请求
   */
  private handleHealthCheck(want: Want): void {
    console.log('[LingAI] 处理健康检查请求');
    
    try {
      interface ServiceStatus {
        service: string;
        timestamp: number;
      }
      const statusObj: ServiceStatus = {
        service: 'running',
        timestamp: Date.now()
      };
      console.log('[LingAI] 服务状态:', JSON.stringify(statusObj));
    } catch (error) {
      console.error('[LingAI] 健康检查失败:', error);
    }
  }

  /**
   * 处理清理请求
   */
  private handleCleanup(want: Want): void {
    console.log('[LingAI] 处理清理请求');
    
    try {
      // 清理操作现在由ApiRouter内部处理
      console.log('[LingAI] 清理操作完成');
    } catch (error) {
      console.error('[LingAI] 清理操作失败:', error);
    }
  }

  /**
   * 配置变更时调用
   */
  onConfigurationUpdate(newConfig: Map<string, string | number | boolean>): void {
    console.log('[LingAI] ServiceExtension onConfigurationUpdate');
    
    try {
      // 配置更新现在由ApiRouter内部处理
      console.log('[LingAI] 配置更新完成');
    } catch (error) {
      console.error('[LingAI] 配置更新失败:', error);
    }
  }

  /**
   * 内存不足时调用
   */
  onMemoryLevel(level: number): void {
    console.log('[LingAI] ServiceExtension onMemoryLevel:', level);
    
    try {
      // 内存管理现在由ApiRouter内部处理
      console.log('[LingAI] 内存级别处理完成');
    } catch (error) {
      console.error('[LingAI] 内存处理失败:', error);
    }
  }
}
