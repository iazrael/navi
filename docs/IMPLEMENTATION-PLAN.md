# Navi - 实施计划

> 版本：v1.0 | 日期：2026-05-07 | 总工期：4 个 Sprint（约 5 个工作日）
> 前置文档：[PRODUCT-SPEC.md](./PRODUCT-SPEC.md) | [TECH-ARCH-v2.md](./TECH-ARCH-v2.md)

---

## 全局依赖关系

```
Sprint 1 (基础骨架) ──→ Sprint 2 (推理引擎) ──→ Sprint 3 (多模态+上下文) ──→ Sprint 4 (打磨+测试)
```

Sprint 1-2 串行，Sprint 3 部分任务可并行。Sprint 5 是可选的优化/打磨。

---

## Sprint 1：项目骨架与依赖集成

> **目标**：Fork fullmoon-ios，替换项目身份，集成 SPM 依赖，确保项目可编译运行。

### 任务 1.1：Fork fullmoon-ios 并重命名项目 🟢

**操作**：

1. 将 `/tmp/fullmoon-ios/` 复制到 `~/workspaces/navi/`
2. Xcode 中重命名项目：`fullmoon` → `Navi`
3. 修改 `fullmoonApp.swift` → `NaviApp.swift`，更新 `@main` 入口
4. 更新 `Info.plist`：应用名、Bundle Identifier、版本号
5. 删除 MLX 相关依赖引用（`import MLX`, `import MLXLLM`, `import MLXLMCommon`, `import MLXRandom`）— 这些会在 Sprint 2 被替换

**涉及文件**：

| 文件 | 操作 |
|------|------|
| `fullmoon/fullmoonApp.swift` | 重命名为 `NaviApp.swift`，更新结构体名 |
| `fullmoon/Models/LLMEvaluator.swift` | 临时注释掉 MLX 引用，避免编译错误 |
| `fullmoon/Models/Models.swift` | 临时注释掉 `import MLXLMCommon` |
| `fullmoon.xcodeproj/project.pbxproj` | 重命名项目 |
| `Package.swift` 或 `Package.resolved` | 移除 MLX 相关包依赖 |

**验收标准**：

- [ ] 项目在 Xcode 中可打开，无"missing package"错误
- [ ] 编译成功（允许运行时崩溃，编译通过即可）

---

### 任务 1.2：添加 SPM 依赖 🟡

**操作**：

1. 在 Xcode 项目中添加 Swift Package 依赖：
   - `https://github.com/mylovelycodes/LiteRTLM-Swift`（LiteRT-LM 推理引擎）
   - `https://github.com/Silo-Labs/swift-context-management`（上下文管理）
2. 在 target 的 Frameworks 中 link 这两个包

**风险说明**：Swift Context Management 是为 Apple FoundationModels 设计的，其 API（`ContextualSession`、`respond(to:)`）依赖 `FoundationModels` framework。它**不能直接用于 LiteRT-LM**。我们有两种路径：

- **路径 A**（推荐）：仅参考其策略设计，自己实现 `SlidingWindow` + `ProgressiveReduction`，不引入该 SPM 包
- **路径 B**：引入该包，尝试 fork 并改造其内部策略逻辑（工作量大，收益低）

**决策**：采用路径 A，不引入 Swift Context Management 包。自己实现一个轻量的 `ContextManager`，参考其策略模式。

**实际需要添加的 SPM 依赖**：

| 包 | URL | 用途 |
|---|---|---|
| LiteRTLM-Swift | `https://github.com/mylovelycodes/LiteRTLM-Swift` | 推理引擎 |

**涉及文件**：

| 文件 | 操作 |
|------|------|
| `Navi.xcodeproj/project.pbxproj` | 添加 SPM 依赖声明 |
| `Navi.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` | 自动生成 |

**验收标准**：

- [ ] LiteRTLM-Swift 包成功 resolve
- [ ] `import LiteRTLMSwift` 编译通过

---

### 任务 1.3：更新 SwiftData 模型 🟢

**操作**：

在 `Data.swift` 中为 `Message` 模型增加图片支持字段：

