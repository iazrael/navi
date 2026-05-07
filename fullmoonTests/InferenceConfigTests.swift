//
//  InferenceConfigTests.swift
//  fullmoonTests
//
//  Sprint 5.4: Tests for InferenceConfig - defaults, persistence, validation.
//

import Testing
import Foundation
@testable import fullmoon

struct InferenceConfigTests {
    
    @Test("Default config has expected values")
    func defaultConfig() {
        let config = InferenceConfig.default
        #expect(config.temperature == 0.7)
        #expect(config.topK == 40)
        #expect(config.topP == 0.9)
        #expect(config.maxTokens == 4096)
        #expect(config.repeatPenalty == 1.1)
    }
    
    @Test("Default config is valid")
    func defaultConfigIsValid() {
        #expect(InferenceConfig.default.isValid)
    }
    
    @Test("Save and load round-trip")
    func saveAndLoad() {
        let original = InferenceConfig(temperature: 0.5, topK: 20, topP: 0.8, maxTokens: 2048, repeatPenalty: 1.2)
        original.save()
        
        let loaded = InferenceConfig.load()
        #expect(loaded == original)
        
        // Clean up
        InferenceConfig.default.save()
    }
    
    @Test("Invalid temperature detected")
    func invalidTemperature() {
        let config = InferenceConfig(temperature: -1, topK: 40, topP: 0.9, maxTokens: 4096, repeatPenalty: 1.1)
        #expect(!config.isValid)
    }
    
    @Test("Invalid topK detected")
    func invalidTopK() {
        let config = InferenceConfig(temperature: 0.7, topK: 0, topP: 0.9, maxTokens: 4096, repeatPenalty: 1.1)
        #expect(!config.isValid)
    }
    
    @Test("Invalid topP detected")
    func invalidTopP() {
        let config = InferenceConfig(temperature: 0.7, topK: 40, topP: 0, maxTokens: 4096, repeatPenalty: 1.1)
        #expect(!config.isValid)
    }
    
    @Test("Invalid maxTokens detected")
    func invalidMaxTokens() {
        let config = InferenceConfig(temperature: 0.7, topK: 40, topP: 0.9, maxTokens: 0, repeatPenalty: 1.1)
        #expect(!config.isValid)
    }
    
    @Test("Reset returns defaults")
    func resetReturnsDefaults() {
        let reset = InferenceConfig.reset()
        #expect(reset == InferenceConfig.default)
    }
    
    @Test("Boundary values are valid")
    func boundaryValues() {
        let minConfig = InferenceConfig(temperature: 0, topK: 1, topP: 0.01, maxTokens: 1, repeatPenalty: 1.0)
        #expect(minConfig.isValid)
        
        let maxConfig = InferenceConfig(temperature: 2.0, topK: 100, topP: 1.0, maxTokens: 8192, repeatPenalty: 2.0)
        #expect(maxConfig.isValid)
    }
}
