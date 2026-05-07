# Navi Code Review Report

> Reviewer: 老六 (Code Review Sub-Agent) | Date: 2026-05-07 | Model: GLM-5.1
> Project: Navi — 离线 AI 聊天助手 (based on fullmoon-ios)

## 总体评分：5.5/10

项目骨架完整，fullmoon fork 到 Navi 的身份切换和接口替换方向正确。但存在 **1 个编译阻断问题**、**若干接口兼容性隐患**、**并发安全设计缺陷** 和 **大量 TODO 占位**。当前状态是一个"能编译但不能跑"的半成品骨架。

---

## 🔴 Critical（必须修复，阻塞编译或运行）

### C1. `LiteRTLMEngine` 完全未集成 — 推理不可用
- **文件**: `LiteRTInferenceService.swift:38-39, 93-94, 137-172`
- **问题**: `engine` 属性被注释掉，`performStreamingInference` 和 `performVisionInference` 都是硬编码的 placeholder 返回字符串。整个推理链路实际上是一条死路。
- **影响**: 应用能编译但无法进行任何推理，所有对话都返回 `"[LiteRT-LM inference output placeholder]"`。
- **修复建议**: 
  1. 确认 `LiteRTLM-Swift` SPM 包已添加到项目
  2. 添加 `import LiteRTLMSwift`
  3. 取消注释 `private var engine: LiteRTLMEngine?` 
  4. 在 `loadModel` 中实现真正的引擎初始化
  5. 实现 streaming 和 vision 推理循环

### C2. `ContextManager` 是 actor 但 `LiteRTInferenceService` 直接 `await` 调用 — 潜在死锁
- **文件**: `LiteRTInferenceService.swift:98` vs `ContextManager.swift:18`
- **问题**: `LiteRTInferenceService` 标记为 `@MainActor`，`ContextManager` 标记为 `actor`。在 `generate()` 中通过 `await contextManager.buildPromptHistory()` 跨 actor 调用。这个调用本身没问题，但 `ContextManager` 作为一个无状态的纯计算单元被设计为 `actor` 是过度设计 — `buildPromptHistory` 只读取 `thread.sortedMessages` 并做数组切片，没有任何需要 actor 保护的可变状态。
- **影响**: 不必要的 actor 切换增加延迟和复杂度；如果未来在 `ContextManager` 中加入缓存等可变状态，可能产生与 `@MainActor` 的死锁。
- **修复建议**: 将 `ContextManager` 改为普通 `final class`（或 struct），不需要 actor 隔离。它只做无副作用的计算。

### C3. `StreamThrottler` 是 actor 但从未被使用
- **文件**: `StreamThrottler.swift` + `LiteRTInferenceService.swift`
- **问题**: `StreamThrottler` 已定义但在 `LiteRTInferenceService` 的 `performStreamingInference` 注释掉的代码中才引用。更重要的是，它被设计为 `actor`，但 streaming 循环内需要频繁 `await` 调用它，这在 `@MainActor` 上下文中会造成不必要的调度开销。
- **影响**: 当真正实现 streaming 时，actor 切换会成为性能瓶颈。
- **修复建议**: 改为 `final class` 或使用 `nonisolated(unsafe)` 的 buffer + lock，避免每 token 两次 actor 切换。

### C4. `RequestLLMIntent` 中创建了孤立的 `LiteRTInferenceService` 实例
- **文件**: `RequestLLMIntent.swift:51-52`
- **问题**: `let llm = LiteRTInferenceService()` 和 `let appManager = AppManager()` 在 Intent handler 中创建了全新的实例，与 App 主进程中的实例完全无关。Intent 中的模型加载和推理结果不会被主 App 看到。
- **影响**: Siri/Shortcuts 发起的对话完全独立于主 App，数据不共享，模型需要重新加载（且不会被缓存）。
- **修复建议**: 
  1. 使用 App Group 共享 SwiftData container
  2. 或者通过 `AppIntent` 的 `openAppWhenRun` 让用户回到 App 内完成操作
  3. 当前 `openAppWhenRun = false` 意味着完全后台运行，但没有持久化 Thread 数据

