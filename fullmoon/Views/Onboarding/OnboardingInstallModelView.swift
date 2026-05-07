//
//  OnboardingInstallModelView.swift
//  Navi
//
//  Based on fullmoon by Jordan Singer.
//  Modified for Navi - uses NaviModelRegistry instead of MLX ModelConfiguration.
//  Sprint 5.1: Shows all available models with device recommendations and metadata.
//

import os
import SwiftUI

struct OnboardingInstallModelView: View {
    @EnvironmentObject var appManager: AppManager
    @State private var deviceSupportsMetal3: Bool = true
    @Binding var showOnboarding: Bool
    @State var selectedModel = NaviModelRegistry.defaultModel
    let suggestedModel = NaviModelRegistry.defaultModel

    func sizeBadge(_ model: NaviModel?) -> String? {
        guard let model = model else { return nil }
        return model.sizeGB + " GB"
    }

    /// Maximum model size as fraction of device RAM
    let modelMemoryThreshold = 0.6

    var modelsList: some View {
        Form {
            Section {
                VStack(spacing: 12) {
                    Image(systemName: "arrow.down.circle.dotted")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 64, height: 64)
                        .foregroundStyle(.primary, .tertiary)

                    VStack(spacing: 4) {
                        Text("install a model")
                            .font(.title)
                            .fontWeight(.semibold)
                        Text("select from models optimized for on-device inference")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        #if DEBUG
                        Text("ram: \(appManager.availableMemory) GB")
                            .foregroundStyle(.red)
                        #endif
                    }
                }
                .padding(.vertical)
                .frame(maxWidth: .infinity)
            }
            .listRowBackground(Color.clear)

            if appManager.installedModels.count > 0 {
                Section(header: Text("installed")) {
                    ForEach(appManager.installedModels, id: \.self) { modelName in
                        Button {} label: {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(appManager.modelDisplayName(modelName))
                                    if let model = NaviModelRegistry.getModelById(modelName) {
                                        modelMetadata(model)
                                    }
                                }
                                .tint(.primary)
                            } icon: {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                        .badge(sizeBadge(NaviModelRegistry.getModelById(modelName)))
                        #if os(macOS)
                            .buttonStyle(.borderless)
                        #endif
                            .foregroundStyle(.secondary)
                            .disabled(true)
                    }
                }
            } else {
                Section(header: Text("suggested")) {
                    Button { selectedModel = suggestedModel } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(suggestedModel.displayName)
                                    .tint(.primary)
                                modelMetadata(suggestedModel)
                            }
                        } icon: {
                            Image(systemName: selectedModel.id == suggestedModel.id ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selectedModel.id == suggestedModel.id ? .green : .secondary)
                        }
                    }
                    .badge(sizeBadge(suggestedModel))
                    #if os(macOS)
                        .buttonStyle(.borderless)
                    #endif
                }
            }

            if filteredModels.count > 0 {
                Section(header: Text("other")) {
                    ForEach(filteredModels) { model in
                        Button { selectedModel = model } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(model.displayName)
                                        .tint(.primary)
                                    modelMetadata(model)
                                }
                            } icon: {
                                Image(systemName: selectedModel.id == model.id ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedModel.id == model.id ? .green : .secondary)
                            }
                        }
                        .badge(sizeBadge(model))
                        #if os(macOS)
                            .buttonStyle(.borderless)
                        #endif
                    }
                }
            }

            #if os(macOS)
            Section {} footer: {
                NavigationLink(destination: OnboardingDownloadingModelProgressView(showOnboarding: $showOnboarding, selectedModel: $selectedModel)) {
                    Text("install")
                        .buttonStyle(.borderedProminent)
                }
                .disabled(filteredModels.isEmpty)
            }
            .padding()
            #endif
        }
        .formStyle(.grouped)
    }

    /// Model metadata view: vision support, speed, recommended device
    @ViewBuilder
    private func modelMetadata(_ model: NaviModel) -> some View {
        HStack(spacing: 8) {
            if model.isMultimodal {
                Label("Vision", systemImage: "eye")
                    .font(.caption2)
            }
            Label(model.estimatedSpeed, systemImage: "gauge.with.dots.needle.33percent")
                .font(.caption2)
            Label(model.recommendedDevice, systemImage: "iphone")
                .font(.caption2)
        }
        .foregroundStyle(.tertiary)
    }

    var body: some View {
        ZStack {
            if deviceSupportsMetal3 {
                modelsList
                #if os(iOS) || os(visionOS)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink(destination: OnboardingDownloadingModelProgressView(showOnboarding: $showOnboarding, selectedModel: $selectedModel)) {
                            Text("install")
                                .font(.headline)
                        }
                        .disabled(filteredModels.isEmpty)
                    }
                }
                .listStyle(.insetGrouped)
                #endif
                .task {
                    checkModels()
                }
            } else {
                DeviceNotSupportedView()
            }
        }
        .onAppear {
            checkMetal3Support()
        }
    }

    var filteredModels: [NaviModel] {
        NaviModelRegistry.availableModels
            .filter { !appManager.installedModels.contains($0.id) }
            .filter { model in
                !(appManager.installedModels.isEmpty && model.id == suggestedModel.id)
            }
            .filter { model in
                return model.modelSize <= Decimal(modelMemoryThreshold * appManager.availableMemory)
            }
            .sorted { $0.sizeMB < $1.sizeMB }
    }

    func checkModels() {
        if appManager.installedModels.contains(suggestedModel.id) {
            if let model = filteredModels.first {
                selectedModel = model
            }
        }
    }

    func checkMetal3Support() {
        #if os(iOS)
        if let device = MTLCreateSystemDefaultDevice() {
            deviceSupportsMetal3 = device.supportsFamily(.metal3)
        }
        #endif
    }
}

#Preview {
    @Previewable @State var appManager = AppManager()

    OnboardingInstallModelView(showOnboarding: .constant(true))
        .environmentObject(appManager)
}