```swift
@Model
class Message {
    @Attribute(.unique) var id: UUID
    var role: Role
    var content: String
    var timestamp: Date
    var generatingTime: TimeInterval?
    
    // [新增] 图片支持
    var imageData: Data?           // 压缩后的 JPEG 缩略图
    var isComplete: Bool = true    // 生成是否完整（中断时为 false）
    
    @Relationship(inverse: \Thread.messages) var thread: Thread?
    
    init(role: Role, content: String, thread: Thread? = nil, 
         generatingTime: TimeInterval? = nil, imageData: Data? = nil) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.timestamp = Date()
        self.thread = thread
        self.generatingTime = generatingTime
        self.imageData = imageData
    }
}
```

为 `Thread` 增加模型 ID 字段：

```swift
@Model
final class Thread: Sendable {
    @Attribute(.unique) var id: UUID
    var title: String?
    var timestamp: Date
    var modelId: String?  // [新增] 记录使用的模型
    
    @Relationship var messages: [Message] = []
    // ...
}
```

**注意**：SwiftData 的 schema 变更需要轻量迁移。在 `NaviApp.swift` 中配置：

```swift
@main
struct NaviApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [Thread.self, Message.self])
    }
}
```

**涉及文件**：

| 文件 | 操作 |
|------|------|
| `fullmoon/Models/Data.swift` | 增加 `imageData`、`isComplete`、`modelId` 字段 |

**验收标准**：

- [ ] 新增字段编译通过
- [ ] 已有数据可正常迁移（新增字段为 optional/有默认值，自动轻量迁移）

---

### 任务 1.4：清理 fullmoon 残留配置 🟢

**操作**：

1. 移除 `Models.swift` 中所有 MLX 模型配置（`ModelConfiguration` extension）
2. 创建 `NaviModelConfig.swift`，定义 Navi 自己的模型配置结构：

```swift
// fullmoon/Models/NaviModelConfig.swift（新建）

import Foundation

struct NaviModel: Identifiable, Codable {
    let id: String
    let displayName: String
    let fileName: String
    let sizeMB: Int
    let isMultimodal: Bool
    let downloadURL: String
    let recommended: Bool
    let backend: String  // "litert-lm"
    let description: String
}

struct NaviModelRegistry {
    static let models: [NaviModel] = [
        NaviModel(
            id: "gemma-4-e2b-it",
            displayName: "Gemma 4 E2B IT（推荐）",
            fileName: "gemma-4-E2B-it.litertlm",
            sizeMB: 2583,
            isMultimodal: true,
            downloadURL: "https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm",
            recommended: true,
            backend: "litert-lm",
            description: "2.3B 参数，GPU backend ~50 tok/s，支持图片输入"
        )
    ]
    
    static var defaultModel: NaviModel {
        models.first { $0.recommended }!
    }
}
```

3. 更新 `AppManager` 中 `currentModelName` 的默认值为 `"gemma-4-e2b-it"`

**涉及文件**：

| 文件 | 操作 |
|------|------|
| `fullmoon/Models/Models.swift` | 重写：移除 MLX 依赖，改为 NaviModelConfig |
| `fullmoon/Models/Data.swift` | AppManager 中 `currentModelName` 默认值更新 |

**验收标准**：

- [ ] 无 MLX import 残留
- [ ] `NaviModelRegistry.defaultModel` 可正常访问

---

## Sprint 2：推理引擎替换（核心）

> **目标**：实现 `LiteRTInferenceService`，替换 `LLMEvaluator`，实现基础文本对话。

### 任务 2.1：实现 LiteRTInferenceService 🟡

**核心设计**：保持与 `LLMEvaluator` 相同的 `@Observable @MainActor` 接口，使 `ChatView` 和 `ConversationView` 的修改最小化。