### C5. 模型下载功能完全缺失
- **文件**: `OnboardingDownloadingModelProgressView.swift:78-82`
- **问题**: `loadModel()` 只调用 `llm.switchModel(selectedModel)`，而 `switchModel` → `loadModel` 只检查文件是否已存在（`FileManager.default.fileExists`），不执行任何下载。2.5GB 的模型文件不会凭空出现在 Documents 目录。
- **影响**: Onboarding 流程中点击 install 后，会显示 "Failed to load model: The file doesn't exist"（或类似错误），用户无法完成首次设置。
- **修复建议**: 实现 `ModelDownloader`，使用 `URLSession` 下载模型文件，支持进度回调和断点续传。

---

## 🟡 Warning（应该修复，影响功能或质量）

### W1. `Models.swift` 中 `getPromptHistory` 与 `ContextManager.buildPromptHistory` 功能重复
- **文件**: `Models.swift:18-38` vs `ContextManager.swift:28-57`
- **问题**: 两个地方实现了几乎相同的 prompt history 构建逻辑。`Models.swift` 的版本不做滑动窗口截断，`ContextManager` 的版本做截断。如果 `LiteRTInferenceService` 用了 `ContextManager` 的版本（确实如此），那 `Models.swift` 的 `getPromptHistory` 是死代码。
- **修复建议**: 删除 `Models.swift` 中的 `getPromptHistory` 方法，或明确标注为 deprecated。

### W2. `Models.swift` 中 `NaviModelType` 和 `modelType` 计算属性冗余
- **文件**: `Models.swift:8-15`
- **问题**: `NaviModelType` 枚举只有 `.regular` 和 `.reasoning`，但 `modelType` 计算属性硬编码返回 `.regular`。这个类型系统没有在任何地方被使用。
- **修复建议**: 删除或在 `NaviModel` 结构体中加入 `modelType` 字段。

### W3. `DeviceStat` 是空壳类，`@unchecked Sendable` 无必要
- **文件**: `DeviceStat.swift`
- **问题**: `DeviceStat` 唯一的属性 `gpuActiveMemory` 永远是 0，从未被更新。同时它标记为 `@unchecked Sendable` 但又标记了 `@MainActor`，语义矛盾。
- **影响**: 占用了 `.environment(DeviceStat())` 注入但无实际功能。
- **修复建议**: 要么实现真正的 Metal 内存监控，要么暂时删除此文件和对应的环境注入。

### W4. `CreditsView` 仍然引用 MLX Swift
- **文件**: `CreditsView.swift:12`
- **问题**: Credits 页面中链接到 `MLX Swift`（`https://github.com/ml-explore/mlx-swift`），但 Navi 已经移除了 MLX 引擎。
- **修复建议**: 替换为 `LiteRTLM-Swift` 的 GitHub 链接，或添加 LiteRT-LM 的 credit。

### W5. `DeviceNotSupportedView` 文案仍为 "fullmoon"
- **文件**: `DeviceNotSupportedView.swift:13`
- **问题**: 错误信息为 "sorry, fullmoon can only run on devices that support Metal 3."
- **修复建议**: 改为 "sorry, Navi can only run on devices that support Metal 3."

### W6. `Thread` 标记 `Sendable` 但包含非 Sendable 关联类型
- **文件**: `Data.swift:104`
- **问题**: `final class Thread: Sendable` — SwiftData 的 `@Model` 类自动合成 conformance 时，`@Relationship var messages: [Message]` 中的 `Message` 不是 `Sendable` 的（也有 `@Relationship`）。这在严格并发检查下会产生警告。
- **修复建议**: SwiftData 的 `@Model` 类不需要手动标记 `Sendable`，移除 `: Sendable`。

### W7. `ChatView` 中 `FocusState.Binding` 初始化方式
- **文件**: `ChatView.swift:18`
- **问题**: `@FocusState.Binding var isPromptFocused: Bool` — 这是 iOS 17+ 的 API，用 `$isPromptFocused` 从父 View 传入。但 Preview 中使用 `@FocusState var isPromptFocused: Bool` 传给 `.constant()`，类型不匹配（`FocusState<Bool>.Binding` vs `Binding<Bool>`）。
- **影响**: Preview 可能编译失败。
- **修复建议**: Preview 中使用正确的 `@FocusState` 变量和 `$` 投影。

