# Navi - 技术架构文档

> 版本：v0.2 | 日期：2026-05-07 | 状态：Draft
> 关联文档：[PRODUCT-SPEC.md](./PRODUCT-SPEC.md)
> 评审记录：iOS 高级工程师评审 7.5/10，已修复全部 P0/P1 项

---

## 1. 技术选型总览

| 层级 | 选型 | 理由 |
|------|------|------|
| UI 框架 | SwiftUI | iOS 原生，声明式，适合聊天界面 |
| 架构模式 | MVVM | 职责清晰，SwiftUI 天然适配 |
| 推理引擎 | LiteRT-LM（C API） | 官方框架，支持多模态 |
| Swift 集成 | LiteRTLM-Swift（SPM） | 社区封装，支持 vision/streaming，直接引用 |
| 数据持久化 | SwiftData | Apple 原生，iOS 17+，免 SQL |
| 图片加载 | PhotosUI + ImageIO | 系统框架，零依赖 |
| 异步机制 | async/await + AsyncStream | 现代 Swift 并发，流式输出必需 |
| 并发安全 | Swift Actor | 推理服务用 actor 隔离，天然线程安全 |
| 日志 | OSLog（os.Logger） | 系统原生，零依赖，Instruments 集成 |
| 最低版本 | iOS 18.0 | Metal 性能优化，SwiftData 稳定版 |
| IDE | Xcode 16+ | 必需 |

---

## 2. 项目结构

```
Navi/
├── Navi.xcodeproj
├── Navi/
│   ├── App/
│   │   ├── NaviApp.swift              # App 入口 + DI 配置
│   │   ├── ContentView.swift          # 根视图（NavigationStack）
│   │   └── OnboardingView.swift       # 首次启动引导（下载模型）
│   │
│   ├── Views/
│   │   ├── ConversationList/
│   │   │   ├── ConversationListView.swift
│   │   │   └── ConversationRowView.swift
│   │   ├── Chat/
│   │   │   ├── ChatView.swift
│   │   │   ├── MessageBubbleView.swift
│   │   │   ├── InputBarView.swift
│   │   │   ├── ImagePreviewView.swift
│   │   │   └── ModelLoadingOverlay.swift
│   │   ├── Models/
│   │   │   ├── ModelManagerView.swift
│   │   │   └── ModelDownloadRow.swift
│   │   └── Settings/
│   │       └── SettingsView.swift
│   │
│   ├── ViewModels/
│   │   ├── ConversationListViewModel.swift
│   │   ├── ChatViewModel.swift
│   │   └── ModelManagerViewModel.swift
│   │
│   ├── Services/
│   │   ├── InferenceService.swift       # 推理协议
│   │   ├── LiteRTInferenceService.swift # LiteRT-LM 实现（actor）
│   │   ├── ModelDownloadService.swift   # 模型下载管理
│   │   └── MemoryMonitor.swift          # 内存警告监听
│   │
│   ├── Models/
│   │   ├── DTO/
│   │   │   ├── ChatMessage.swift        # 纯 DTO，Service 层使用
│   │   │   ├── AIModelDescriptor.swift  # 模型描述 DTO
│   │   │   └── ModelState.swift         # 模型状态枚举
│   │   ├── Persistence/
│   │   │   ├── ChatConversation.swift   # SwiftData 模型
│   │   │   └── PersistentMessage.swift  # SwiftData 模型
│   │   └── Registry/
│   │       └── ModelRegistry.swift      # model-registry.json 解析
│   │
│   ├── Utilities/
│   │   ├── ImageCompressor.swift        # 图片压缩（含 HEIC → JPEG）
│   │   ├── StreamThrottler.swift        # 流式输出 throttle
│   │   └── Constants.swift              # 常量定义
│   │
│   └── Resources/
│       ├── Assets.xcassets
│       └── model-registry.json          # 可用模型元数据
│
├── NaviTests/
├── NaviUITests/
├── docs/
│   ├── PRODUCT-SPEC.md
│   └── TECH-ARCH.md
└── Package.swift                         # SPM 依赖
```

---

## 3. 架构分层设计