```swift
// fullmoon/Models/LiteRTInferenceService.swift（新建）

import Foundation
import LiteRTLMSwift
import SwiftUI

@Observable
@MainActor
class LiteRTInferenceService {
    // --- 兼容 LLMEvaluator 接口 ---
    var running = false
    var cancelled = false
    var output = ""
    var stat = ""
    var thinkingTime: TimeInterval?
    
    // --- 内部状态 ---
    private var engine: LiteRTLMEngine?
    private var loadedModelId: String?
    
    // --- 配置 ---
    let maxTokens = 4096
    private let displayEveryNTokens = 4
    
    enum InferenceError: Error {
        case modelNotLoaded
        case engineBusy
    }
    
    func loadModel(_ model: NaviModel) async throws {
        // 1. 检查模型文件是否存在（Documents 目录）
        // 2. 如果已加载相同模型，直接返回
        // 3. 释放旧引擎
        // 4. LiteRTLMEngine(path: modelFilePath)
        // 5. 设置 loadedModelId
    }
    
    func generate(
        modelName: String, 
        thread: Thread, 
        systemPrompt: String,
        imageData: Data? = nil
    ) async -> String {
        guard !running else { return "" }
        
        running = true
        cancelled = false
        output = ""
        let startTime = Date()
        
        do {
            let model = NaviModelRegistry.models.first { $0.id == modelName } 
                ?? NaviModelRegistry.defaultModel
            try await loadModel(model)
            guard let engine = engine else { throw InferenceError.modelNotLoaded }
            
            // 构建 prompt（含上下文管理，见任务 2.3）
            let contextManager = ContextManager(maxContextTokens: 3072)
            let history = contextManager.buildPromptHistory(
                thread: thread, 
                systemPrompt: systemPrompt
            )
            
            if let imageData = imageData {
                // 多模态推理：使用 engine.vision() 或 conversation API
                let result = try await engine.vision(
                    imageData: imageData,
                    prompt: buildPromptFromHistory(history),
                    maxTokens: maxTokens
                )
                output = result
            } else {
                // 纯文本流式推理
                var tokenCount = 0
                for try await chunk in engine.generateStreaming(
                    prompt: buildPromptFromHistory(history)
                ) {
                    if cancelled { break }
                    tokenCount += 1
                    if tokenCount % displayEveryNTokens == 0 {
                        output = chunk  // LiteRTLM 的 streaming 行为需验证
                    }
                }
            }
            
            let elapsed = Date().timeIntervalSince(startTime)
            stat = "生成耗时: \(elapsed.formatted)"
            
        } catch {
            output = "推理失败: \(error.localizedDescription)"
        }
        
        running = false
        return output
    }
    
    func stop() {
        cancelled = true
        running = false
    }
    
    func unloadModel() {
        engine = nil
        loadedModelId = nil
    }
    
    // --- Private ---
    
    private func modelFilePath(for model: NaviModel) -> String {
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsDir.appendingPathComponent(model.fileName).path
    }
    
    private func buildPromptFromHistory(_ history: [[String: String]]) -> String {
        // 将 message history 转为 Gemma 4 turn marker 格式
        // Gemma 4 格式：<start_of_turn>user\n...\n<end_of_turn>\n<start_of_turn>model\n...\n<end_of_turn>
        var parts: [String] = []
        for msg in history {
            let role = msg["role"] == "assistant" ? "model" : "user"
            let content = msg["content"] ?? ""
            parts.append("<start_of_turn>\(role)\n\(content)\n<end_of_turn>")
        }
        parts.append("<start_of_turn>model\n")
        return parts.joined(separator: "\n")
    }
}
```

**关键风险**：

1. LiteRTLM-Swift 的 `generateStreaming` 返回的 chunk 格式需要真机验证 — 可能是增量文本也可能是累积文本
2. `engine.vision()` 是否支持同时传入多轮历史 + 图片，需要验证 — 如果不支持，需要使用 Conversation API（`openConversation` + `conversationSend`）
3. Gemma 4 的 turn marker 格式需要与 LiteRT-LM 的 tokenizer 匹配

**涉及文件**：

| 文件 | 操作 |
|------|------|
| `fullmoon/Models/LiteRTInferenceService.swift` | **新建** |

**验收标准**：

- [ ] `LiteRTInferenceService` 编译通过
- [ ] `@Observable` 属性（`running`, `output`, `stat`）可被 View 层正常绑定

---

### 任务 2.2：替换 LLMEvaluator 引用 🟡

**操作**：全局搜索 `LLMEvaluator` 引用，替换为 `LiteRTInferenceService`。