### W8. 图片双重压缩 — thumbnail 存入 Message，inference quality 传给引擎
- **文件**: `ChatView.swift:155-158`
- **问题**: `generate()` 中先对 selectedImage 做 `compressForThumbnail`（200x200）存入 Message，再对 pickedImage 做 `compressForInference`（1024x1024）传给引擎。这个设计是正确的，但 `pickedImage` 在 `selectedImage = nil` 之前被缓存了。如果 future 修改不注意顺序，会导致 image 丢失。
- **修复建议**: 加注释说明为什么需要保存两个引用，或提取为更清晰的变量名（如 `imageForStorage` / `imageForInference`）。

### W9. `ImagePreviewView` 中 `photoPickerItem` 状态未被使用
- **文件**: `ImagePreviewView.swift:12`
- **问题**: `@State private var photoPickerItem: PhotosPickerItem?` 声明了但从未绑定到任何 `PhotosPicker`。图片选择是在 `ChatView` 中完成的，`ImagePreviewView` 只负责展示预览和移除。
- **修复建议**: 删除未使用的 `photoPickerItem` 状态，以及在 `onRemove` 中 `photoPickerItem = nil` 的操作。

### W10. `OnboardingInstallModelView` 中模型过滤逻辑有问题
- **文件**: `OnboardingInstallModelView.swift:107-118`
- **问题**: `filteredModels` 过滤掉了已安装模型和建议模型（当 installedModels 为空时），这意味着如果用户只安装了推荐模型，`filteredModels` 为空，"other" section 不显示。如果用户没安装任何模型，推荐模型也被过滤掉。
- **影响**: 首次安装时 "suggested" section 显示推荐模型但 "other" section 可能为空（当前只有一个模型），这是预期行为。但如果未来添加更多模型，过滤逻辑需要重新审视。
- **修复建议**: 添加注释说明过滤意图，或为多模型场景准备更健壮的过滤逻辑。

### W11. `TimeInterval.formatted` 扩展未处理小数
- **文件**: `ConversationView.swift:12-23`
- **问题**: `formatted` 属性只返回整数秒，对于 0.5s 这种生成时间会显示 "0s"。模型推理通常首 token 时间在 0.3-2s 之间，整数秒精度不够。
- **修复建议**: 当 `totalSeconds < 5` 时显示一位小数，如 "1.3s"。

### W12. `ConversationView` 中 running 状态的流式 output 直接拼接 llm.output
- **文件**: `ConversationView.swift:139-145`
- **问题**: 当 `llm.running && !llm.output.isEmpty` 时，创建一个临时 `Message` 显示 `llm.output + " 🌕"`。这个临时 Message 没有持久化，生成完成后会被替换为真正的 assistant Message。但临时 Message 的 `id` 是自动生成的 UUID，在 ForEach 中可能产生闪烁。
- **修复建议**: 使用固定的 placeholder ID 或 `@State` 来管理临时消息的 ID。

### W13. `NaviApp` 使用 `@State var llm` 而非 `@StateObject`
- **文件**: `NaviApp.swift:17`
- **问题**: `LiteRTInferenceService` 是 `@Observable @MainActor class`（reference type），用 `@State` 在 SwiftUI 中对于 Observable 对象是可以的（iOS 17+ Observable pattern），但 `AppManager` 用的是 `@StateObject`（ObservableObject pattern）。两种模式混用增加维护负担。
- **修复建议**: 统一迁移到 `@Observable` pattern（将 `AppManager` 也改为 `@Observable`），或保持现状但添加注释说明两种模式的选择原因。

---

## 🟢 Suggestion（建议优化，非必须）

### S1. `NaviModelRegistry.models` 是硬编码数组
- **文件**: `NaviModelConfig.swift:27-39`
- **建议**: 考虑从远程 JSON 或本地配置文件加载模型列表，方便后续动态添加模型而不需要发版。

### S2. `estimateTokens` 启发式算法过于粗糙
- **文件**: `ContextManager.swift:61-64`
- **建议**: 对于 Gemma 模型，中文 token ratio 更接近 1.2-1.8 chars/token（取决于 tokenizer）。建议在真机上用实际 tokenizer 校准。