```
┌──────────────────────────────────────────────┐
│                  Views (SwiftUI)              │
│  ConversationListView / ChatView /           │
│  ModelManagerView / SettingsView /           │
│  OnboardingView                              │
└──────────────────┬───────────────────────────┘
                   │ @Observable / @Environment
┌──────────────────▼───────────────────────────┐
│              ViewModels (@Observable)         │
│  ConversationListVM / ChatVM / ModelManagerVM│
│  • 持有 conversationId: UUID（不持有 @Model）  │
│  • 通过 ModelContext 间接访问 SwiftData       │
│  • 调用 Service 层（通过 @Environment 注入）   │
└──────────────────┬───────────────────────────┘
                   │
┌──────────────────▼───────────────────────────┐
│             Services Layer                    │
│                                              │
│  ┌──────────────────────────────────┐        │
│  │  InferenceService (protocol)     │        │
│  │  • 使用 ChatMessage DTO          │        │
│  │  • 暴露 ModelState 状态          │        │
│  │  • 支持 InferenceError 类型      │        │
│  └──────────┬───────────────────────┘        │
│             │ implements                      │
│  ┌──────────▼───────────────────────┐        │
│  │  LiteRTInferenceService (actor)  │        │
│  │  • actor 隔离，天然线程安全       │        │
│  │  • Engine 单例 + KV-cache 管理   │        │
│  │  • 上下文窗口滑动截断            │        │
│  │  • 图片预处理（后台线程）         │        │
│  │  • 流式输出 throttle             │        │
│  └──────────────────────────────────┘        │
│                                              │
│  ┌──────────────────────────────────┐        │
│  │  ModelDownloadService            │        │
│  │  • URLSession 下载 + 进度追踪    │        │
│  │  • 支持取消                      │        │
│  └──────────────────────────────────┘        │
│                                              │
│  ┌──────────────────────────────────┐        │
│  │  MemoryMonitor                   │        │
│  │  • 监听内存警告                  │        │
│  │  • 触发时释放 KV-cache / 卸载模型│        │
│  └──────────────────────────────────┘        │
└──────────────────────────────────────────────┘
                   │
┌──────────────────▼───────────────────────────┐
│           Data Layer (SwiftData)              │
│  ChatConversation / PersistentMessage         │
│  AppStorage (用户偏好)                         │
└──────────────────────────────────────────────┘
```

---

## 4. 核心模块详细设计

### 4.1 数据传输对象（DTO）

Service 层和 ViewModel 层之间使用纯 DTO，不依赖 SwiftData：

```swift
/// 独立于 SwiftData 的纯 DTO，用于 Service ↔ ViewModel 通信
struct ChatMessage: Sendable {
    let role: MessageRole
    let text: String
    let imageData: Data?
}

enum MessageRole: String, Sendable, Codable {
    case user
    case assistant
}

/// 模型生命周期状态
enum ModelState: Sendable {
    case idle                    // 未加载
    case downloading(progress: Double)  // 下载中
    case loading(progress: Double)      // 加载到内存中
    case ready                   // 就绪，可推理
    case inferencing             // 正在生成
    case error(InferenceError)   // 出错
}

/// 推理错误类型
enum InferenceError: Error, Sendable {
    case modelNotLoaded
    case modelNotFound(id: String)
    case modelLoadFailed(reason: String)
    case insufficientMemory
    case inferenceFailed(reason: String)
    case generationCancelled
    case imageDataInvalid
}

/// 模型描述信息
struct AIModelDescriptor: Sendable, Identifiable {
    let id: String              // 如 "gemma3-4b-it"
    let displayName: String     // 如 "Gemma 3 4B IT"
    let fileName: String        // 如 "gemma3-4b-it.litertlm"
    let sizeMB: Int
    let isMultimodal: Bool
    let downloadURL: URL
    let isRecommended: Bool
}
```

### 4.2 InferenceService 协议

```swift
protocol InferenceService: Sendable {
    /// 当前模型状态
    var modelState: ModelState { get }
    
    /// 当前已加载的模型 ID
    var currentModelId: String? { get }
    
    /// 加载模型
    func loadModel(id: String) async throws
    
    /// 卸载模型
    func unloadModel() async
    
    /// 同步发送文本消息
    func sendMessage(_ text: String, history: [ChatMessage]) async throws -> String
    
    /// 同步发送带图片的消息
    func sendMessageWithImage(_ text: String, imageData: Data, history: [ChatMessage]) async throws -> String
    
    /// 流式发送文本消息
    func streamMessage(_ text: String, history: [ChatMessage]) -> AsyncThrowingStream<String, Error>
    
    /// 流式发送带图片的消息
    func streamMessageWithImage(_ text: String, imageData: Data, history: [ChatMessage]) -> AsyncThrowingStream<String, Error>
    
    /// 停止当前生成
    func stopGeneration()
}
```

