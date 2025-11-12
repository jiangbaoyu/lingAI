import { LingAIClient } from '../sdk/LingAIClient'
import { 
  ChatMessage, 
  MessageRole, 
  ModelInfo, 
  ModelStatus, 
  ModelType,
  LingAIConfig,
  ChatCompletionRequest,
  ChatCompletionResponse
} from '../sdk/types/LingAITypes'
import { promptAction } from '@kit.ArkUI'

@Entry
@Component
struct Index {
  @State private apiKey: string = ''
  @State private baseUrl: string = 'http://localhost:8080'
  @State private isConnected: boolean = false
  @State private connectionStatus: string = '未连接'
  @State private models: ModelInfo[] = []
  @State private selectedModel: string = ''
  @State private chatMessages: ChatMessage[] = []
  @State private currentMessage: string = ''
  @State private isLoading: boolean = false
  @State private showApiConfig: boolean = false
  @State private showModelManager: boolean = false

  
  private lingAIClient: LingAIClient | null = null

  aboutToAppear() {
    this.initializeApp();
    
    // 添加一些模拟数据用于测试界面
    // 创建明确的ChatMessage对象
    const chatMessage: ChatMessage = {
      id: '1',
      role: MessageRole.ASSISTANT,
      content: '欢迎使用灵桥AI桥接服务！请先配置API连接信息以开始使用。',
      timestamp: Date.now() - 60000
    };
    this.chatMessages = [chatMessage];
    
    // 模拟模型数据
    // 创建明确的ModelInfo对象
    const model1: ModelInfo = {
      id: 'qwen2.5-7b',
      name: 'Qwen2.5-7B',
      description: '通义千问2.5 7B参数模型，支持中文对话',
      size: 14000000000,
      type: ModelType.CHAT,
      status: ModelStatus.READY,
      createdAt: Date.now() - 86400000,
      updatedAt: Date.now()
    };
    
    const model2: ModelInfo = {
      id: 'llama2-13b',
      name: 'Llama2-13B',
      description: 'Meta Llama2 13B参数模型，英文对话',
      size: 26000000000,
      type: ModelType.CHAT,
      status: ModelStatus.AVAILABLE,
      createdAt: Date.now() - 172800000,
      updatedAt: Date.now()
    };
    
    this.models = [model1, model2];
    
    if (this.models.length > 0) {
      this.selectedModel = this.models[0].id;
    }
  }

  async initializeApp() {
    try {
      // 初始化配置
      // 创建明确的LingAIConfig对象
      const config: LingAIConfig = {
        apiKey: this.apiKey,
        baseUrl: this.baseUrl,
        debug: true
      };
      
      this.lingAIClient = new LingAIClient(config);
      
      if (this.apiKey) {
        await this.connectToServer();
      }
    } catch (error) {
      this.showErrorDialog('初始化失败: ' + (error as Error).message);
    }
  }

  async connectToServer() {
    if (!this.apiKey.trim()) {
      this.showErrorDialog('请输入API密钥');
      return;
    }

    this.isLoading = true;
    this.connectionStatus = '连接中...';

    try {
      if (!this.lingAIClient) {
        // 创建明确的LingAIConfig对象
        const config: LingAIConfig = {
          apiKey: this.apiKey,
          baseUrl: this.baseUrl,
          debug: true
        };
        this.lingAIClient = new LingAIClient(config);
      }

      await this.lingAIClient.initialize();
      
      this.isConnected = true;
      this.connectionStatus = '已连接';
      this.showApiConfig = false;
      
      // 加载模型列表
      await this.loadModels();
      
      this.showErrorDialog('连接成功！', false);
    } catch (error) {
      this.isConnected = false;
      this.connectionStatus = '连接失败';
      this.showErrorDialog('连接失败: ' + (error as Error).message);
    } finally {
      this.isLoading = false;
    }
  }

  async loadModels() {
    if (!this.lingAIClient) return

    try {
      this.models = await this.lingAIClient.listModels()
      
      // 选择第一个可用的聊天模型
      const chatModel = this.models.find(m => m.type === ModelType.CHAT && m.status === ModelStatus.READY)
      if (chatModel) {
        this.selectedModel = chatModel.id
      }
    } catch (error) {
      this.showErrorDialog('加载模型失败: ' + (error as Error).message)
    }
  }

