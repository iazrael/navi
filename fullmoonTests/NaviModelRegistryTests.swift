//
//  NaviModelRegistryTests.swift
//  fullmoonTests
//
//  Sprint 5.4: Tests for NaviModelRegistry - model lookup, defaults.
//

import Testing
import Foundation
@testable import fullmoon

struct NaviModelRegistryTests {
    
    @Test("Default model is Gemma 4 E2B IT")
    func defaultModel() {
        let model = NaviModelRegistry.defaultModel
        #expect(model.id == "gemma-4-e2b-it")
        #expect(model.recommended == true)
        #expect(model.isMultimodal == true)
    }
    
    @Test("Get model by ID returns correct model")
    func getModelById() {
        let model = NaviModelRegistry.getModelById("gemma-3-1b-it")
        #expect(model != nil)
        #expect(model?.displayName == "Gemma 3 1B IT")
        #expect(model?.isMultimodal == false)
        #expect(model?.sizeMB == 550)
    }
    
    @Test("Get model by unknown ID returns nil")
    func getUnknownModel() {
        let model = NaviModelRegistry.getModelById("nonexistent-model")
        #expect(model == nil)
    }
    
    @Test("Available models contains all registered models")
    func availableModels() {
        let models = NaviModelRegistry.availableModels
        #expect(models.count >= 3)
        #expect(models.contains { $0.id == "gemma-4-e2b-it" })
        #expect(models.contains { $0.id == "gemma-3-4b-it" })
        #expect(models.contains { $0.id == "gemma-3-1b-it" })
    }
    
    @Test("Model size formatting")
    func modelSizeFormatting() {
        let model = NaviModelRegistry.defaultModel
        // 2583 MB ≈ 2.5 GB
        #expect(model.sizeGB == "2.5")
    }
    
    @Test("Only one model is recommended")
    func singleRecommendedModel() {
        let recommended = NaviModelRegistry.models.filter { $0.recommended }
        #expect(recommended.count == 1)
        #expect(recommended.first?.id == "gemma-4-e2b-it")
    }
    
    @Test("All models have valid download URLs")
    func validDownloadURLs() {
        for model in NaviModelRegistry.models {
            #expect(!model.downloadURL.isEmpty)
            #expect(model.downloadURL.hasPrefix("https://"))
            #expect(!model.fileName.isEmpty)
            #expect(model.sizeMB > 0)
        }
    }
}