**设计意图**：
- 协议标记 `Sendable`，实现可以用 `actor`
- `history` 使用 `ChatMessage` DTO，不依赖 SwiftData
- `ModelState` 暴露完整生命周期，UI 可据此展示 loading/error 状态
- `InferenceError` 提供类型化错误，UI 可精确处理不同错误场景

### 4.3 LiteRTInferenceService 实现（Actor）

```swift
actor LiteRTInferenceService: InferenceService {
    private var engine: LiteRTLMEngine?
    private var activeConversationId: UUID?
    private var conversationCache: [UUID: LiteRTLMConversation] = [:]
    private var isGenerating = false
    private var generationTask: Task<Void, Never>?
    
    // 关键设计：
    
    // 1. 上下文窗口管理
    private let maxContextTokens = 3072  // 约 3K tokens，平衡质量和内存
    private var currentTokenCount = 0
    
    // 当 history 超出窗口时，使用滑动窗口截断最早的对话
    private func trimHistory(_ history: [ChatMessage]) -> [ChatMessage] {
        // 估算：1 token ≈ 0.75 英文词 / 0.5 中文字
        // 从最早的消息开始移除，直到 tokenCount < maxContextTokens
        // 保留最近的 maxContextTokens 个 token
    }
    
    // 2. Conversation 管理
    // 每个聊天会话对应一个 LiteRTLMConversation 实例
    // 切换会话时从缓存取或新建
    // KV-cache 与会话绑定，卸载会话时释放
    
    // 3. 图片预处理
    // HEIC → JPEG 转换（相册默认 HEIC）
    // 压缩到 512x512，JPEG 0.7
    // 在 actor 内部执行（天然后台线程）
}
```

### 4.4 依赖注入

```swift
// NaviApp.swift
@main
struct NaviApp: App {
    // 推理服务全局单例（actor）
    let inferenceService = LiteRTInferenceService()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(inferenceService)
        }
        .modelContainer(for: [ChatConversation.self, PersistentMessage.self])
    }
}
```

### 4.5 ChatViewModel

```swift
@Observable
@MainActor
final class ChatViewModel {
    var messages: [DisplayMessage] = []
    var inputText: String = ""
    var attachedImage: UIImage? = nil
    var isGenerating: Bool = false
    var streamingText: String = ""
    var modelState: ModelState = .idle
    
    private let inferenceService: InferenceService
    private let conversationId: UUID  // 不持有 SwiftData @Model 对象
    private let modelContext: ModelContext
    
    private let throttler = StreamThrottler(interval: .milliseconds(50))
    
    func sendMessage() async { ... }
    func stopGeneration() { ... }
    func attachImage(_ image: UIImage) { ... }
    func removeAttachedImage() { ... }
}
```

**流式输出处理流程**：
1. 用户点击发送 → `isGenerating = true`，输入栏禁用
2. 创建空的 assistant message 占位（写入 SwiftData）
3. 从 SwiftData 查询 history → 转为 `[ChatMessage]` DTO → 调用 `streamMessage()`
4. 订阅 `AsyncThrowingStream`，通过 `StreamThrottler`（50ms 间隔）合并更新
5. Throttle 触发时 → 追加到 `streamingText` → SwiftUI 刷新
6. Stream 结束或用户点击停止 → `isGenerating = false`，完整文本写入 SwiftData

**StreamThrottler 实现**：
```swift
/// 将高频的 token 流合并为低频的 UI 更新
actor StreamThrottler {
    let interval: Duration
    private var buffer = ""
    private var lastEmit: ContinuousClock.Instant?
    
    func append(_ token: String) -> String? {
        buffer += token
        let now = ContinuousClock.Instant.now
        guard let last = lastEmit, now - last >= interval else {
            return nil  // 还没到 emit 时间
        }
        lastEmit = now
        let result = buffer
        buffer = ""
        return result
    }
    
    func flush() -> String {
        let result = buffer
        buffer = ""
        return result
    }
}
```

### 4.6 数据模型（SwiftData）