**需要修改的文件**：

| 文件 | 修改内容 | 风险 |
|------|---------|------|
| `ChatView.swift` | `@Environment(LLMEvaluator.self) var llm` → `@Environment(LiteRTInferenceService.self) var llm` | 🟢 纯文本替换 |
| `ConversationView.swift` | 同上（`MessageView` 和 `ConversationView` 各一处） | 🟢 纯文本替换 |
| `ModelsSettingsView.swift` | 模型切换逻辑：从 `LLMEvaluator.switchModel()` 改为 `LiteRTInferenceService.loadModel()` | 🟡 接口变化 |
| `OnboardingView.swift` / `OnboardingInstallModelView.swift` | 模型下载和加载逻辑适配 | 🟡 |
| `NaviApp.swift`（原 fullmoonApp.swift） | 环境注入：`.environment(LLMEvaluator())` → `.environment(LiteRTInferenceService())` | 🟢 |
| `fullmoon/Models/LLMEvaluator.swift` | **删除此文件** | 🟢 |

**验收标准**：

- [ ] 全局搜索 `LLMEvaluator` 无残留引用
- [ ] 全局搜索 `import MLX`、`import MLXLLM`、`import MLXLMCommon`、`import MLXRandom` 无残留
- [ ] 项目编译通过

---

### 任务 2.3：实现上下文管理（ContextManager）🟡

**设计决策**：不引入 Swift Context Management 包（它是为 Apple FoundationModels 设计的），自己实现轻量版。

```swift
// fullmoon/Models/ContextManager.swift（新建）

import Foundation

actor ContextManager {
    let maxContextTokens: Int
    
    init(maxContextTokens: Int = 3072) {
        self.maxContextTokens = maxContextTokens
    }
    
    /// 从 Thread 构建带上下文截断的 prompt history
    /// - Returns: `[[String: String]]` 格式的消息历史
    func buildPromptHistory(
        thread: Thread, 
        systemPrompt: String
    ) -> [[String: String]] {
        var history: [[String: String]] = []
        
        // 1. System prompt
        history.append(["role": "system", "content": systemPrompt])
        
        // 2. 滑动窗口策略：保留最近 N 轮对话
        let messages = thread.sortedMessages
        let maxTurns = 10  // 保守估计：10 轮约 2000-3000 tokens
        let startIndex = max(0, messages.count - maxTurns)
        let recentMessages = Array(messages[startIndex...])
        
        // 3. 如果截断了历史，插入一条压缩摘要（V2 功能）
        // if startIndex > 0 { ... }
        
        for message in recentMessages {
            let role = message.role.rawValue  // "user" / "assistant"
            var content = message.content
            
            // 如果有图片，追加图片描述占位（实际图片通过 vision API 传递）
            if message.imageData != nil {
                content = "[用户发送了一张图片]\n\(content)"
            }
            
            history.append(["role": role, "content": content])
        }
        
        return history
    }
    
    /// 估算 token 数（简单启发式：中文 ~1.5 字/token，英文 ~4 字符/token）
    func estimateTokens(_ text: String) -> Int {
        let chineseCount = text.filter { $0.isChineseCharacter }.count
        let otherCount = text.count - chineseCount
        return Int(Double(chineseCount) / 1.5) + otherCount / 4
    }
}

// Helper extension
extension Character {
    var isChineseCharacter: Bool {
        guard let scalar = unicodeScalars.first else { return false }
        return (0x4E00...0x9FFF).contains(scalar.value)
    }
}
```

**涉及文件**：

| 文件 | 操作 |
|------|------|
| `fullmoon/Models/ContextManager.swift` | **新建** |

**验收标准**：

- [ ] `ContextManager` 编译通过
- [ ] 输入 15 轮对话时，正确截断为最近 10 轮
- [ ] System prompt 始终保留在首位

---

### 任务 2.4：适配模型下载管理 🟢

**操作**：fullmoon 已有模型下载机制（`OnboardingInstallModelView` + `OnboardingDownloadingModelProgressView`）。需要适配：

