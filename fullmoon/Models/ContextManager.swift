//
//  ContextManager.swift
//  Navi
//
//  Lightweight context manager with sliding window and rolling summary strategies.
//  Self-implemented instead of using Swift Context Management package.
//  Sprint 5.2: Added RollingSummary strategy and ContextStrategy enum.
//

import Foundation

/// Strategy for managing conversation context
enum ContextStrategy: String, CaseIterable, Codable {
    case slidingWindow = "sliding_window"
    case rollingSummary = "rolling_summary"
    
    var displayName: String {
        switch self {
        case .slidingWindow: return "滑动窗口"
        case .rollingSummary: return "滚动摘要"
        }
    }
    
    var description: String {
        switch self {
        case .slidingWindow: return "保留最近 N 轮对话，丢弃更早的内容"
        case .rollingSummary: return "将早期对话压缩为摘要，保留更多上下文信息"
        }
    }
}

final class ContextManager {
    let maxContextTokens: Int
    let maxTurns: Int
    let strategy: ContextStrategy

    init(
        maxContextTokens: Int = NaviConfig.maxContextTokens,
        maxTurns: Int = NaviConfig.maxTurns,
        strategy: ContextStrategy = NaviConfig.defaultContextStrategy
    ) {
        self.maxContextTokens = maxContextTokens
        self.maxTurns = maxTurns
        self.strategy = strategy
    }

    /// Build prompt history from Thread with the configured strategy.
    /// - Parameters:
    ///   - thread: The conversation thread
    ///   - systemPrompt: System-level instruction
    /// - Returns: Array of [role, content] dictionaries
    func buildPromptHistory(
        thread: Thread,
        systemPrompt: String
    ) async -> [[String: String]] {
        switch strategy {
        case .slidingWindow:
            return buildSlidingWindowHistory(thread: thread, systemPrompt: systemPrompt)
        case .rollingSummary:
            return await buildRollingSummaryHistory(thread: thread, systemPrompt: systemPrompt)
        }
    }

    // MARK: - Sliding Window Strategy

    private func buildSlidingWindowHistory(
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

    // MARK: - Rolling Summary Strategy (Sprint 5.2)

    private func buildRollingSummaryHistory(
        thread: Thread,
        systemPrompt: String
    ) async -> [[String: String]] {
        var history: [[String: String]] = []

        // 1. System prompt always first
        history.append(["role": "system", "content": systemPrompt])

        let messages = thread.sortedMessages

        // If within window, just include all messages
        if messages.count <= maxTurns {
            for message in messages {
                let role = message.role.rawValue
                var content = message.content
                if message.imageData != nil {
                    content = "[用户发送了一张图片]\n\(content)"
                }
                history.append(["role": role, "content": content])
            }
            return history
        }

        // 2. Compress older messages into a summary
        let olderMessages = Array(messages[..<messages.count - maxTurns])
        let recentMessages = Array(messages[messages.count - maxTurns...])

        // Generate rolling summary from older messages
        let summary = generateRollingSummary(olderMessages)
        history.append(["role": "system", "content": summary])

        // 3. Add recent messages
        for message in recentMessages {
            let role = message.role.rawValue
            var content = message.content
            if message.imageData != nil {
                content = "[用户发送了一张图片]\n\(content)"
            }
            history.append(["role": role, "content": content])
        }

        return history
    }

    /// Generate a compressed summary from older messages.
    /// Uses a deterministic format that preserves key information without requiring LLM inference.
    private func generateRollingSummary(_ messages: [Message]) -> String {
        var summaryParts: [String] = []

        // Group messages into pairs (user + assistant)
        var index = 0
        while index < messages.count {
            let msg = messages[index]

            if msg.role == .user {
                var userContent = msg.content
                // Truncate long messages
                if userContent.count > 100 {
                    userContent = String(userContent.prefix(100)) + "..."
                }

                // Look for the following assistant response
                if index + 1 < messages.count && messages[index + 1].role == .assistant {
                    var assistantContent = messages[index + 1].content
                    if assistantContent.count > 100 {
                        assistantContent = String(assistantContent.prefix(100)) + "..."
                    }
                    summaryParts.append("用户询问了「\(userContent)」，AI回答了「\(assistantContent)」")
                    index += 2
                } else {
                    summaryParts.append("用户询问了「\(userContent)」")
                    index += 1
                }
            } else {
                index += 1
            }
        }

        if summaryParts.isEmpty {
            return "[之前的对话摘要：无重要内容]"
        }

        // Limit summary length
        let fullSummary = summaryParts.joined(separator: "；")
        if fullSummary.count > 500 {
            return "[之前的对话摘要：\(String(fullSummary.prefix(500)))...]"
        }
        return "[之前的对话摘要：\(fullSummary)]"
    }

    // MARK: - Token Estimation

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