  async sendMessage() {
    if (!this.currentMessage.trim() || !this.selectedModel || !this.isConnected) {
      return;
    }

    if (!this.lingAIClient) {
      this.showErrorDialog('SDK未初始化');
      return;
    }

    // 添加用户消息
    // 创建明确的ChatMessage对象
    const userMessage: ChatMessage = {
      id: Date.now().toString(),
      role: MessageRole.USER,
      content: this.currentMessage,
      timestamp: Date.now()
    };
    
    this.chatMessages.push(userMessage);
    this.currentMessage = '';
    this.isLoading = true;

    try {
      // 准备请求
      // 创建明确的ChatCompletionRequest对象
      const request: ChatCompletionRequest = {
        model: this.selectedModel,
        messages: this.chatMessages,
        temperature: 0.7,
        maxTokens: 2048
      };

      // 发送请求
      const response = await this.lingAIClient.chatCompletion(request);
      
      // 添加助手回复
      if (response.choices && response.choices.length > 0) {
        // 创建明确的ChatMessage对象
        const assistantMessage: ChatMessage = {
          id: (Date.now() + 1).toString(),
          role: MessageRole.ASSISTANT,
          content: response.choices[0].message.content,
          timestamp: Date.now()
        };
        this.chatMessages.push(assistantMessage);
      }
    } catch (error) {
      this.showErrorDialog('发送消息失败: ' + (error as Error).message);
    } finally {
      this.isLoading = false;
    }
  }

  showErrorDialog(message: string, isError: boolean = true) {
    if (isError) {
      // 创建明确的toast选项对象
      const toastOptions: {
        message: string;
        duration: number;
      } = {
        message: message,
        duration: 2000
      };
      promptAction.showToast(toastOptions);
    } else {
      // 创建明确的toast选项对象
      const toastOptions: {
        message: string;
        duration: number;
      } = {
        message: message,
        duration: 1500
      };
      promptAction.showToast(toastOptions);
    }
  }