### S3. 魔法数字散落在代码中
- **涉及文件**: 多处
- `LiteRTInferenceService.swift`: `maxTokens = 4096`, `displayEveryNTokens = 4`
- `ContextManager.swift`: `maxContextTokens: 3072`, `maxTurns: 10`
- `ImageCompressor.swift`: `CGSize(width: 1024, height: 1024)`, `0.7`, `200x200`, `0.5`
- `StreamThrottler.swift`: `0.05`, `4`
- **建议**: 提取为配置常量或 `NaviConfig` 结构体，方便调参。

### S4. `Message.isComplete` 声明但从未使用
- **文件**: `Data.swift:82`
- **建议**: 设计文档中提到推理中断时应标记 `isComplete = false`，但 `generate()` 函数中没有设置。要么实现，要么删除以避免混淆。

### S5. `Thread.modelId` 声明但从未写入
- **文件**: `Data.swift:110`
- **建议**: 在 `generate()` 中设置 `currentThread.modelId = modelName`，这样历史对话可以追溯使用的模型。

### S6. 缺少错误状态的 UI 展示
- **文件**: `ChatView.swift`, `ConversationView.swift`
- **建议**: 当 `LiteRTInferenceService.generate()` 返回错误信息（如 "推理失败: ..."）时，应该在 UI 中以错误样式展示（红色/警告图标），而非普通 assistant 消息。

### S7. `ImageCompressor` 只支持 iOS（`UIKit`）
- **文件**: `ImageCompressor.swift`
- **建议**: 项目代码中有多处 `#if os(macOS)` 的平台适配，但 `ImageCompressor` 只 `import UIKit`。如果需要支持 macOS，需要 `#if canImport(UIKit)` / `#if canImport(AppKit)` 条件编译。

### S8. `ChatsListView` 使用 `DispatchQueue.main.asyncAfter` 做延迟删除
- **文件**: `ChatsListView.swift:103`
- **建议**: 这是从 fullmoon 继承的 workaround。SwiftData 的删除在某些情况下会有 UI 崩溃。考虑使用 `withAnimation` 或 Task 延迟代替 GCD。

### S9. `RequestLLMIntent` 中 `maxCharacters` 的 300 字符限制
- **文件**: `RequestLLMIntent.swift:43`
- **建议**: 连续对话模式下限制 300 字符对于 LLM 回复可能太短。中文 300 字符可能只有 ~200 token 的内容。建议增大到 500 或可配置。

### S10. 缺少单元测试
- **建议**: 至少为以下模块添加测试：
  - `ContextManager.buildPromptHistory` 的滑动窗口逻辑
  - `NaviModelRegistry` 的模型查找
  - `ImageCompressor` 的压缩效果
  - `buildPromptFromHistory` 的 Gemma 格式化

---

## ✅ 做得好的地方

1. **接口兼容性设计优秀**: `LiteRTInferenceService` 保持了与 `LLMEvaluator` 相同的 `@Observable @MainActor` 接口模式（`running`, `output`, `stat`, `generate()`），使得 View 层的替换成本极低 — 主要是全局替换类型名。

2. **图片双通道设计**: 在 `ChatView.generate()` 中区分了 thumbnail（存 SwiftData）和 inference quality（传引擎）两条路径，避免了在 SwiftData 中存储大体积图片数据。

3. **平台适配完整**: 保留了 fullmoon 对 iOS/macOS/visionOS 的条件编译支持，包括 `#if os(...)` 的 UI 差异处理。

4. **SwiftData 模型扩展合理**: `imageData: Data?` 和 `isComplete: Bool` 作为 optional/有默认值的字段，可以实现 SwiftData 的自动轻量迁移。

5. **模型注册表模式**: `NaviModelRegistry` 用静态注册表管理模型配置，支持按 ID 查找，比 fullmoon 原来的 MLX ModelConfiguration 更清晰。

6. **环境注入模式统一**: 通过 `.environment(LiteRTInferenceService())` + `@Environment(LiteRTInferenceService.self)` 的 Observable 注入，View 层不需要关心推理引擎的具体实现。

7. **代码风格一致**: 所有文件保持了统一的注释风格、缩进和命名规范，fullmoon 的原始代码风格被良好继承。

