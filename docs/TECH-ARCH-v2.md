# Navi - 技术架构文档 v2.0（基于 fullmoon-ios）

> 版本：v2.0 | 日期：2026-05-07 | 状态：Draft
> 关联文档：[PRODUCT-SPEC.md](./PRODUCT-SPEC.md)
> 基于：fullmoon-ios (MIT) + Swift Context Management (Silo-Labs) + LiteRTLM-Swift

---

## 1. 技术方案变更说明

### 1.1 变更背景

经调研，发现 fullmoon-ios 等现有开源项目均未实现完整的上下文管理逻辑（KV cache 淘汰、token window 截断、滑动窗口等）。为降低开发工作量，采用组合方案：

1. **fullmoon-ios**（MIT）→ UI 骨架（聊天、对话列表、设置、Onboarding、SwiftData 存储层）
2. **Swift Context Management**（Silo-Labs）→ 上下文管理策略（token window 截断、滑动窗口）
3. **LiteRTLM-Swift**（SPM）→ 推理引擎（Gemma 4 E2B IT，GPU backend）

### 1.2 性能基准数据

**Gemma 4 E2B IT on iPhone 15 Pro**（预估）：

| 框架 | Backend | Decode (tok/s) | 首 token (s) | 内存 (MB) |
|------|---------|----------------|--------------|-----------|
| MLX | GPU | ~35-40 | 0.5-0.8 | ~1200 |
| **LiteRT-LM** | **GPU** | **~50-55** | **0.3-0.4** | **~1450** |
| LiteRT-LM | CPU | ~25 | 1.5-2.0 | ~600 |

**结论**：LiteRT-LM GPU backend 更快，适合 Gemma 4 E2B IT。未来可启用 MTP（Multi-Token Prediction）drafter，再提速 2-3x。

---

## 2. 项目结构（基于 fullmoon-ios）

```
Navi/
├── Navi.xcodeproj
├── fullmoon/                              # fork 自 fullmoon-ios
│   ├── Models/
│   │   ├── LLMEvaluator.swift            # [待替换] → LiteRTInferenceService
│   │   ├── Models.swift                  # 模型配置定义
│   │   ├── Data.swift                    # SwiftData 模型
│   │   └── ContextManager.swift          # [新增] 上下文管理适配层
│   ├── Views/
│   │   ├── Chat/                         # [保留] 聊天 UI
│   │   │   ├── ChatView.swift
│   │   │   ├── ConversationView.swift
│   │   │   ├── MessageInputView.swift
│   │   │   └── [新增] ImagePreviewView.swift
│   │   ├── ConversationList/             # [保留] 对话列表
│   │   ├── Settings/                     # [保留] 设置
│   │   ├── Onboarding/                   # [保留] 首次启动引导
│   │   └── ModelSelection/               # [修改] 模型管理，增加 Gemma 4 E2B
│   └── [其他文件保留]
├── Packages/
│   ├── SwiftContextManagement/           # Swift Package，上下文管理策略
│   └── LiteRTLM-Swift/                   # Swift Package，LiteRT-LM 封装
└── docs/
    ├── PRODUCT-SPEC.md
    ├── TECH-ARCH.md
    └── TECH-ARCH-v2.md (本文档)
```

---

## 3. 核心模块设计

### 3.1 上下文管理（基于 Swift Context Management）

**Swift Context Management 功能**（Silo-Labs 提供）：

| 策略 | 描述 |
|------|------|
| Sliding Window | 保留最近 N 轮对话，丢弃最早对话 |
| Rolling Summary | 老对话压缩成摘要，新对话保留原文 |
| Progressive Reduction | 超限时自动加激进减策略 |
| Structured State | 提取关键事实/决策 |

**适配层设计**：

```swift
// fullmoon/Models/ContextManager.swift

import SwiftContextManagement
import LiteRTLMSwift

/// 适配 LiteRT-LM 接口到 Swift Context Management
actor ContextManager {
    private let maxContextTokens = 3072
    private let reductionPolicy: ReductionPolicy = .progressive(
        initialStrategy: .slidingWindow(maxTurns: 10),
        fallbackStrategies: [
            .slidingWindow(maxTurns: 5),
            .rollingSummary(targetTokens: 512)
        ]
    )
    
    private var contextManager: SwiftContextManager?
    
    func applyPolicy(to messages: [ChatMessage]) async -> [ChatMessage] {
        // 1. 将 ChatMessage 转为 Swift Context Management 的 Message 格式
        // 2. 调用 contextManager.reduce()
        // 3. 转回 ChatMessage
    }
    
    func clearCache() async {
        // 清空 Conversation 缓存，释放 KV-cache
    }
}
```

