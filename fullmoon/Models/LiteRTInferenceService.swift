//
//  LiteRTInferenceService.swift
//  Navi
//
//  Replaces fullmoon's LLMEvaluator with LiteRT-LM based inference.
//  Maintains the same @Observable @MainActor interface for minimal View-layer changes.
//

import Foundation
import SwiftUI

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
    // TODO: 真机验证 - Replace with actual LiteRTLMEngine once SPM dependency is resolved
    // private var engine: LiteRTLMEngine?
    private var loadedModelId: String?

    // --- Configuration ---
    let maxTokens = 4096
    private let displayEveryNTokens = 4
    private let contextManager = ContextManager(maxContextTokens: 3072)

    enum InferenceError: Error {
        case modelNotLoaded
        case engineBusy
        case modelFileNotFound
        case loadFailed(String)
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

        // TODO: 真机验证 - Actual engine initialization
        // engine = try await LiteRTLMEngine(path: filePath)
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
            let history = await contextManager.buildPromptHistory(
                thread: thread,
                systemPrompt: systemPrompt
            )
            let promptText = buildPromptFromHistory(history)

            // TODO: 真机验证 - Actual inference with LiteRTLMEngine
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
        // engine = nil
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

    // TODO: 真机验证 - Implement with actual LiteRTLMEngine streaming API
    private func performStreamingInference(prompt: String) async throws -> String {
        // Placeholder: simulates streaming behavior
        // Real implementation:
        //   var tokenCount = 0
        //   var fullOutput = ""
        //   let throttler = StreamThrottler()
        //   for try await chunk in engine.generateStreaming(prompt: prompt) {
        //       if cancelled { break }
        //       tokenCount += 1
        //       if let text = await throttler.append(chunk) {
        //           fullOutput += text
        //           self.output = fullOutput
        //       }
        //   }
        //   if let remaining = await throttler.flush() {
        //       fullOutput += remaining
        //       self.output = fullOutput
        //   }
        //   return fullOutput

        // Mock implementation for compilation
        return "[LiteRT-LM inference output placeholder]"
    }

    // TODO: 真机验证 - Implement with actual LiteRTLMEngine vision API
    private func performVisionInference(prompt: String, imageData: Data) async throws -> String {
        // Real implementation:
        //   let result = try await engine.vision(
        //       imageData: imageData,
        //       prompt: prompt,
        //       maxTokens: maxTokens
        //   )
        //   return result

        // Mock implementation for compilation
        return "[Vision inference output placeholder]"
    }
}
