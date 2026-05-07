//
//  StreamThrottlerTests.swift
//  fullmoonTests
//
//  Sprint 5.4: Tests for StreamThrottler - buffering and flushing logic.
//

import Testing
import Foundation
@testable import fullmoon

struct StreamThrottlerTests {
    
    @Test("Append returns nil when buffer is below threshold")
    func appendBelowThreshold() {
        let throttler = StreamThrottler(updateInterval: 999, maxBufferTokens: 4)
        
        let result = throttler.append("ab") // Only 2 chars, below 4
        #expect(result == nil)
    }
    
    @Test("Append returns flushed text when buffer exceeds threshold")
    func appendExceedsThreshold() {
        let throttler = StreamThrottler(updateInterval: 999, maxBufferTokens: 4)
        
        _ = throttler.append("ab") // 2 chars
        let result = throttler.append("cd") // 4 chars total, exceeds threshold
        #expect(result == "abcd")
    }
    
    @Test("Flush returns remaining buffer")
    func flushReturnsRemaining() {
        let throttler = StreamThrottler(updateInterval: 999, maxBufferTokens: 10)
        
        _ = throttler.append("hello")
        let flushed = throttler.flush()
        #expect(flushed == "hello")
    }
    
    @Test("Flush after threshold returns empty")
    func flushAfterThresholdReturnsEmpty() {
        let throttler = StreamThrottler(updateInterval: 999, maxBufferTokens: 3)
        
        let result = throttler.append("abc")
        #expect(result == "abc")
        
        let flushed = throttler.flush()
        #expect(flushed == "")
    }
    
    @Test("Multiple appends accumulate before threshold")
    func multipleAppends() {
        let throttler = StreamThrottler(updateInterval: 999, maxBufferTokens: 6)
        
        _ = throttler.append("a")
        _ = throttler.append("b")
        _ = throttler.append("c")
        let result = throttler.append("def") // 6 chars total
        #expect(result == "abcdef")
    }
    
    @Test("Time-based flush works")
    func timeBasedFlush() async {
        let throttler = StreamThrottler(updateInterval: 0.0, maxBufferTokens: 100)
        
        // With 0 interval, next append should flush immediately
        _ = throttler.append("hello")
        
        // Small delay to let time pass
        try? await Task.sleep(for: .milliseconds(10))
        
        let result = throttler.append(" world")
        #expect(result == "hello world")
    }
    
    @Test("Empty flush on new throttler")
    func emptyFlush() {
        let throttler = StreamThrottler()
        let flushed = throttler.flush()
        #expect(flushed == "")
    }
}
