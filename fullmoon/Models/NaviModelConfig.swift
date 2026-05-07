//
//  NaviModelConfig.swift
//  Navi
//
//  Model registry for Navi. Replaces fullmoon's MLX-based ModelConfiguration.
//

import Foundation

struct NaviModel: Identifiable, Codable, Equatable {
    let id: String
    let displayName: String
    let fileName: String
    let sizeMB: Int
    let isMultimodal: Bool
    let downloadURL: String
    let recommended: Bool
    let backend: String
    let description: String
    
    /// Size in GB for display
    var sizeGB: String {
        String(format: "%.1f", Double(sizeMB) / 1024.0)
    }
    
    /// Approximate size as Decimal (for compatibility with old code)
    var modelSize: Decimal {
        Decimal(sizeMB) / 1024
    }
}

struct NaviModelRegistry {
    static let models: [NaviModel] = [
        NaviModel(
            id: "gemma-4-e2b-it",
            displayName: "Gemma 4 E2B IT（推荐）",
            fileName: "gemma-4-E2B-it.litertlm",
            sizeMB: 2583,
            isMultimodal: true,
            downloadURL: "https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm",
            recommended: true,
            backend: "litert-lm",
            description: "2.3B 参数，GPU backend ~50 tok/s，支持图片输入"
        )
    ]
    
    static var defaultModel: NaviModel {
        models.first { $0.recommended }!
    }
    
    static func getModelById(_ id: String) -> NaviModel? {
        models.first { $0.id == id }
    }
    
    static var availableModels: [NaviModel] {
        models
    }
}
