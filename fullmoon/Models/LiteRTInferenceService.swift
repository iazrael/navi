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

    // --- Configuration ---
    var maxTokens: Int { NaviConfig.maxTokens }
    private let displayEveryNTokens = 4
    private let contextManager = ContextManager(maxContextTokens: NaviConfig.maxContextTokens)

    enum InferenceError: Error {
        case modelNotLoaded
        case engineBusy
        case modelFileNotFound
        case loadFailed(String)
        case inferenceFailed(String)
    }

    // MARK: - Model Loading

    func load(modelName: String) async throws {
        guard let model = NaviModelRegistry.getModelById(modelName) else {
            throw InferenceError.modelFileNotFound
        }
        try await loadModel(model)
    }

    func switchModel(_ model: NaviModel) async {
        progress = 0.0
        do {
            try await loadModel(model)
        } catch {
            modelInfo = "Failed to load model: \(error.localizedDescription)"
        }
    }

    private func loadModel(_ model: NaviModel) async throws {
        // Skip if already loaded
        if loadedModelId == model.id { return }

        let filePath = modelFilePath(for: model)

        // Check if model file exists
        if !FileManager.default.fileExists(atPath: filePath) {
            throw InferenceError.modelFileNotFound
        }

        // Unload previous engine
        unloadModel()

        progress = 0.2

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
        startTime = Date()

        do {
            let model = NaviModelRegistry.getModelById(modelName) ?? NaviModelRegistry.defaultModel
            try await loadModel(model)

            // Build prompt history with context management
            let history = contextManager.buildPromptHistory(
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

        } catch {
            output = "推理失败: \(error.localizedDescription)"
        }

        running = false
        return output
    }

    func stop() {
        isThinking = false
        cancelled = true
        running = false
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
        //     temperature: 0.7,
        //     maxTokens: maxTokens
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
        //     temperature: 0.7,
        //     maxTokens: maxTokens,
        //     maxImageDimension: NaviConfig.imageSize
        // )
        // return result

        // Placeholder: remove when SPM dependency is added
        return "[Vision inference output placeholder]"
    }
}
