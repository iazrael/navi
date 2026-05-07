//
//  ContextManager.swift
//  Navi
//
//  Lightweight context manager with sliding window strategy.
//  Self-implemented instead of using Swift Context Management package.
//

import Foundation

actor ContextManager {
    let maxContextTokens: Int
    private let maxTurns: Int

    init(maxContextTokens: Int = 3072, maxTurns: Int = 10) {
        self.maxContextTokens = maxContextTokens
        self.maxTurns = maxTurns
    }

    /// Build prompt history from Thread with sliding window truncation.
    /// - Parameters:
    ///   - thread: The conversation thread
    ///   - systemPrompt: System-level instruction
    /// - Returns: Array of [role, content] dictionaries
    func buildPromptHistory(
        thread: Thread,
        systemPrompt: String
    ) -> [[String: String]] {
        var history: [[String: String]] = []

        // 1. System prompt always first
        history.append(["role": "system", "content": systemPrompt])

        // 2. Sliding window: keep only the most recent N turns
        let messages = thread.sortedMessages
        let startIndex = max(0, messages.count - maxTurns)
        let recentMessages = Array(messages[startIndex...])

        // 3. If we truncated history, note it (future: insert compressed summary)
        // if startIndex > 0 { ... rolling summary ... }

        for message in recentMessages {
            let role = message.role.rawValue  // "user" / "assistant"
            var content = message.content

            // If message has image, add placeholder text
            if message.imageData != nil {
                content = "[用户发送了一张图片]\n\(content)"
            }

            history.append(["role": role, "content": content])
        }

        return history
    }

    /// Estimate token count (heuristic: Chinese ~1.5 chars/token, English ~4 chars/token)
    func estimateTokens(_ text: String) -> Int {
        let chineseCount = text.filter { $0.isChineseCharacter }.count
        let otherCount = text.count - chineseCount
        return Int(Double(chineseCount) / 1.5) + otherCount / 4
    }
}

// MARK: - Helper Extension

extension Character {
    var isChineseCharacter: Bool {
        guard let scalar = unicodeScalars.first else { return false }
        return (0x4E00...0x9FFF).contains(scalar.value)
    }
}
