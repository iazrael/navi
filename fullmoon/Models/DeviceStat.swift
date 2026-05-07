//
//  DeviceStat.swift
//  Navi
//
//  Based on fullmoon by Jordan Singer.
//  MLX GPU stats removed; provides device info stubs.
//

import Foundation
import SwiftUI

@Observable
final class DeviceStat: @unchecked Sendable {
    @MainActor
    var gpuActiveMemory: Int = 0
    
    init() {
        // No MLX GPU monitoring; placeholder for future Metal/Memory stats
    }
}
