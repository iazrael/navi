//
//  OnboardingDownloadingModelProgressView.swift
//  Navi
//
//  Based on fullmoon by Jordan Singer.
//  Modified for Navi - uses NaviModel and LiteRTInferenceService.
//

import SwiftUI

struct OnboardingDownloadingModelProgressView: View {
    @Binding var showOnboarding: Bool
    @EnvironmentObject var appManager: AppManager
    @Binding var selectedModel: NaviModel
    @Environment(LiteRTInferenceService.self) var llm
    @State var didSwitchModel = false
    
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
                
                ProgressView(value: llm.progress, total: 1)
                    .progressViewStyle(.linear)
                    .padding(.horizontal, 48)
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
            await loadModel()
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
    
    func loadModel() async {
        // TODO: 真机验证 - Download model from downloadURL, then load
        // For now, attempt to load (will succeed if model file already exists)
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