**工作流程**：

```
用户发送消息
  → ContextManager.applyPolicy() 滑动截断 history
  → 转为 LiteRT-LM 格式
  → LiteRTInferenceService.streamMessage()
  → 流式返回
  → ContextManager 缓存新消息（用于下次截断）
```

### 3.2 推理引擎（基于 LiteRTLM-Swift）

```swift
// fullmoon/Models/LiteRTInferenceService.swift（替换 LLMEvaluator.swift）

import LiteRTLMSwift

actor LiteRTInferenceService {
    private var engine: LiteRTLMEngine?
    private var currentConversationId: UUID?
    private var conversationCache: [UUID: LiteRTLMConversation] = [:]
    private var contextManager: ContextManager?
    
    func loadModel(id: String) async throws {
        // 从 model-registry.json 获取模型路径
        // 加载 LiteRTLMEngine
    }
    
    func streamMessage(
        _ text: String,
        imageData: Data? = nil,
        conversationId: UUID
    ) -> AsyncThrowingStream<String, Error> {
        // 1. 从 SwiftData 查询 history
        // 2. ContextManager.applyPolicy() 截断
        // 3. 发给模型推理
        // 4. 流式返回
    }
    
    func stopGeneration() {
        // 停止当前生成
    }
    
    func clearCache() async {
        // 释放 KV-cache
        conversationCache.removeAll()
    }
}
```

**性能优化**：

- GPU backend 优先，CPU fallback
- 支持 MTP（Multi-Token Prediction）drafter（未来）
- KV-cache 按会话管理，切换会话时释放

### 3.3 数据模型（继承自 fullmoon）

```swift
// fullmoon/Models/Data.swift

// 保留 fullmoon 的 SwiftData 模型，增加 vision 字段
@Model
final class Conversation {
    @Attribute(.unique) var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var modelId: String
    @Relationship(deleteRule: .cascade) var messages: [Message]
}

@Model
final class Message {
    @Attribute(.unique) var id: UUID
    var role: String  // "user" / "assistant"
    var text: String
    var imageData: Data?  // [新增] 图片数据
    var timestamp: Date
    var isComplete: Bool
    var conversation: Conversation?
}
```

### 3.4 拍照提问（新增功能）

```swift
// fullmoon/Views/Chat/ImagePreviewView.swift（新增）

import PhotosUI

struct ImagePreviewView: View {
    @Binding var selectedImage: UIImage?
    @State private var photoPickerItem: PhotosPickerItem?
    
    var body: some View {
        HStack(spacing: 12) {
            if let image = selectedImage {
                Image(uiImage: image)
                    .resizable()
                    .frame(width: 60, height: 60)
                    .cornerRadius(8)
                
                Button("移除") {
                    selectedImage = nil
                }
                .font(.caption)
            } else {
                PhotosPicker(selection: $photoPickerItem, matching: .images) {
                    Label("添加图片", systemImage: "photo")
                }
            }
        }
        .onChange(of: photoPickerItem) { newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    selectedImage = image
                }
            }
        }
    }
}
```

**集成到 MessageInputView**：

```swift
// 修改 fullmoon/Views/Chat/MessageInputView.swift
struct MessageInputView: View {
    @State private var selectedImage: UIImage?
    
    var body: some View {
        VStack {
            if selectedImage != nil {
                ImagePreviewView(selectedImage: $selectedImage)
            }
            
            HStack {
                TextField("输入消息...", text: $inputText)
                
                Button {
                    Task {
                        await sendMessage()
                    }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                }
            }
        }
    }
}
```

---

## 4. 依赖清单