```swift
/// 对话会话（SwiftData）
@Model
final class ChatConversation {
    @Attribute(.unique) var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var modelId: String
    @Relationship(deleteRule: .cascade, inverse: \PersistentMessage.conversation)
    var messages: [PersistentMessage]
    
    init(title: String = "", modelId: String) {
        self.id = UUID()
        self.title = title
        self.createdAt = Date()
        self.updatedAt = Date()
        self.modelId = modelId
        self.messages = []
    }
}

/// 消息（SwiftData）
@Model
final class PersistentMessage {
    @Attribute(.unique) var id: UUID
    var role: String  // "user" / "assistant"
    var text: String
    var imageData: Data?
    var timestamp: Date
    var isComplete: Bool  // 是否生成完毕（被中断的标记为 false）
    var conversation: ChatConversation?
    
    init(role: MessageRole, text: String, imageData: Data? = nil) {
        self.id = UUID()
        self.role = role.rawValue
        self.text = text
        self.imageData = imageData
        self.timestamp = Date()
        self.isComplete = true
    }
    
    /// 转为 DTO（用于传给 InferenceService）
    func toDTO() -> ChatMessage {
        ChatMessage(
            role: MessageRole(rawValue: role)!,
            text: text,
            imageData: imageData
        )
    }
}
```

**命名规范**：
- `ChatConversation` / `PersistentMessage` — SwiftData 模型，避免与 LiteRTLM 的 `Conversation` 冲突
- `ChatMessage` — 纯 DTO，Service 层使用
- `AIModelDescriptor` — 模型描述，避免与 LiteRTLM 的 model 概念混淆

### 4.7 内存管理策略

```swift
// MemoryMonitor.swift
final class MemoryMonitor {
    private let inferenceService: InferenceService
    private var cancellable: Any?
    
    func startMonitoring() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task {
                await self?.handleMemoryPressure()
            }
        }
    }
    
    private func handleMemoryPressure() async {
        // 1. 释放所有缓存的 Conversation 实例（KV-cache）
        // 2. 如果仍然紧张，卸载模型
        // 3. 通知 UI 显示内存警告
    }
}
```

**内存预算（iPhone 15 Pro 8GB）**：
| 组件 | 预估占用 |
|------|----------|
| 模型权重（Gemma 3 4B） | ~2GB |
| KV-cache（3072 tokens） | ~200-400MB |
| 图片缓冲区 | ~50MB |
| SwiftUI 渲染 | ~100-200MB |
| 系统开销 | ~500MB |
| **合计** | ~3-3.5GB（在 4-5GB 可用范围内） |

**策略**：
- 上下文窗口硬上限 3072 tokens，超出滑动截断
- 内存警告时优先释放 KV-cache（清空 Conversation 缓存）
- 二次警告时卸载模型，UI 显示重新加载提示
- 不在 app 启动时自动加载模型，用户进入聊天页时按需加载

### 4.8 后台行为策略

```
App 进入后台：
├── 推理中 → 等待当前生成完成（iOS 给 ~30s）
│   ├── 完成 → 正常 suspend，保留模型在内存
│   └── 超时 → stopGeneration()，保留已生成内容
├── 空闲 → 正常 suspend，保留模型
└── 收到内存警告 → 主动卸载模型，标记 modelState = .idle

App 回到前台：
├── modelState == .ready → 直接可用
└── modelState == .idle → 显示加载界面，重新加载模型
```

### 4.9 首次启动引导流程

```
首次启动：
1. 检查 Documents/models/ 目录下是否有模型文件
2. 无模型 → 显示 OnboardingView
   ├── 欢迎页面："欢迎使用 Navi，你的离线 AI 助手"
   ├── 模型选择：推荐 Gemma 3 4B IT，标注大小和说明
   ├── 下载进度页
   └── 下载完成 → 进入聊天界面
3. 有模型 → 直接进入对话列表
```

### 4.10 模型注册与下载

**model-registry.json**（内置在 app bundle 中）：
```json
{
  "models": [
    {
      "id": "gemma3-1b-it",
      "displayName": "Gemma 3 1B IT",
      "fileName": "gemma3-1b-it.litertlm",
      "sizeMB": 550,
      "isMultimodal": true,
      "downloadURL": "https://huggingface.co/litert-community/Gemma3-1B-IT/resolve/main/gemma3-1b-it.litertlm",
      "recommended": false,
      "description": "轻量级模型，响应快速，适合简单问答"
    },
    {
      "id": "gemma3-4b-it",
      "displayName": "Gemma 3 4B IT",
      "fileName": "gemma3-4b-it.litertlm",
      "sizeMB": 2000,
      "isMultimodal": true,
      "downloadURL": "https://huggingface.co/litert-community/Gemma3-4B-IT/resolve/main/gemma3-4b-it.litertlm",
      "recommended": true,
      "description": "推荐模型，平衡性能与质量，支持图片输入"
    }
  ],
  "note": "所有模型均为预转换的 .litertlm 格式，由 LiteRT 社区在 HuggingFace 上维护"
}
```