1. 将下载 URL 从 MLX 格式（HuggingFace mlx-community）改为 LiteRT-LM 格式（HuggingFace litert-community）
2. 模型文件格式从 `.safetensors` 改为 `.litertlm`
3. 验证下载后文件完整性（文件大小校验）

**涉及文件**：

| 文件 | 操作 |
|------|------|
| `fullmoon/Models/NaviModelConfig.swift` | 已在 Sprint 1 定义，确保 downloadURL 正确 |
| `fullmoon/Views/Onboarding/OnboardingInstallModelView.swift` | 适配 NaviModel 配置 |
| `fullmoon/Views/Onboarding/OnboardingDownloadingModelProgressView.swift` | 适配下载逻辑 |
| `fullmoon/Views/Settings/ModelsSettingsView.swift` | 适配模型列表展示 |

**验收标准**：

- [ ] 模型列表展示 Gemma 4 E2B IT
- [ ] 下载功能正常（URL 有效、进度显示）
- [ ] 下载完成后文件存在于 Documents 目录

---

## Sprint 3：多模态与用户体验

> **目标**：实现拍照提问 UI、图片压缩、流式输出优化，完成完整用户体验。

### 任务 3.1：实现 ImagePreviewView 组件 🟢

```swift
// fullmoon/Views/Chat/ImagePreviewView.swift（新建）

import PhotosUI
import SwiftUI

struct ImagePreviewView: View {
    @Binding var selectedImage: UIImage?
    @State private var photoPickerItem: PhotosPickerItem?
    let onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            if let image = selectedImage {
                // 缩略图预览
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("已选择图片")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("移除") {
                        selectedImage = nil
                        onRemove()
                    }
                    .font(.caption)
                    .foregroundStyle(.red)
                }
                
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}
```

**涉及文件**：

| 文件 | 操作 |
|------|------|
| `fullmoon/Views/Chat/ImagePreviewView.swift` | **新建** |

---

### 任务 3.2：改造 MessageInputView / ChatView 支持图片 🟡

**操作**：修改 `ChatView.swift` 的 `chatInput` 部分，增加图片选择按钮和预览区域。

**ChatView.swift 修改要点**：

1. 新增状态：`@State private var selectedImage: UIImage?`
2. 在 `chatInput` HStack 左侧添加附件按钮：
   ```swift
   // 在 TextField 左侧、modelPickerButton 右侧添加
   PhotosPicker(selection: $photoPickerItem, matching: .images) {
       Image(systemName: "photo.on.rectangle")
           .frame(width: 24, height: 24)
   }
   ```
3. 在 `chatInput` 上方添加条件渲染的 `ImagePreviewView`
4. `generate()` 函数传递 `selectedImage` 的 JPEG 数据
5. 清空输入时同时清空 `selectedImage`

**关键代码路径（generate 函数改造）**：

```swift
private func generate() {
    if !isPromptEmpty || selectedImage != nil {
        // ... 创建/获取 thread ...
        
        let messageText = prompt
        let imageData = selectedImage?.jpegData(compressionQuality: 0.6)
        prompt = ""
        selectedImage = nil
        
        // 用户消息带图片
        let userMessage = Message(role: .user, content: messageText, thread: currentThread, imageData: imageData)
        sendMessage(userMessage)
        
        // AI 推理
        let output = await llm.generate(
            modelName: modelName, 
            thread: currentThread, 
            systemPrompt: appManager.systemPrompt,
            imageData: imageData
        )
        // ...
    }
}
```

**涉及文件**：

| 文件 | 操作 |
|------|------|
| `fullmoon/Views/Chat/ChatView.swift` | 增加 PhotosPicker、图片状态、generate() 传参 |

**验收标准**：

- [ ] 点击附件按钮弹出图片选择器
- [ ] 选择图片后输入栏上方显示缩略图预览
- [ ] 可移除已选图片
- [ ] 发送后图片保存在 Message 中

---

### 任务 3.3：实现图片压缩工具 🟢

