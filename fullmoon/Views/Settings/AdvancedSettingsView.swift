//
//  AdvancedSettingsView.swift
//  Navi
//
//  Sprint 5.3: Advanced inference parameter settings.
//  Exposes temperature, topK, topP, maxTokens, repeatPenalty.
//

import SwiftUI

struct AdvancedSettingsView: View {
    @Environment(LiteRTInferenceService.self) var llm
    @EnvironmentObject var appManager: AppManager
    @State private var config: InferenceConfig = InferenceConfig.load()
    @State private var contextStrategy: ContextStrategy = .slidingWindow

    var body: some View {
        Form {
            // MARK: - Context Strategy
            Section(header: Text("上下文策略")) {
                Picker("策略", selection: $contextStrategy) {
                    ForEach(ContextStrategy.allCases, id: \.self) { strategy in
                        VStack(alignment: .leading) {
                            Text(strategy.displayName)
                                .font(.body)
                            Text(strategy.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(strategy)
                    }
                }
                .pickerStyle(.inline)
            }

            // MARK: - Sampling Parameters
            Section(header: Text("采样参数")) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Temperature")
                        Spacer()
                        Text(String(format: "%.2f", config.temperature))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $config.temperature, in: 0...2.0, step: 0.05) {
                        Text("Temperature")
                    }
                    Text("越低越确定，越高越有创意")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Top-K")
                        Spacer()
                        Text("\(config.topK)")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: Binding(
                        get: { Double(config.topK) },
                        set: { config.topK = Int($0) }
                    ), in: 1...100, step: 1) {
                        Text("Top-K")
                    }
                    Text("只考虑概率最高的 K 个 token")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Top-P")
                        Spacer()
                        Text(String(format: "%.2f", config.topP))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $config.topP, in: 0.01...1.0, step: 0.05) {
                        Text("Top-P")
                    }
                    Text("核采样：累积概率阈值")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            // MARK: - Generation Parameters
            Section(header: Text("生成参数")) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("最大 Token 数")
                        Spacer()
                        Text("\(config.maxTokens)")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: Binding(
                        get: { Double(config.maxTokens) },
                        set: { config.maxTokens = Int($0) }
                    ), in: 256...8192, step: 256) {
                        Text("最大 Token 数")
                    }
                    Text("每次回复生成的最大 token 数量")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("重复惩罚")
                        Spacer()
                        Text(String(format: "%.2f", config.repeatPenalty))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $config.repeatPenalty, in: 1.0...2.0, step: 0.05) {
                        Text("重复惩罚")
                    }
                    Text("越高越不容易重复，1.0 = 无惩罚")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            // MARK: - Reset
            Section {
                Button("恢复默认设置") {
                    config = InferenceConfig.reset()
                    contextStrategy = NaviConfig.defaultContextStrategy
                }
                .foregroundStyle(.red)
                #if os(macOS)
                .buttonStyle(.borderless)
                #endif
            }
        }
        .formStyle(.grouped)
        .navigationTitle("高级设置")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onChange(of: config) { _, newConfig in
            newConfig.save()
            llm.inferenceConfig = newConfig
        }
        .onChange(of: contextStrategy) { _, newStrategy in
            UserDefaults.standard.set(newStrategy.rawValue, forKey: "contextStrategy")
        }
        .onAppear {
            if let saved = UserDefaults.standard.string(forKey: "contextStrategy"),
               let strategy = ContextStrategy(rawValue: saved) {
                contextStrategy = strategy
            }
        }
    }
}

#Preview {
    AdvancedSettingsView()
        .environmentObject(AppManager())
        .environment(LiteRTInferenceService())
}
