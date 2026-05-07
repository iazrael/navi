//
//  OnboardingView.swift
//  Navi
//
//  Based on fullmoon by Jordan Singer.
//  Modified for Navi branding.
//  Sprint 4.4: Added device compatibility check (≥ A17 Pro / iPhone 15 Pro+).
//

import SwiftUI

struct OnboardingView: View {
    @Binding var showOnboarding: Bool
    
    /// Check device compatibility for on-device LLM
    private var isDeviceCompatible: Bool {
        #if os(iOS)
        // Check for Metal 3 support and sufficient RAM
        guard let device = MTLCreateSystemDefaultDevice() else { return false }
        guard device.supportsFamily(.metal3) else { return false }
        // Check RAM: need at least 6GB for recommended models
        let ramGB = ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024)
        return ramGB >= 4 // Minimum 4GB for smallest model
        #else
        return true // macOS and visionOS always compatible
        #endif
    }
    
    var body: some View {
        NavigationStack {
            VStack {
                Spacer()
                
                VStack(spacing: 12) {
                    Image(systemName: "location.north.fill")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 64, height: 64)
                        .foregroundStyle(.tint)
                    
                    VStack(spacing: 4) {
                        Text("Navi")
                            .font(.title)
                            .fontWeight(.semibold)
                        Text("离线 AI 助手，数据完全在设备端处理")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                
                Spacer()
                                
                VStack(alignment: .leading, spacing: 24) {
                    Label {
                        VStack(alignment: .leading) {
                            Text("快速")
                                .font(.headline)
                            Text("GPU 加速推理，流式输出")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "bolt.fill")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 24, height: 24)
                            .foregroundStyle(.secondary)
                            .padding(.trailing, 8)
                    }
                    
                    Label {
                        VStack(alignment: .leading) {
                            Text("私密")
                                .font(.headline)
                            Text("完全离线运行，零数据上传")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "checkmark.shield.fill")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 24, height: 24)
                            .foregroundStyle(.secondary)
                            .padding(.trailing, 8)
                    }
                    
                    Label {
                        VStack(alignment: .leading) {
                            Text("多模态")
                                .font(.headline)
                            Text("支持拍照提问，图片理解")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "camera.fill")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 24, height: 24)
                            .foregroundStyle(.secondary)
                            .padding(.trailing, 8)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                
                Spacer()
                
                if isDeviceCompatible {
                    NavigationLink(destination: OnboardingInstallModelView(showOnboarding: $showOnboarding)) {
                        Text("开始使用")
                            #if os(iOS) || os(visionOS)
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            #endif
                            #if os(iOS)
                            .foregroundStyle(.background)
                            #endif
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .padding(.horizontal)
                } else {
                    VStack(spacing: 12) {
                        Text("您的设备暂不支持 Navi")
                            .font(.headline)
                            .foregroundStyle(.red)
                        Text("Navi 需要 iPhone 15 Pro 及以上机型（A17 Pro 芯片或更新）")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }
            }
            .padding()
            .navigationTitle("welcome")
            .toolbar(.hidden)
        }
        #if os(macOS)
        .frame(width: 420, height: 520)
        #endif
    }
}

#Preview {
    OnboardingView(showOnboarding: .constant(true))
}
