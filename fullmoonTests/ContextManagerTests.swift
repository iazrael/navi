//
//  ContextManagerTests.swift
//  fullmoonTests
//
//  Sprint 5.4: Tests for ContextManager - sliding window, rolling summary, empty history.
//

import Testing
import Foundation
@testable import fullmoon

@MainActor
struct ContextManagerTests {
    
    // MARK: - Helper
    
    private func makeThread(withMessages messages: [(role: Role, content: String)]) -> Thread {
        let thread = Thread()
        for (role, content) in messages {
            let msg = Message(role: role, content: content, thread: thread)
            thread.messages.append(msg)
        }
        return thread
    }
    
    // MARK: - Sliding Window Tests
    
    @Test("Sliding window keeps system prompt")
    func slidingWindowKeepsSystemPrompt() async {
        let manager = ContextManager(maxTurns: 5, strategy: .slidingWindow)
        let thread = makeThread(withMessages: [
            (.user, "Hello"),
            (.assistant, "Hi there!")
        ])
        
        let history = await manager.buildPromptHistory(thread: thread, systemPrompt: "You are helpful")
        
        #expect(history.first?["role"] == "system")
        #expect(history.first?["content"] == "You are helpful")
    }
    
    @Test("Sliding window truncates old messages")
    func slidingWindowTruncatesOldMessages() async {
        let manager = ContextManager(maxTurns: 3, strategy: .slidingWindow)
        
        // Create 10 messages (5 turns)
        var messages: [(role: Role, content: String)] = []
        for i in 1...10 {
            let role: Role = i % 2 == 1 ? .user : .assistant
            messages.append((role, "Message \(i)"))
        }
        let thread = makeThread(withMessages: messages)
        
        let history = await manager.buildPromptHistory(thread: thread, systemPrompt: "test")
        
        // System prompt + 3 most recent turns = 1 + 6 = 7 entries
        // (maxTurns=3 means 3 pairs = 6 messages)
        #expect(history.count == 7) // system + 6 recent messages
        #expect(history[1]["content"] == "Message 5") // First kept message
    }
    
    @Test("Sliding window handles empty history")
    func slidingWindowEmptyHistory() async {
        let manager = ContextManager(maxTurns: 5, strategy: .slidingWindow)
        let thread = Thread()
        
        let history = await manager.buildPromptHistory(thread: thread, systemPrompt: "test")
        
        // Only system prompt
        #expect(history.count == 1)
        #expect(history.first?["role"] == "system")
    }
    
    @Test("Sliding window keeps all messages within limit")
    func slidingWindowKeepsAllWithinLimit() async {
        let manager = ContextManager(maxTurns: 10, strategy: .slidingWindow)
        let thread = makeThread(withMessages: [
            (.user, "Q1"),
            (.assistant, "A1"),
            (.user, "Q2"),
            (.assistant, "A2")
        ])
        
        let history = await manager.buildPromptHistory(thread: thread, systemPrompt: "test")
        
        #expect(history.count == 5) // system + 4 messages
    }
    
    // MARK: - Rolling Summary Tests
    
    @Test("Rolling summary adds summary for old messages")
    func rollingSummaryCompressesOldMessages() async {
        let manager = ContextManager(maxTurns: 2, strategy: .rollingSummary)
        
        // 6 messages = 3 turns, window keeps 2 turns = 4 messages
        let thread = makeThread(withMessages: [
            (.user, "What is Swift?"),
            (.assistant, "Swift is a programming language"),
            (.user, "Tell me more"),
            (.assistant, "It was created by Apple"),
            (.user, "Latest question"),
            (.assistant, "Latest answer")
        ])
        
        let history = await manager.buildPromptHistory(thread: thread, systemPrompt: "test")
        
        // system + summary + 4 recent messages = 6
        #expect(history.count >= 3) // At minimum system + summary + some messages
        #expect(history.first?["role"] == "system")
        
        // Check that there's a summary message containing the old content
        let summaryMessages = history.filter { $0["content"]?.contains("之前的对话摘要") == true }
        #expect(summaryMessages.count == 1)
    }
    
    @Test("Rolling summary no compression when within window")
    func rollingSummaryNoCompressionWithinWindow() async {
        let manager = ContextManager(maxTurns: 10, strategy: .rollingSummary)
        let thread = makeThread(withMessages: [
            (.user, "Q1"),
            (.assistant, "A1")
        ])
        
        let history = await manager.buildPromptHistory(thread: thread, systemPrompt: "test")
        
        // No summary should be generated
        let summaryMessages = history.filter { $0["content"]?.contains("之前的对话摘要") == true }
        #expect(summaryMessages.isEmpty)
        #expect(history.count == 3) // system + 2 messages
    }
    
    @Test("Rolling summary handles empty history")
    func rollingSummaryEmptyHistory() async {
        let manager = ContextManager(maxTurns: 5, strategy: .rollingSummary)
        let thread = Thread()
        
        let history = await manager.buildPromptHistory(thread: thread, systemPrompt: "test")
        
        #expect(history.count == 1)
        #expect(history.first?["role"] == "system")
    }
    
    // MARK: - Token Estimation
    
    @Test("Token estimation for English text")
    func tokenEstimationEnglish() {
        let manager = ContextManager()
        let tokens = manager.estimateTokens("Hello world this is a test")
        // ~4 chars/token for English = 27/4 ≈ 6
        #expect(tokens > 0)
        #expect(tokens < 20)
    }
    
    @Test("Token estimation for Chinese text")
    func tokenEstimationChinese() {
        let manager = ContextManager()
        let tokens = manager.estimateTokens("你好世界这是一个测试")
        // ~1.5 chars/token for Chinese = 10/1.5 ≈ 6
        #expect(tokens > 0)
        #expect(tokens < 15)
    }
}
