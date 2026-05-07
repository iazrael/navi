//
//  NaviConfig.swift
//  Navi
//
//  Centralized configuration constants for Navi.
//  Extracts magic numbers from across the codebase into one place.
//

import Foundation

enum NaviConfig {
    // MARK: - Inference
    /// Maximum tokens to generate per response (overridden by InferenceConfig)
    static let maxTokens = 4096
    /// Sampling temperature for generation (overridden by InferenceConfig)
    static let temperature: Float = 0.7
    
    // MARK: - Context Management
    /// Maximum context tokens for sliding window
    static let maxContextTokens = 3072
    /// Maximum conversation turns to keep in context
    static let maxTurns = 10
    /// Default context strategy
    static let defaultContextStrategy: ContextStrategy = .slidingWindow
    
    // MARK: - Streaming
    /// Throttle interval for streaming UI updates (seconds)
    static let streamUpdateInterval: TimeInterval = 0.05
    /// Number of tokens to buffer before flushing to UI
    static let streamMaxBufferTokens = 4
    
    // MARK: - Image Processing
    /// Maximum image dimension for inference input
    static let imageSize: Int = 1024
    /// JPEG compression quality for inference
    static let inferenceCompressionQuality: CGFloat = 0.7
    /// Thumbnail size for storage in SwiftData
    static let thumbnailSize: Int = 200
    /// JPEG compression quality for thumbnail storage
    static let thumbnailCompressionQuality: CGFloat = 0.5
    
    // MARK: - Device Compatibility (Sprint 4.4)
    /// Minimum chip for recommended experience (A17 Pro = iPhone 15 Pro and above)
    static let minimumChipForRecommended = "A17 Pro"
    /// Minimum RAM for running models (in GB)
    static let minimumRAMGB: Double = 6.0
}