> **模型格式说明**：下载 URL 指向 HuggingFace 上 LiteRT 社区预转换好的 `.litertlm` 格式文件，无需用户自行转换。

**ModelDownloadService**：
- 使用 `URLSession` + `URLSessionDownloadTask`
- 暴露 `AsyncStream<Double>` 下载进度（0.0 ~ 1.0）
- 支持取消下载
- 下载完成后验证文件完整性（大小校验）
- 模型存储路径：`Documents/models/{modelId}.litertlm`

### 4.11 图片处理

```swift
struct ImageCompressor {
    /// 压缩图片用于模型输入和 SwiftData 存储
    /// - 支持 HEIC（相册默认格式）→ JPEG 转换
    /// - 在后台线程执行（由 actor 隔离保证）
    static func compress(_ image: UIImage, maxSize: CGSize = CGSize(width: 512, height: 512), quality: CGFloat = 0.7) -> Data? {
        // 1. 等比缩放到 maxSize 以内
        // 2. 转为 JPEG（自动处理 HEIC）
        // 3. 返回压缩后的 Data
    }
}
```

---

## 5. 关键技术决策

### 5.1 为什么选 LiteRTLM-Swift（SPM）

| 维度 | LiteRTLM-Swift (SPM) | Issue #1906 源码集成 | 直接用 C API |
|------|----------------------|---------------------|-------------|
| 集成方式 | SPM 依赖，一行搞定 | 手动复制源码 + C bridge + Bazel | 自己写 Swift 封装 |
| 维护成本 | 跟随社区更新 | 自己维护 fork | 自己维护封装层 |
| API 质量 | async/await 原生，API 简洁 | 更贴近 C++ API | 最底层 |
| Vision 支持 | 内置 `vision()` 方法 | 需要自己封装 | 需要自己封装 |
| 版本控制 | ⚠️ xcframework 版本锁定 | 可自行更新 | 完全控制 |

**决策**：先用 LiteRTLM-Swift SPM 快速起步。

**风险缓解**：
- InferenceService 协议隔离 → 迁移成本极低
- 在项目中记录使用的 LiteRTLM-Swift API 边界（`LiteRTLMEngine`、`vision()`、`generateStreaming()`、`openConversation`/`conversationSend`）
- 如果社区包停更，可降级到直接用 C API（需要 ~500 行 Swift 封装代码）

### 5.2 为什么用 SwiftData 而不是 Core Data

- SwiftData 是 iOS 17+ 的现代替代方案，代码量减少 60%+
- 目标 iOS 18.0+，SwiftData 已经稳定
- `@Model` 宏直接定义模型，不需要 `.xcdatamodeld`
- `@Query` 直接在 SwiftUI 中查询

**注意事项**：
- `@Relationship(deleteRule: .cascade)` 删除长对话可能卡 UI → 使用后台 context 操作
- 长对话分页加载，不一次加载全部 messages

### 5.3 上下文管理策略

**核心决策：LiteRTLM Conversation 管理上下文，SwiftData 只做展示存档**

```
数据流：
  用户发送消息
  → ViewModel 从 SwiftData 查询历史，转为 [ChatMessage] DTO
  → 传给 InferenceService.streamMessage()
  → LiteRTInferenceService.trimHistory() 滑动截断
  → 发给模型推理
  → 流式返回 → ViewModel 实时展示 + 最终写入 SwiftData
```

**为什么不用 LiteRTLM 的 openConversation/conversationSend**：
- LiteRTLM 的 Conversation API 内部管理历史，但我们还需要 SwiftData 存档用于 UI 展示
- 双写容易导致状态不一致
- 自己管理 history 更可控，可以精确控制 token 预算

### 5.4 图片处理策略

- 从相机/相册获取原图后，立即压缩：
  - 最大尺寸：512 x 512（LiteRT-LM vision 输入要求）
  - 压缩质量：JPEG 0.7
  - HEIC 自动转 JPEG（相册默认格式）
  - 预期大小：~50-100KB
- 压缩在 actor 内执行（天然后台线程），不卡 UI
- 压缩后数据同时用于：发送给模型 + 存入 SwiftData
- 不保留原图，避免存储膨胀

