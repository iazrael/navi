//
//  StreamThrottler.swift
//  Navi
//
//  Throttles streaming output to avoid excessive UI updates per token.
//

import Foundation

/// Throttles streaming token output to reduce UI update frequency.
actor StreamThrottler {
    private var buffer = ""
    private var lastUpdateTime: Date = .distantPast
    private let updateInterval: TimeInterval
    private let maxBufferTokens: Int

    init(updateInterval: TimeInterval = 0.05, maxBufferTokens: Int = 4) {
        self.updateInterval = updateInterval
        self.maxBufferTokens = maxBufferTokens
    }

    /// Append a token chunk. Returns flushed text if threshold reached, nil otherwise.
    func append(_ token: String) -> String? {
        buffer += token
        let now = Date()

        if buffer.count >= maxBufferTokens || now.timeIntervalSince(lastUpdateTime) >= updateInterval {
            let result = buffer
            buffer = ""
            lastUpdateTime = now
            return result
        }
        return nil
    }

    /// Flush any remaining buffered content
    func flush() -> String {
        let result = buffer
        buffer = ""
        return result
    }
}