```swift
// fullmoon/Utilities/ImageCompressor.swift（新建）

import UIKit

enum ImageCompressor {
    /// 压缩图片用于发送给模型（保持合理分辨率）
    static func compressForInference(_ image: UIImage, maxSize: CGSize = CGSize(width: 1024, height: 1024)) -> Data? {
        let scaled = scaleImage(image, to: maxSize)
        return scaled.jpegData(compressionQuality: 0.7)
    }
    
    /// 压缩图片用于聊天记录缩略图存储
    static func compressForThumbnail(_ image: UIImage) -> Data? {
        let thumbnail = scaleImage(image, to: CGSize(width: 200, height: 200))
        return thumbnail.jpegData(compressionQuality: 0.5)
    }
    
    private static func scaleImage(_ image: UIImage, to maxSize: CGSize) -> UIImage {
        let size = image.size
        let widthRatio = maxSize.width / size.width
        let heightRatio = maxSize.height / size.height
        let ratio = min(widthRatio, heightRatio, 1.0)  // 不放大
        
        let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
```

**涉及文件**：

| 文件 | 操作 |
|------|------|
| `fullmoon/Utilities/ImageCompressor.swift` | **新建** |

---

### 任务 3.4：改造 ConversationView 展示图片消息 🟢

**操作**：修改 `MessageView`，当 `message.imageData != nil` 时在用户消息气泡中展示缩略图。

```swift
// 在 MessageView.body 的 user 分支中，content 之前添加：

if let imageData = message.imageData, 
   let uiImage = UIImage(data: imageData) {
    Image(uiImage: uiImage)
        .resizable()
        .aspectRatio(contentMode: .fit)
        .frame(maxHeight: 200)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .padding(.top, 12)
}
```

**涉及文件**：

| 文件 | 操作 |
|------|------|
| `fullmoon/Views/Chat/ConversationView.swift` | MessageView 中增加图片渲染 |

**验收标准**：

- [ ] 用户消息中图片正确显示为缩略图
- [ ] AI 回复中无图片（仅文字）

---

### 任务 3.5：流式输出节流优化 🟢

**操作**：fullmoon 的 `displayEveryNTokens = 4` 策略值得保留。在 `LiteRTInferenceService` 中实现类似逻辑。

**新增文件**：

```swift
// fullmoon/Utilities/StreamThrottler.swift（新建）

import Foundation

/// 流式输出节流器，避免每个 token 都触发 UI 更新
actor StreamThrottler {
    private var buffer = ""
    private var lastUpdateTime: Date = .distantPast
    private let updateInterval: TimeInterval  // 秒
    private let maxBufferTokens: Int
    
    init(updateInterval: TimeInterval = 0.05, maxBufferTokens: Int = 4) {
        self.updateInterval = updateInterval
        self.maxBufferTokens = maxBufferTokens
    }
    
    func append(_ token: String) -> String? {
        buffer += token
        let now = Date()
        
        if buffer.count >= maxBufferTokens || now.timeIntervalSince(lastUpdateTime) >= updateInterval {
            let result = buffer
            buffer = ""
            lastUpdateTime = now
            return result
        }
        return nil  // 尚未到输出时机
    }
    
    func flush() -> String {
        let result = buffer
        buffer = ""
        return result
    }
}
```

**涉及文件**：

| 文件 | 操作 |
|------|------|
| `fullmoon/Utilities/StreamThrottler.swift` | **新建** |
| `fullmoon/Models/LiteRTInferenceService.swift` | 在 streaming 循环中使用 StreamThrottler |

---

## Sprint 4：集成测试与打磨

> **目标**：真机测试、性能调优、边界情况处理。

### 任务 4.1：真机端到端测试 🔴

**测试用例**：

| 编号 | 测试场景 | 预期结果 | 风险 |
|------|---------|---------|------|
| T1 | 冷启动 → 首次对话 | < 3s 从打开到可以输入 | 🟢 |
| T2 | 纯文本对话（5 轮） | 流式输出，≥ 15 tok/s | 🟡 首次需要真机基准数据 |
| T3 | 发送图片 + 文字提问 | AI 正确识别图片内容 | 🔴 vision API 行为未验证 |
| T4 | 多轮对话超过 10 轮 | 自动截断早期历史 | 🟢 |
| T5 | 生成中点击停止 | 保留已生成内容，标记不完整 | 🟢 |
| T6 | 切换模型 | 释放旧引擎，加载新引擎 | 🟡 |
| T7 | 杀掉进程重启 | 对话历史完整保留 | 🟢 |
| T8 | 内存压力（开多个 app） | 不 crash，可能降速 | 🟡 |

