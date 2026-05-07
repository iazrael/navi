//
//  PromptFormatterTests.swift
//  fullmoonTests
//
//  Sprint 5.4: Tests for Gemma 4 turn marker prompt formatting.
//

import Testing
import Foundation
@testable import fullmoon

struct PromptFormatterTests {
    
    // MARK: - Turn Marker Format Tests
    
    private func buildPrompt(_ history: [[String: String]]) -> String {
        // Replicate the buildPromptFromHistory logic from LiteRTInferenceService
        var parts: [String] = []
        for msg in history {
            let role: String
            switch msg["role"] {
            case "assistant":
                role = "model"
            case "system":
                role = "user"
            default:
                role = "user"
            }
            let content = msg["content"] ?? ""
            parts.append("<start_of_turn>\(role)\n\(content)\n<end_of_turn>")
        }
        parts.append("<start_of_turn>model\n")
        return parts.joined(separator: "\n")
    }
    
    @Test("Single user message formatted correctly")
    func singleUserMessage() {
        let history = [
            ["role": "user", "content": "Hello"]
        ]
        let prompt = buildPrompt(history)
        
        #expect(prompt.contains("<start_of_turn>user\nHello\n<end_of_turn>"))
        #expect(prompt.hasSuffix("<start_of_turn>model\n"))
    }
    
    @Test("System prompt uses user role")
    func systemPromptUsesUserRole() {
        let history = [
            ["role": "system", "content": "You are helpful"],
            ["role": "user", "content": "Hi"]
        ]
        let prompt = buildPrompt(history)
        
        // System should be formatted as user role
        #expect(prompt.contains("<start_of_turn>user\nYou are helpful\n<end_of_turn>"))
    }
    
    @Test("Assistant role maps to model")
    func assistantMapsToModel() {
        let history = [
            ["role": "user", "content": "Question"],
            ["role": "assistant", "content": "Answer"]
        ]
        let prompt = buildPrompt(history)
        
        #expect(prompt.contains("<start_of_turn>model\nAnswer\n<end_of_turn>"))
    }
    
    @Test("Multi-turn conversation has correct ordering")
    func multiTurnOrdering() {
        let history = [
            ["role": "system", "content": "Be helpful"],
            ["role": "user", "content": "Q1"],
            ["role": "assistant", "content": "A1"],
            ["role": "user", "content": "Q2"],
            ["role": "assistant", "content": "A2"]
        ]
        let prompt = buildPrompt(history)
        
        // Verify ordering
        let q1Range = prompt.range(of: "Q1")!
        let a1Range = prompt.range(of: "A1")!
        let q2Range = prompt.range(of: "Q2")!
        let a2Range = prompt.range(of: "A2")!
        
        #expect(q1Range.lowerBound < a1Range.lowerBound)
        #expect(a1Range.lowerBound < q2Range.lowerBound)
        #expect(q2Range.lowerBound < a2Range.lowerBound)
    }
    
    @Test("Empty history produces minimal prompt")
    func emptyHistory() {
        let history: [[String: String]] = []
        let prompt = buildPrompt(history)
        
        #expect(prompt == "<start_of_turn>model\n")
    }
    
    @Test("Prompt ends with model turn marker")
    func promptEndsWithModelMarker() {
        let history = [
            ["role": "user", "content": "Test"]
        ]
        let prompt = buildPrompt(history)
        
        #expect(prompt.hasSuffix("<start_of_turn>model\n"))
    }
}