---

## 6. 依赖清单

| 依赖 | 版本 | 用途 | 引入方式 |
|------|------|------|----------|
| LiteRTLM-Swift | 0.1.0+ | LiteRT-LM Swift 封装 | SPM |
| SwiftData | 系统内置 | 数据持久化 | Framework |
| PhotosUI | 系统内置 | 相机/相册访问 | Framework |
| UIKit | 系统内置 | 图片压缩 | Framework |
| os | 系统内置 | OSLog 日志 | Framework |

> 零第三方 UI 库依赖。所有 UI 组件使用原生 SwiftUI。

**LiteRTLM-Swift 使用的 API 边界**（迁移时需替换的部分）：
- `LiteRTLMEngine(modelPath:)` / `engine.load()`
- `engine.generate()` / `engine.generateStreaming()`
- `engine.vision()` / `engine.visionMultiImage()`
- `engine.openConversation()` / `engine.conversationSend()`

---

## 7. 构建与部署

### 7.1 开发环境

- macOS 15.0+
- Xcode 16.0+
- Apple Developer Account（真机调试必需）
- 使用 SPM 管理依赖

### 7.2 构建步骤

```bash
# 1. 克隆项目
git clone <repo-url> && cd Navi

# 2. 打开 Xcode 项目，SPM 自动拉取依赖

# 3. 选择真机或模拟器构建
# ⚠️ 模拟器不支持 Metal GPU，推理速度会极慢
# 真机测试需要 Apple Developer Account

# 4. 首次运行需要配置 Signing Team
```

### 7.3 Entitlements 配置

```xml
<!-- Navi.entitlements -->
<key>com.apple.developer.kernel.increased-memory-limit</key>
<true/>
```

> 不加此 entitlement，加载 Gemma 3 4B 会被系统 kill。

### 7.4 真机部署注意事项

- 模型文件需要首次下载（~550MB ~ 2GB），建议 WiFi 环境
- Debug 模式推理速度比 Release 慢 2-3 倍，性能测试必须用 Release
- 首次模型加载约 5-10 秒（2GB 模型从 flash 读入内存），后续热启动 < 1s

---

## 8. 风险与缓解

| 风险 | 影响 | 概率 | 缓解措施 |
|------|------|------|----------|
| LiteRTLM-Swift 停止维护 | 无法跟进 LiteRT-LM 新特性 | 中 | InferenceService 协议隔离 + 记录 API 边界 |
| 官方 Swift API 发布 | 需要迁移 | 高 | 协议层 + DTO 隔离，预估 1-2 天 |
| 8GB 内存紧张 | 大模型 + 长对话可能被 kill | 中 | maxContextTokens=3072 + 内存警告监听 + 小模型选项 |
| 模型中文质量差 | 用户体验不达标 | 高 | 提供 Qwen 中文模型选项 |
| iOS 模拟器无法测试 GPU | 开发效率受影响 | 确定 | CPU 模式可测试逻辑，UI 可模拟器验证 |
| LiteRTLM-Swift xcframework 版本锁定 | 无法跟进 LiteRT-LM bugfix | 中 | 记录 API 边界，可降级到直接用 C API |

---

## 9. 迁移路径

当 Google 官方发布 LiteRT-LM Swift API 时：

1. 新增 `OfficialInferenceService` 实现 `InferenceService` 协议
2. 在 `NaviApp.swift` 中切换 DI 注入
3. 移除 `LiteRTLM-Swift` SPM 依赖
4. DTO 层（`ChatMessage`/`ModelState`/`InferenceError`）无需修改
5. ViewModel 层无需修改（只依赖协议）
6. 全量回归测试

预估迁移工作量：**1-2 天**

---

## 10. Accessibility（基本支持）

- VoiceOver：消息气泡添加 `.accessibilityLabel()`，标注角色和内容
- Dynamic Type：聊天文字支持用户字号设置，最大支持 2x
- 对比度：遵循系统浅色/深色主题，不使用自定义低对比度颜色
- 输入栏：确保键盘与输入栏的交互对 VoiceOver 可用

---

## 附录：评审修改记录

| 版本 | 日期 | 修改内容 |
|------|------|----------|
| v0.1 | 2026-05-07 | 初始版本 |
| v0.2 | 2026-05-07 | 根据 iOS 高级工程师评审（7.5/10）修复全部 P0/P1 项 |
