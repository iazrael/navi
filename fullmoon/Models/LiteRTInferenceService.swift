//
//  LiteRTInferenceService.swift
//  Navi
//
//  Replaces fullmoon's LLMEvaluator with LiteRT-LM based inference.
//  Maintains the same @Observable @MainActor interface for minimal View-layer changes.
//

import Foundation
import SwiftUI
// NOTE: Add LiteRTLM-Swift SPM dependency in Xcode:
//   https://github.com/mylovelycodes/LiteRTLM-Swift
// Then uncomment the import below:
// import LiteRTLMSwift

@Observable
@MainActor
class LiteRTInferenceService {
    // --- Compatible with LLMEvaluator interface ---
    var running = false
    var cancelled = false
    var output = ""
    var modelInfo = ""
    var stat = ""
    var progress = 0.0
    var thinkingTime: TimeInterval?
    var collapsed: Bool = false
    var isThinking: Bool = false

    /// Last inference error for UI display
    var lastError: InferenceError?

    var elapsedTime: TimeInterval? {
        if let startTime {
            return Date().timeIntervalSince(startTime)
        }
        return nil
    }

    private var startTime: Date?

    // --- Internal state ---
    private var engine: Any? // Will be LiteRTLMEngine once SPM dependency added
    private var loadedModelId: String?

    // --- Memory management ---
    private var backgroundTask: Task<Void, Never>?
    private var memoryWarningObserver: NSObjectProtocol?

    // --- Configuration ---
    var maxTokens: Int { inferenceConfig.maxTokens }
    private let displayEveryNTokens = 4
    private let contextManager = ContextManager(maxContextTokens: NaviConfig.maxContextTokens)

    /// Current inference configuration (persisted via AppManager)
    var inferenceConfig: InferenceConfig = InferenceConfig.load()

    enum InferenceError: Error, LocalizedError {
        case modelNotLoaded
        case engineBusy
        case modelFileNotFound(String)
        case loadFailed(String)
        case inferenceFailed(String)
        case outOfMemory
        case cancelled

        var errorDescription: String? {
            switch self {
            case .modelNotLoaded:
                return "模型未加载，请先下载并选择一个模型"
            case .engineBusy:
                return "推理引擎正在忙碌中"
            case .modelFileNotFound(let name):
                return "模型文件不存在：\(name)。请前往模型管理页下载"
            case .loadFailed(let reason):
                return "模型加载失败：\(reason)"
            case .inferenceFailed(let reason):
                return "推理失败：\(reason)"
            case .outOfMemory:
                return "内存不足，建议关闭其他应用或使用更小的模型"
            case .cancelled:
                return "推理已取消"
            }
        }

        /// User-friendly recovery suggestion
        var recoverySuggestion: String? {
            switch self {
            case .modelNotLoaded, .modelFileNotFound:
                return "前往 模型管理 下载模型"
            case .loadFailed:
                return "请重试或切换其他模型"
            case .outOfMemory:
                return "关闭其他应用后重试，或在设置中选择更小的模型"
            default:
                return nil
            }
        }

        /// Whether this error should show a "go to models" action
        var shouldShowModelManagement: Bool {
            switch self {
            case .modelNotLoaded, .modelFileNotFound:
                return true
            default:
                return false
            }
        }

        /// Whether this error should show a retry button
        var shouldShowRetry: Bool {
            switch self {
            case .loadFailed, .outOfMemory, .inferenceFailed:
                return true
            default:
                return false
            }
        }
    }

    // MARK: - Initialization

    init() {
        setupMemoryWarningHandling()
    }

