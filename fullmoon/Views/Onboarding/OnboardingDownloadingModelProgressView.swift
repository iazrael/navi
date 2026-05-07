//
//  OnboardingDownloadingModelProgressView.swift
//  Navi
//
//  Based on fullmoon by Jordan Singer.
//  Modified for Navi - downloads model using ModelDownloader, then loads via LiteRTInferenceService.
//

import SwiftUI

struct OnboardingDownloadingModelProgressView: View {
    @Binding var showOnboarding: Bool
    @EnvironmentObject var appManager: AppManager
    @Binding var selectedModel: NaviModel
    @Environment(LiteRTInferenceService.self) var llm
    @State var didSwitchModel = false
    @State var downloader = ModelDownloader()
    
    var installed: Bool {
        llm.progress == 1 && didSwitchModel
    }
    
    var body: some View {
        VStack {
            Spacer()
            
            VStack(spacing: 16) {
                MoonAnimationView(isDone: installed)
                
                VStack(spacing: 4) {
                    Text(installed ? "installed" : "installing")
                        .font(.title)
                        .fontWeight(.semibold)
                    Text(selectedModel.displayName)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                
                if downloader.isDownloading {
                    ProgressView(value: downloader.downloadProgress, total: 1)
                        .progressViewStyle(.linear)
                        .padding(.horizontal, 48)
                    
                    Text(String(format: "%.1f%%", downloader.downloadProgress * 100))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView(value: llm.progress, total: 1)
                        .progressViewStyle(.linear)
                        .padding(.horizontal, 48)
                }
            }
            
            Spacer()
            
            if installed {
                Button(action: { showOnboarding = false }) {
                    Text("done")
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
            } else if let error = downloader.errorMessage {
                VStack(spacing: 12) {
                    Text("Download failed: \(error)")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    Button("Retry") {
                        Task { await downloadAndLoadModel() }
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal)
            } else {
                Text("keep this screen open and wait for the installation to complete.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
        .padding()
        .navigationTitle("sit back and relax")
        .toolbar(installed ? .hidden : .visible)
        .navigationBarBackButtonHidden()
        .task {
            await downloadAndLoadModel()
        }
        #if os(iOS)
        .sensoryFeedback(.success, trigger: installed)
        #endif
        .onChange(of: installed) {
            #if os(iOS)
            UIApplication.shared.isIdleTimerDisabled = false
            #endif
            addInstalledModel()
        }
        .interactiveDismissDisabled(!installed)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
        #endif
    }
    
    func downloadAndLoadModel() async {
        // Step 1: Download model file (if not already downloaded)
        if !downloader.isModelDownloaded(selectedModel) {
            do {
                try await downloader.download(model: selectedModel)
            } catch {
                // Error is displayed via downloader.errorMessage
                return
            }
        }
        
        // Step 2: Load model into inference engine
        await llm.switchModel(selectedModel)
        didSwitchModel = true
    }
    
    func addInstalledModel() {
        if installed {
            print("added installed model")
            appManager.currentModelName = selectedModel.id
            appManager.addInstalledModel(selectedModel.id)
        }
    }
}

#Preview {
    OnboardingDownloadingModelProgressView(
        showOnboarding: .constant(true),
        selectedModel: .constant(NaviModelRegistry.defaultModel)
    )
    .environmentObject(AppManager())
    .environment(LiteRTInferenceService())
}