**关键风险项**：

1. **LiteRT-LM streaming API 行为** 🔴：`generateStreaming` 返回的 chunk 是增量还是累积？直接影响 `output` 变量的更新逻辑
2. **Vision API 兼容性** 🔴：`engine.vision()` 是否支持多轮上下文 + 图片？如果不支持，需要改用 Conversation API
3. **Gemma 4 prompt format** 🟡：LiteRT-LM 对 Gemma 4 的 turn marker 格式是否需要特殊处理

---

### 任务 4.2：内存管理优化 🟡

**操作**：

1. 添加内存警告监听：

```swift
// 在 NaviApp 或 LiteRTInferenceService 中
NotificationCenter.default.addObserver(
    forName: UIApplication.didReceiveMemoryWarningNotification,
    queue: .main
) { _ in
    Task { @MainActor in
        // 释放 KV-cache
        // 提示用户
    }
}
```

2. 配置 `increased-memory-limit` entitlement（如需超过默认限制）
3. 切换会话时释放上一会话的推理资源

**涉及文件**：

| 文件 | 操作 |
|------|------|
| `fullmoon/Models/LiteRTInferenceService.swift` | 添加内存管理逻辑 |
| `Navi.entitlements` | 增加 `com.apple.developer.kernel.increased-memory-limit` |

---

### 任务 4.3：错误处理与用户反馈 🟢

**操作**：

在 `LiteRTInferenceService.generate()` 中完善错误分支：

| 错误场景 | 处理方式 |
|---------|---------|
| 模型文件不存在 | 提示"模型未下载"，引导到模型管理页 |
| 模型加载失败 | 显示具体错误 + 重试按钮 |
| 推理 OOM | 提示"内存不足，建议关闭其他应用或使用更小模型" |
| 推理中断 | 保留已生成内容，`isComplete = false` |
| 下载中断 | 支持断点续传（如果 LiteRTLM 不支持则支持重新下载） |

**涉及文件**：

| 文件 | 操作 |
|------|------|
| `fullmoon/Models/LiteRTInferenceService.swift` | 完善 catch 分支 |
| `fullmoon/Views/Chat/ChatView.swift` | 错误提示 UI |

---

### 任务 4.4：Onboarding 流程适配 🟢

**操作**：确保首次启动流程正确：

1. 检查设备兼容性（≥ 8GB RAM，支持 Metal）
2. 引导下载模型
3. 下载完成后进入主界面

fullmoon 已有 `OnboardingView`、`DeviceNotSupportedView`、`OnboardingInstallModelView`，需要适配：
- 设备检查逻辑保留
- 模型下载 URL 改为 LiteRT-LM 格式
- 下载完成后使用 `LiteRTInferenceService.loadModel()` 而非 `LLMEvaluator.load()`

**涉及文件**：

| 文件 | 操作 |
|------|------|
| `fullmoon/Views/Onboarding/OnboardingView.swift` | 适配新模型配置 |
| `fullmoon/Views/Onboarding/OnboardingInstallModelView.swift` | 适配下载 URL |

---

## Sprint 5（可选）：优化与扩展

> **目标**：性能调优、多模型支持、体验细节打磨。

### 任务 5.1：多模型支持 🟢

在 `NaviModelRegistry` 中增加更多模型：

```swift
NaviModel(id: "gemma-3-1b-it", fileName: "gemma-3-1b-it.litertlm", sizeMB: 550, isMultimodal: true, ...),
NaviModel(id: "gemma-3-4b-it", fileName: "gemma-3-4b-it.litertlm", sizeMB: 2000, isMultimodal: true, ...),
```

### 任务 5.2：上下文管理增强（Rolling Summary）🟡

在 `ContextManager` 中实现 `RollingSummary` 策略：超过窗口的早期对话压缩为一条摘要消息。

### 任务 5.3：推理参数可配置 🟢

