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
    /// Maximum tokens to generate per response
    static let maxTokens = 4096
    /// Sampling temperature for generation
    static let temperature: Float = 0.7
    
    // MARK: - Context Management
    /// Maximum context tokens for sliding window
    static let maxContextTokens = 3072
    /// Maximum conversation turns to keep in context
    static let maxTurns = 10
    
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
}