    deinit {
        if let observer = memoryWarningObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Memory Warning Handling (Sprint 4.2)

    private func setupMemoryWarningHandling() {
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.handleMemoryWarning()
            }
        }
    }

    private func handleMemoryWarning() async {
        // Release KV-cache and unload model
        unloadModel()
        lastError = .outOfMemory
        modelInfo = "内存警告：已释放模型资源"
    }

    // MARK: - Background Handling (Sprint 4.2)

    /// Called when app enters background. Keeps model loaded for 30 seconds, then releases.
    func handleEnterBackground() {
        backgroundTask?.cancel()
        backgroundTask = Task {
            // Keep model for 30 seconds in case user returns quickly
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled else { return }
            if self.engine != nil {
                self.unloadModel()
                self.modelInfo = "后台超时：已释放模型（重新进入时自动加载）"
            }
        }
    }

    /// Called when app enters foreground. Reloads model if needed.
    func handleEnterForeground() {
        backgroundTask?.cancel()
        backgroundTask = nil
    }

    // MARK: - Model Loading

    func load(modelName: String) async throws {
        guard let model = NaviModelRegistry.getModelById(modelName) else {
            throw InferenceError.modelFileNotFound(modelName)
        }
        try await loadModel(model)
    }

    func switchModel(_ model: NaviModel) async {
        progress = 0.0
        lastError = nil
        do {
            try await loadModel(model)
        } catch let error as InferenceError {
            lastError = error
            modelInfo = error.localizedDescription
        } catch {
            let inferenceError = InferenceError.loadFailed(error.localizedDescription)
            lastError = inferenceError
            modelInfo = inferenceError.localizedDescription
        }
    }

    private func loadModel(_ model: NaviModel) async throws {
        // Skip if already loaded
        if loadedModelId == model.id { return }

        let filePath = modelFilePath(for: model)

        // Check if model file exists
        guard FileManager.default.fileExists(atPath: filePath) else {
            throw InferenceError.modelFileNotFound(model.displayName)
        }

        // Unload previous engine
        unloadModel()

        progress = 0.2

        do {
            // Initialize LiteRTLMEngine and load model
            // When LiteRTLM-Swift SPM is added, this becomes:
            //   let litertEngine = LiteRTLMEngine(modelPath: filePath, backend: "gpu")
            //   try await litertEngine.load()
            //   engine = litertEngine

            // TODO: verify with LiteRTLM-Swift docs - uncomment when SPM dependency is added
            // let litertEngine = LiteRTLMEngine(modelPath: filePath, backend: "gpu")
            // try await litertEngine.load()
            // engine = litertEngine

            loadedModelId = model.id
            modelInfo = "Loaded \(model.displayName)"
            progress = 1.0
        } catch {
            unloadModel()
            throw InferenceError.loadFailed(error.localizedDescription)
        }
    }

    // MARK: - Generation

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
        lastError = nil
        startTime = Date()

        do {
            let model = NaviModelRegistry.getModelById(modelName) ?? NaviModelRegistry.defaultModel
            try await loadModel(model)

            // Build prompt history with context management
            let history = await contextManager.buildPromptHistory(
                thread: thread,
                systemPrompt: systemPrompt
            )
            let promptText = buildPromptFromHistory(history)

            if let imageData = imageData {
                // Multimodal inference path
                output = try await performVisionInference(
                    prompt: promptText,
                    imageData: imageData
                )
            } else {
                // Text-only streaming inference path
                output = try await performStreamingInference(prompt: promptText)
            }

            let elapsed = Date().timeIntervalSince(startTime ?? Date())
            thinkingTime = elapsed
            stat = " 生成耗时: \(elapsed.formatted)"

            // Mark the thread's model
            thread.modelId = model.id

        } catch let error as InferenceError {
            lastError = error
            output = ""
        } catch {
            let inferenceError = InferenceError.inferenceFailed(error.localizedDescription)
            lastError = inferenceError
            output = ""
        }

        running = false
        return output
    }

    func stop() {
        isThinking = false
        cancelled = true
        running = false
        lastError = .cancelled
    }

    func unloadModel() {
        // TODO: verify with LiteRTLM-Swift docs - call engine.unload() when SPM is added
        // if let litertEngine = engine as? LiteRTLMEngine {
        //     litertEngine.unload()
        // }
        engine = nil
        loadedModelId = nil
        modelInfo = ""
    }

    /// Check if a model is currently loaded
    var isModelLoaded: Bool {
        return engine != nil && loadedModelId != nil
    }

    /// Currently loaded model ID
    var currentModelId: String? {
        return loadedModelId
    }

    // MARK: - Private Helpers

    private func modelFilePath(for model: NaviModel) -> String {
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsDir.appendingPathComponent(model.fileName).path
    }

    /// Convert message history to Gemma 4 turn marker format
    private func buildPromptFromHistory(_ history: [[String: String]]) -> String {
        var parts: [String] = []
        for msg in history {
            let role: String
            switch msg["role"] {
            case "assistant":
                role = "model"
            case "system":
                // Gemma doesn't have explicit system role, prepend to first user turn
                // For now, we include system as a user instruction
                role = "user"
            default:
                role = "user"
            }
            let content = msg["content"] ?? ""
            parts.append("<start_of_turn>\(role)\n\(content)\n<end_of_turn>")
        }
        // Add final model turn marker to prompt generation
        parts.append("<start_of_turn>model\n")
        return parts.joined(separator: "\n")
    }

    /// Streaming text inference using LiteRTLMEngine
    private func performStreamingInference(prompt: String) async throws -> String {
        guard engine != nil else {
            throw InferenceError.modelNotLoaded
        }

        var fullOutput = ""
        let throttler = StreamThrottler()

        // TODO: verify with LiteRTLM-Swift docs - uncomment when SPM dependency is added
        // let litertEngine = engine as! LiteRTLMEngine
        // let stream = litertEngine.generateStreaming(
        //     prompt: prompt,
        //     temperature: inferenceConfig.temperature,
        //     topK: inferenceConfig.topK,
        //     topP: inferenceConfig.topP,
        //     maxTokens: inferenceConfig.maxTokens,
        //     repeatPenalty: inferenceConfig.repeatPenalty
        // )
        // for try await chunk in stream {
        //     if cancelled { break }
        //     if let flushed = throttler.append(chunk) {
        //         fullOutput += flushed
        //         self.output = fullOutput
        //     }
        // }
        // if let remaining = throttler.flush() {
        //     fullOutput += remaining
        //     self.output = fullOutput
        // }

        // Placeholder: remove when SPM dependency is added
        fullOutput = "[LiteRT-LM inference output placeholder]"

        if cancelled {
            throw InferenceError.cancelled
        }

        return fullOutput
    }

    /// Vision (image understanding) inference using LiteRTLMEngine
    private func performVisionInference(prompt: String, imageData: Data) async throws -> String {
        guard engine != nil else {
            throw InferenceError.modelNotLoaded
        }

        // TODO: verify with LiteRTLM-Swift docs - uncomment when SPM dependency is added
        // let litertEngine = engine as! LiteRTLMEngine
        // let result = try await litertEngine.vision(
        //     imageData: imageData,
        //     prompt: prompt,
        //     temperature: inferenceConfig.temperature,
        //     maxTokens: inferenceConfig.maxTokens,
        //     maxImageDimension: NaviConfig.imageSize
        // )
        // return result

        // Placeholder: remove when SPM dependency is added
        return "[Vision inference output placeholder]"
    }
}
