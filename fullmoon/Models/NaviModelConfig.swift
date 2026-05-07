//
//  NaviModelConfig.swift
//  Navi
//
//  Model registry for Navi. Replaces fullmoon's MLX-based ModelConfiguration.
//  Sprint 5.1: Added multi-model support with device recommendations.
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
    
    /// Device recommendation
    let recommendedDevice: String
    /// Estimated speed range
    let estimatedSpeed: String
    /// Minimum RAM required in GB
    let minRAMGB: Double
    
    /// Size in GB for display
    var sizeGB: String {
        String(format: "%.1f", Double(sizeMB) / 1024.0)
    }
    
    /// Approximate size as Decimal (for compatibility with old code)
    var modelSize: Decimal {
        Decimal(sizeMB) / 1024
    }
    
    /// Whether this model is suitable for the current device
    var isSuitableForDevice: Bool {
        let deviceRAM = ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024)
        return Double(deviceRAM) >= minRAMGB
    }
}

struct NaviModelRegistry {
    static let models: [NaviModel] = [
        NaviModel(
            id: "gemma-4-e2b-it",
            displayName: "Gemma 4 E2B IT",
            fileName: "gemma-4-E2B-it.litertlm",
            sizeMB: 2583,
            isMultimodal: true,
            downloadURL: "https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm",
            recommended: true,
            backend: "litert-lm",
            description: "2.3B 参数，支持图片输入，最佳质量",
            recommendedDevice: "iPhone 15 Pro 及以上",
            estimatedSpeed: "~50 tok/s",
            minRAMGB: 6.0
        ),
        NaviModel(
            id: "gemma-3-4b-it",
            displayName: "Gemma 3 4B IT",
            fileName: "gemma-3-4b-it.litertlm",
            sizeMB: 2000,
            isMultimodal: true,
            downloadURL: "https://huggingface.co/litert-community/gemma-3-4b-it-litert-lm/resolve/main/gemma-3-4b-it.litertlm",
            recommended: false,
            backend: "litert-lm",
            description: "4B 参数，平衡性能和质量，支持图片输入",
            recommendedDevice: "iPhone 15 Pro 及以上",
            estimatedSpeed: "~30 tok/s",
            minRAMGB: 6.0
        ),
        NaviModel(
            id: "gemma-3-1b-it",
            displayName: "Gemma 3 1B IT",
            fileName: "gemma-3-1b-it.litertlm",
            sizeMB: 550,
            isMultimodal: false,
            downloadURL: "https://huggingface.co/litert-community/gemma-3-1b-it-litert-lm/resolve/main/gemma-3-1b-it.litertlm",
            recommended: false,
            backend: "litert-lm",
            description: "1B 参数，适合低内存设备，仅文本",
            recommendedDevice: "所有 iPhone 15 及以上",
            estimatedSpeed: "~80 tok/s",
            minRAMGB: 4.0
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
    
    /// Models suitable for the current device
    static var suitableModels: [NaviModel] {
        models.filter { $0.isSuitableForDevice }
    }
}
