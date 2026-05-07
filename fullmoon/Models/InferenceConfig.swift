//
//  InferenceConfig.swift
//  Navi
//
//  Sprint 5.3: Configurable inference parameters.
//  Persisted to UserDefaults, passed to LiteRTInferenceService.
//

import Foundation

struct InferenceConfig: Codable, Equatable {
    /// Sampling temperature (0.0 = deterministic, 1.0 = creative)
    var temperature: Float
    
    /// Top-K sampling: only consider top K most likely tokens
    var topK: Int
    
    /// Top-P (nucleus) sampling: cumulative probability threshold
    var topP: Float
    
    /// Maximum tokens to generate per response
    var maxTokens: Int
    
    /// Penalty for repeating tokens (1.0 = no penalty, >1.0 = more penalty)
    var repeatPenalty: Float

    static let `default` = InferenceConfig(
        temperature: 0.7,
        topK: 40,
        topP: 0.9,
        maxTokens: 4096,
        repeatPenalty: 1.1
    )

    // MARK: - Persistence

    private static let storageKey = "inferenceConfig"

    static func load() -> InferenceConfig {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let config = try? JSONDecoder().decode(InferenceConfig.self, from: data) else {
            return .default
        }
        return config
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    // MARK: - Validation

    var isValid: Bool {
        temperature >= 0 && temperature <= 2.0 &&
        topK > 0 && topK <= 100 &&
        topP > 0 && topP <= 1.0 &&
        maxTokens > 0 && maxTokens <= 8192 &&
        repeatPenalty >= 1.0 && repeatPenalty <= 2.0
    }

    /// Reset to defaults
    static func reset() -> InferenceConfig {
        let config = `default`
        config.save()
        return config
    }
}
