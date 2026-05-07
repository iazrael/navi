//
//  ModelsSettingsView.swift
//  Navi
//
//  Based on fullmoon by Jordan Singer.
//  Modified for Navi - uses NaviModelRegistry, LiteRTInferenceService, and ModelDownloader.
//

import SwiftUI

struct ModelsSettingsView: View {
    @EnvironmentObject var appManager: AppManager
    @Environment(LiteRTInferenceService.self) var llm
    @State var showOnboardingInstallModelView = false
    @State var downloadingModel: NaviModel?
    @State var downloader = ModelDownloader()
    
    var body: some View {
        Form {
            Section(header: Text("installed")) {
                ForEach(appManager.installedModels, id: \.self) { modelName in
                    Button {
                        Task {
                            await switchModel(modelName)
                        }
                    } label: {
                        Label {
                            Text(appManager.modelDisplayName(modelName))
                                .tint(.primary)
                        } icon: {
                            Image(systemName: appManager.currentModelName == modelName ? "checkmark.circle.fill" : "circle")
                        }
                    }
                    #if os(macOS)
                    .buttonStyle(.borderless)
                    #endif
                }
            }
            
            if let model = downloadingModel, downloader.isDownloading {
                Section(header: Text("downloading")) {
                    VStack(spacing: 8) {
                        Text(model.displayName)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        ProgressView(value: downloader.downloadProgress, total: 1)
                            .progressViewStyle(.linear)
                        
                        HStack {
                            Text(String(format: "%.1f%%", downloader.downloadProgress * 100))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Cancel") {
                                downloader.cancel()
                                downloadingModel = nil
                            }
                            .foregroundStyle(.red)
                        }
                    }
                }
            }
            
            if let error = downloader.errorMessage {
                Section {
                    Text("Download failed: \(error)")
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
            
            Button {
                showOnboardingInstallModelView.toggle()
            } label: {
                Label("install a model", systemImage: "arrow.down.circle.dotted")
            }
            #if os(macOS)
            .buttonStyle(.borderless)
            #endif
        }
        .formStyle(.grouped)
        .navigationTitle("models")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(isPresented: $showOnboardingInstallModelView) {
            NavigationStack {
                OnboardingInstallModelView(showOnboarding: $showOnboardingInstallModelView)
                    .environment(llm)
                    .toolbar {
                        #if os(iOS) || os(visionOS)
                        ToolbarItem(placement: .topBarLeading) {
                            Button(action: { showOnboardingInstallModelView = false }) {
                                Image(systemName: "xmark")
                            }
                        }
                        #elseif os(macOS)
                        ToolbarItem(placement: .destructiveAction) {
                            Button(action: { showOnboardingInstallModelView = false }) {
                                Text("close")
                            }
                        }
                        #endif
                    }
            }
        }
    }
    
    private func switchModel(_ modelName: String) async {
        if let model = NaviModelRegistry.getModelById(modelName) {
            // Check if model file exists, download if needed
            if !downloader.isModelDownloaded(model) {
                downloadingModel = model
                do {
                    try await downloader.download(model: model)
                } catch {
                    downloadingModel = nil
                    return
                }
                downloadingModel = nil
            }
            
            appManager.currentModelName = modelName
            appManager.playHaptic()
            await llm.switchModel(model)
        }
    }
}

#Preview {
    ModelsSettingsView()
}