| 依赖 | 版本 | 用途 | 引入方式 |
|------|------|------|----------|
| fullmoon-ios | main | UI 骨架（fork） | git submodule |
| Swift Context Management | 1.0+ | 上下文管理策略 | SPM |
| LiteRTLM-Swift | 0.1.0+ | LiteRT-LM Swift 封装 | SPM |
| SwiftData | 系统内置 | 数据持久化 | Framework |
| PhotosUI | 系统内置 | 图片选择 | Framework |

---

## 5. 模型配置

**model-registry.json**（更新自 fullmoon）：

```json
{
  "models": [
    {
      "id": "gemma-4-e2b-it",
      "displayName": "Gemma 4 E2B IT（推荐）",
      "fileName": "gemma-4-e2b-it.litertlm",
      "sizeMB": 2583,
      "isMultimodal": true,
      "downloadURL": "https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm",
      "recommended": true,
      "backend": "litert-lm",
      "description": "2.3B 参数，GPU backend ~50 tok/s，支持图片输入"
    }
  ],
  "defaultModelId": "gemma-4-e2b-it",
  "maxContextTokens": 3072,
  "memoryLimitMB": 4500
}
```

---

## 6. 工作量评估

| 任务 | 工作量 | 说明 |
|------|--------|------|
| Fork fullmoon-ios | 0.5h | git clone + 移除不必要的模型配置 |
| 替换 LLMEvaluator → LiteRTInferenceService | 2h | 实现 actor + LiteRTLM-Swift 集成 |
| 集成 Swift Context Management | 0.5h | SPM 依赖 + 适配层实现 |
| 新增拍照提问 UI | 1.5h | ImagePreviewView + MessageInputView 改造 |
| 图片预处理（压缩 + HEIC→JPEG） | 1h | 实现 ImageCompressor |
| 模型下载管理（改用 LiteRT-LM 格式） | 1h | 更新 download URL + 验证 |
| 测试 + 调试 | 2h | 真机测试、性能测试 |
| **总计** | **~8.5h** | 约 1 个工作日 |

---

## 7. 风险与缓解

| 风险 | 缓解措施 |
|------|----------|
| Swift Context Management 适配 LiteRT-LM 需要改造 | 预留 0.5h，如复杂则直接自己实现滑动窗口 |
| fullmoon 的 SwiftData 模型与我们需求不匹配 | 保留基础结构，增加 vision 字段即可 |
| Gemma 4 E2B 模型文件大（2.5GB），下载时间长 | fullmoon 已有下载管理，复用即可 |
| 内存压力（GPU backend 1.45GB） | increased-memory-limit entitlement + 内存警告监听 |

---

## 8. 下一步行动

1. Fork fullmoon-ios 到 Navi 仓库
2. 添加 Swift Context Management + LiteRTLM-Swift 依赖
3. 实现核心替换：LLMEvaluator → LiteRTInferenceService
4. 新增拍照提问 UI
5. 真机测试 Gemma 4 E2B IT 推理速度
6. 全面搜索其他项目，确认无遗漏

---

## 附录：fullmoon-ios 保留与修改清单

### 保留（无需修改）

- ✅ `fullmoon/Views/Chat/ChatView.swift` - 聊天 UI
- ✅ `fullmoon/Views/Chat/ConversationView.swift` - 对话详情 UI
- ✅ `fullmoon/Views/ConversationList/` - 对话列表
- ✅ `fullmoon/Views/Settings/` - 设置页
- ✅ `fullmoon/Views/Onboarding/` - 首次启动引导
- ✅ `fullmoon/Models/Data.swift` - SwiftData 模型（仅增加 imageData 字段）
- ✅ `fullmoon/Models/Models.swift` - 模型配置结构

### 修改/替换

- 🔄 `fullmoon/Models/LLMEvaluator.swift` → 替换为 `LiteRTInferenceService`
- 🔄 `fullmoon/Views/Chat/MessageInputView.swift` → 增加图片选择功能
- 🔄 `fullmoon/Models/Models.swift` → 更新模型列表，只保留 Gemma 4 E2B IT

### 新增

- ➕ `fullmoon/Models/ContextManager.swift` - 上下文管理适配层
- ➕ `fullmoon/Views/Chat/ImagePreviewView.swift` - 图片预览组件
- ➕ `fullmoon/Utilities/ImageCompressor.swift` - 图片压缩工具
- ➕ `fullmoon/Utilities/StreamThrottler.swift` - 流式输出节流