在设置页暴露 Temperature、Top-K、Max Tokens 参数，传入 `LiteRTInferenceService`。

---

## 风险汇总

| 风险 | 等级 | 影响范围 | 缓解措施 |
|------|------|---------|---------|
| LiteRTLM-Swift streaming API 行为不确定 | 🔴 | Sprint 2-3 | 先写 adapter 层隔离，真机验证后调整 |
| Vision API 不支持多轮上下文 + 图片 | 🔴 | Sprint 3 | 改用 Conversation API（`openConversation` + `conversationSend`） |
| Swift Context Management 不兼容 LiteRT-LM | 🟡 | Sprint 2 | 已决策：自己实现，不引入该包 |
| fullmoon SwiftData schema 与需求不匹配 | 🟢 | Sprint 1 | 增加 optional 字段，自动轻量迁移 |
| Gemma 4 prompt format 与 LiteRT-LM 不匹配 | 🟡 | Sprint 2 | 参考 LiteRTLM-Swift 文档中的 Prompt Format 部分 |
| 内存压力（GPU backend ~1.45GB） | 🟡 | Sprint 4 | increased-memory-limit + 内存警告监听 |

---

## 工期估算

| Sprint | 工作量 | 累计 |
|--------|--------|------|
| Sprint 1：项目骨架与依赖集成 | 0.5 天 | 0.5 天 |
| Sprint 2：推理引擎替换 | 1.5 天 | 2 天 |
| Sprint 3：多模态与用户体验 | 1.5 天 | 3.5 天 |
| Sprint 4：集成测试与打磨 | 1.5 天 | 5 天 |
| Sprint 5（可选）：优化与扩展 | 1 天 | 6 天 |

**核心工期**：5 个工作日（Sprint 1-4）
**含优化**：6 个工作日（+Sprint 5）

---

## 文件变更总览

### 新建文件（6 个）

| 文件 | 说明 |
|------|------|
| `fullmoon/Models/LiteRTInferenceService.swift` | 推理引擎，替换 LLMEvaluator |
| `fullmoon/Models/ContextManager.swift` | 上下文管理（滑动窗口） |
| `fullmoon/Models/NaviModelConfig.swift` | 模型配置注册表 |
| `fullmoon/Views/Chat/ImagePreviewView.swift` | 图片预览组件 |
| `fullmoon/Utilities/ImageCompressor.swift` | 图片压缩工具 |
| `fullmoon/Utilities/StreamThrottler.swift` | 流式输出节流 |

### 修改文件（8 个）

| 文件 | 修改说明 |
|------|---------|
| `fullmoon/fullmoonApp.swift` → `NaviApp.swift` | 重命名 + 环境注入改为 LiteRTInferenceService |
| `fullmoon/Models/Data.swift` | Message 增加 imageData/isComplete，Thread 增加 modelId |
| `fullmoon/Models/Models.swift` | 移除 MLX 模型配置，改为 NaviModelConfig |
| `fullmoon/Views/Chat/ChatView.swift` | LLMEvaluator→LiteRTInferenceService + 图片选择 |
| `fullmoon/Views/Chat/ConversationView.swift` | LLMEvaluator→LiteRTInferenceService + 图片消息渲染 |
| `fullmoon/Views/Settings/ModelsSettingsView.swift` | 适配 NaviModel 配置 |
| `fullmoon/Views/Onboarding/*.swift` | 适配模型下载和加载 |
| `fullmoon/ContentView.swift` | 适配新的环境注入 |

### 删除文件（1 个）

| 文件 | 说明 |
|------|------|
| `fullmoon/Models/LLMEvaluator.swift` | 被 LiteRTInferenceService 替代 |

---

## 开发顺序建议

严格按 Sprint 1 → 2 → 3 → 4 顺序执行。Sprint 2 是最关键的阶段，建议在一个完整的编码 session 中完成（推理引擎替换 + 编译通过）。

Sprint 2 完成后应立即在真机上验证推理是否可用，再继续 Sprint 3 的 UI 工作。如果 Sprint 2 遇到 LiteRT-LM API 问题，可以先用模拟的 `MockInferenceService` 继续推进 UI 工作。