  formatFileSize(bytes: number): string {
    if (bytes === 0) return '0 B'
    const k = 1024
    const sizes = ['B', 'KB', 'MB', 'GB']
    const i = Math.floor(Math.log(bytes) / Math.log(k))
    return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i]
  }

  build() {
    Column() {
      Row() {
        Text('LingAI 桥接服务')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
        
        Row() {
          Text(this.connectionStatus)
            .fontSize(14)
            .fontColor(this.isConnected ? '#4CAF50' : '#F44336')
            .margin({ right: 8 })
          
          Text('模型: ' + this.selectedModel)
            .fontSize(14)
            .fontColor('#757575')
            .margin({ right: 8 })
          
          Button('API配置')
            .onClick(() => {
              this.showApiConfig = true
            })
            .margin({ right: 8 })
          
          Button('模型管理')
            .onClick(() => {
              this.showModelManager = true
            })
        }
      }
      .width('100%')
      .padding(16)
      .backgroundColor(Color.White)
      .justifyContent(FlexAlign.SpaceBetween)
      .borderRadius(8)
      .margin({ bottom: 16 })

      if (this.isConnected) {
          Column() {
            Text('模型: ' + this.selectedModel)
              .fontSize(14)
              .fontColor('#757575')
              .margin({ bottom: 8 })

            Scroll() {
              Column() {
                ForEach(this.chatMessages, (message: ChatMessage) => {
                  Column() {
                    Text(message.role === MessageRole.USER ? '用户' : '助手')
                      .fontSize(12)
                      .fontColor('#9E9E9E')
                      .margin({ bottom: 4 })
                    
                    Text(message.content)
                      .fontSize(14)
                      .padding(12)
                      .backgroundColor(message.role === MessageRole.USER 
                        ? '#E3F2FD' 
                        : '#F5F5F5')
                      .borderRadius(8)
                      .width('80%')
                  }
                  .margin({ bottom: 8 })
                })
              }
            }
            .height(400)
            .margin({ bottom: 8 })

            Row() {
              TextInput({ text: this.currentMessage, placeholder: '输入消息...' })
                .width('80%')
                .height(40)
                .onChange((value: string) => {
                  this.currentMessage = value
                })
                .onSubmit(() => {
                  this.sendMessage()
                })
              
              Button('发送')
                .width('15%')
                .height(40)
                .onClick(() => {
                  this.sendMessage()
                })
                .margin({ left: 8 })
            }
          }
          .padding(16)
          .backgroundColor('#FAFAFA')
          .borderRadius(8)
          .height(600)
        } else {
        Column() {
          Text('欢迎使用 LingAI 桥接服务')
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .margin({ bottom: 16 })
          
          Text('请先配置API连接信息以开始使用')
            .fontSize(16)
            .fontColor('#757575')
            .margin({ bottom: 24 })
          
          Button('配置API连接')
            .onClick(() => {
              this.showApiConfig = true
            })
        }
        .padding(16)
        .backgroundColor('#FFFFFF')
        .borderRadius(8)
        .height(600)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    .padding(16)
    .backgroundColor('#F5F5F5')

    if (this.showApiConfig) {
      Column() {
        Row() {
          Text('API配置')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
          
          Button('✕')
            .onClick(() => {
              this.showApiConfig = false
            })
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceBetween)
        .margin({ bottom: 16 })

        Text('API密钥')
          .fontSize(16)
          .margin({ bottom: 8 })
        
        TextInput({ text: this.apiKey, placeholder: '请输入API密钥' })
          .width('100%')
          .height(40)
          .onChange((value: string) => {
            this.apiKey = value
          })
          .margin({ bottom: 16 })

        Text('基础URL')
          .fontSize(16)
          .margin({ bottom: 8 })
        
        TextInput({ text: this.baseUrl, placeholder: '请输入基础URL' })
          .width('100%')
          .height(40)
          .onChange((value: string) => {
            this.baseUrl = value
          })
          .margin({ bottom: 24 })

        Row() {
          Button('取消')
            .onClick(() => {
              this.showApiConfig = false
            })
            .margin({ right: 8 })
          
          Button('连接')
            .onClick(() => {
              this.connectToServer()
            })
        }
      }
      .width('80%')
      .padding(24)
      .backgroundColor('#FFFFFF')
      .borderRadius(8)
      .position({ x: '10%', y: '30%' })
    }

    if (this.showModelManager) {
      Column() {
        Row() {
          Text('模型管理')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
          
          Button('✕')
            .onClick(() => {
              this.showModelManager = false
            })
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceBetween)
        .margin({ bottom: 16 })

        if (this.models.length > 0) {
          Scroll() {
            Column() {
              ForEach(this.models, (model: ModelInfo) => {
                Row() {
                  Radio({ value: model.id, group: 'models' })
                    .checked(model.id === this.selectedModel)
                    .onChange((isChecked: boolean) => {
                      if (isChecked) {
                        this.selectedModel = model.id
                      }
                    })
                    .margin({ right: 8 })
                  
                  Column() {
                    Text(model.name)
                      .fontSize(16)
                      .fontWeight(FontWeight.Medium)
                    
                    Text(model.description)
                      .fontSize(12)
                      .fontColor('#757575')
                      .margin({ top: 4 })
                    
                    Row() {
                      Text('大小: ' + this.formatFileSize(model.size))
                        .fontSize(10)
                        .fontColor('#9E9E9E')
                      
                      Text('状态: ' + (model.status === ModelStatus.READY ? '就绪' : '未就绪'))
                        .fontSize(10)
                        .fontColor(model.status === ModelStatus.READY ? '#4CAF50' : '#FF9800')
                        .margin({ left: 8 })
                    }
                    .margin({ top: 4 })
                  }
                  .layoutWeight(1)
                }
                .width('100%')
                .padding(12)
                .backgroundColor('#F5F5F5')
                .borderRadius(8)
                .margin({ bottom: 8 })
              })
            }
          }
        } else {
          Text('暂无可用模型')
            .fontSize(16)
            .fontColor('#757575')
            .margin({ top: 50 })
        }

        Button('关闭')
          .onClick(() => {
            this.showModelManager = false
          })
          .margin({ top: 16 })
      }
      .width('80%')
      .height('60%')
      .padding(24)
      .backgroundColor('#FFFFFF')
      .borderRadius(8)
      .position({ x: '10%', y: '20%' })
    }
  }
}