---

## 文件级审查清单

| 文件 | 状态 | 说明 |
|------|------|------|
| `NaviApp.swift` | ✅ 通过 | 入口文件，环境注入正确，macOS AppDelegate 保留完整 |
| `ContentView.swift` | ✅ 通过 | 平台分流、Onboarding、模型加载逻辑完整 |
| `Models/Data.swift` | ⚠️ 有问题 | `Thread: Sendable` 不必要；`isComplete`/`modelId` 未被使用；`AppManager` 混用 ObservableObject 模式 |
| `Models/LiteRTInferenceService.swift` | ❌ 严重问题 | 核心推理全部为 placeholder；引擎未集成；TODO 待真机验证 |
| `Models/ContextManager.swift` | ⚠️ 有问题 | actor 隔离不必要；与 Models.swift 功能重复 |
| `Models/Models.swift` | ⚠️ 有问题 | `getPromptHistory` 是死代码；`NaviModelType` 未使用 |
| `Models/NaviModelConfig.swift` | ✅ 通过 | 清晰的模型注册表设计 |
| `Models/DeviceStat.swift` | ⚠️ 有问题 | 空壳类，Sendable 标注矛盾 |
| `Models/RequestLLMIntent.swift` | ❌ 严重问题 | 创建孤立实例，数据不共享 |
| `Views/Chat/ChatView.swift` | ✅ 通过 | 图片选择、双通道压缩、环境注入均正确 |
| `Views/Chat/ConversationView.swift` | ⚠️ 有问题 | 时间格式精度不足；临时 Message ID 问题 |
| `Views/Chat/ImagePreviewView.swift` | ⚠️ 有问题 | 未使用的 `photoPickerItem` 状态 |
| `Views/Chat/ChatsListView.swift` | ✅ 通过 | fullmoon 原始代码，适配良好 |
| `Views/Onboarding/OnboardingView.swift` | ✅ 通过 | Navi 品牌替换完成 |
| `Views/Onboarding/OnboardingInstallModelView.swift` | ✅ 通过 | 模型列表适配 NaviModelRegistry |
| `Views/Onboarding/OnboardingDownloadingModelProgressView.swift` | ❌ 严重问题 | 无下载功能，只有模型加载 |
| `Views/Onboarding/DeviceNotSupportedView.swift` | ⚠️ 有问题 | 文案仍为 "fullmoon" |
| `Views/Onboarding/MoonAnimationView.swift` | ✅ 通过 | fullmoon 原始动画代码 |
| `Views/Settings/ModelsSettingsView.swift` | ✅ 通过 | 模型切换适配 LiteRTInferenceService |
| `Views/Settings/SettingsView.swift` | ✅ 通过 | 版本号显示 Navi |
| `Views/Settings/AppearanceSettingsView.swift` | ✅ 通过 | fullmoon 原始代码 |
| `Views/Settings/ChatsSettingsView.swift` | ✅ 通过 | fullmoon 原始代码 |
| `Views/Settings/CreditsView.swift` | ⚠️ 有问题 | 仍引用 MLX Swift |
| `Utilities/ImageCompressor.swift` | ⚠️ 有问题 | 仅支持 UIKit，macOS 不兼容 |
| `Utilities/StreamThrottler.swift` | ⚠️ 有问题 | actor 设计不合理；未被使用 |

---

## 优先修复路线图

| 优先级 | 任务 | 预计工时 |
|--------|------|---------|
| P0 | 集成 LiteRTLM-Swift，实现真正的推理引擎 (C1) | 4h |
| P0 | 实现模型下载功能 (C5) | 3h |
| P1 | 修复 RequestLLMIntent 孤立实例问题 (C4) | 2h |
| P1 | 将 ContextManager/StreamThrottler 从 actor 改为 class (C2, C3) | 0.5h |
| P2 | 修复遗留文案和 credit (W4, W5) | 0.5h |
| P2 | 清理死代码 (W1, W2, W3, S4, S5) | 1h |
| P3 | 提取魔法数字为配置 (S3) | 1h |
| P3 | 添加核心模块单元测试 (S10) | 2h |

**总预计修复工时**: ~14h（约 2 个工作日）
