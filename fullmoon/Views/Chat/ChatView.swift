//
//  ChatView.swift
//  Navi
//
//  Based on fullmoon by Jordan Singer.
//  Modified for Navi - uses LiteRTInferenceService, adds image picker support.
//  Sprint 5.5: Added error state UI, long-press copy/delete.
//

import MarkdownUI
import PhotosUI
import SwiftUI

struct ChatView: View {
    @EnvironmentObject var appManager: AppManager
    @Environment(\.modelContext) var modelContext
    @Binding var currentThread: Thread?
    @Environment(LiteRTInferenceService.self) var llm
    @Namespace var bottomID
    @State var showModelPicker = false
    @State var prompt = ""
    @FocusState.Binding var isPromptFocused: Bool
    @Binding var showChats: Bool
    @Binding var showSettings: Bool
    
    @State var thinkingTime: TimeInterval?
    @State private var generatingThreadID: UUID?

    // Image picker state
    @State private var selectedImage: UIImage?
    @State private var photoPickerItem: PhotosPickerItem?

    // Error state (Sprint 5.5)
    @State private var showError = false

    var isPromptEmpty: Bool {
        prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && selectedImage == nil
    }

    let platformBackgroundColor: Color = {
        #if os(iOS)
        return Color(UIColor.secondarySystemBackground)
        #elseif os(visionOS)
        return Color(UIColor.separator)
        #elseif os(macOS)
        return Color(NSColor.secondarySystemFill)
        #endif
    }()

    var chatInput: some View {
        VStack(spacing: 0) {
            // Image preview above input
            if selectedImage != nil {
                ImagePreviewView(selectedImage: $selectedImage, onRemove: {})
            }

            HStack(alignment: .bottom, spacing: 0) {
                // Photo picker button
                PhotosPicker(selection: $photoPickerItem, matching: .images) {
                    Image(systemName: "photo.on.rectangle")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        #if os(iOS) || os(visionOS)
                        .frame(width: 20, height: 20)
                        #else
                        .frame(width: 16, height: 16)
                        #endif
                        .tint(.secondary)
                }
                #if os(iOS) || os(visionOS)
                .padding(.leading, 12)
                .padding(.bottom, 12)
                #else
                .padding(.leading, 8)
                .padding(.bottom, 8)
                #endif
                #if os(macOS) || os(visionOS)
                .buttonStyle(.plain)
                #endif

                TextField("message", text: $prompt, axis: .vertical)
                    .focused($isPromptFocused)
                    .textFieldStyle(.plain)
                #if os(iOS) || os(visionOS)
                    .padding(.horizontal, 16)
                #elseif os(macOS)
                    .padding(.horizontal, 12)
                    .onSubmit {
                        handleShiftReturn()
                    }
                    .submitLabel(.send)
                #endif
                    .padding(.vertical, 8)
                #if os(iOS) || os(visionOS)
                    .frame(minHeight: 48)
                #elseif os(macOS)
                    .frame(minHeight: 32)
                #endif
                #if os(iOS)
                .onSubmit {
                    isPromptFocused = true
                    generate()
                }
                #endif

                if llm.running {
                    stopButton
                } else {
                    generateButton
                }
            }
        }
        #if os(iOS) || os(visionOS)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(platformBackgroundColor)
        )
        #elseif os(macOS)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(platformBackgroundColor)
        )
        #endif
        .onChange(of: photoPickerItem) { _, newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    selectedImage = image
                }
            }
        }
    }

    var modelPickerButton: some View {
        Button {
            appManager.playHaptic()
            showModelPicker.toggle()
        } label: {
            Group {
                Image(systemName: "chevron.up")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                #if os(iOS) || os(visionOS)
                    .frame(width: 16)
                #elseif os(macOS)
                    .frame(width: 12)
                #endif
                    .tint(.primary)
            }
            #if os(iOS) || os(visionOS)
            .frame(width: 48, height: 48)
            #elseif os(macOS)
            .frame(width: 32, height: 32)
            #endif
            .background(
                Circle()
                    .fill(platformBackgroundColor)
            )
        }
        #if os(macOS) || os(visionOS)
        .buttonStyle(.plain)
        #endif
    }

    var generateButton: some View {
        Button {
            generate()
        } label: {
            Image(systemName: "arrow.up.circle.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
            #if os(iOS) || os(visionOS)
                .frame(width: 24, height: 24)
            #else
                .frame(width: 16, height: 16)
            #endif
        }
        .disabled(isPromptEmpty)
        #if os(iOS) || os(visionOS)
            .padding(.trailing, 12)
            .padding(.bottom, 12)
        #else
            .padding(.trailing, 8)
            .padding(.bottom, 8)
        #endif
        #if os(macOS) || os(visionOS)
        .buttonStyle(.plain)
        #endif
    }

    var stopButton: some View {
        Button {
            llm.stop()
        } label: {
            Image(systemName: "stop.circle.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
            #if os(iOS) || os(visionOS)
                .frame(width: 24, height: 24)
            #else
                .frame(width: 16, height: 16)
            #endif
        }
        .disabled(llm.cancelled)
        #if os(iOS) || os(visionOS)
            .padding(.trailing, 12)
            .padding(.bottom, 12)
        #else
            .padding(.trailing, 8)
            .padding(.bottom, 8)
        #endif
        #if os(macOS) || os(visionOS)
        .buttonStyle(.plain)
        #endif
    }

    // MARK: - Error Banner (Sprint 5.5)

    @ViewBuilder
    var errorBanner: some View {
        if let error = llm.lastError {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text(error.localizedDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                Spacer()

                if error.shouldShowRetry {
                    Button("重试") {
                        retryLastGeneration()
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                }

                if error.shouldShowModelManagement {
                    Button("模型管理") {
                        showModelPicker = true
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.red.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal)
        }
    }

    var chatTitle: String {
        if let currentThread = currentThread {
            if let firstMessage = currentThread.sortedMessages.first {
                return firstMessage.content
            }
        }
        return "Navi"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let currentThread = currentThread {
                    ConversationView(thread: currentThread, generatingThreadID: generatingThreadID)
                } else {
                    Spacer()
                    Image(systemName: appManager.getMoonPhaseIcon())
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 32, height: 32)
                        .foregroundStyle(.quaternary)
                    Spacer()
                }

                // Error banner above input
                errorBanner

                HStack(alignment: .bottom) {
                    modelPickerButton
                    chatInput
                }
                .padding()
            }
            .navigationTitle(chatTitle)
            #if os(iOS) || os(visionOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .sheet(isPresented: $showModelPicker) {
                    NavigationStack {
                        ModelsSettingsView()
                            .environment(llm)
                        #if os(visionOS)
                            .toolbar {
                                ToolbarItem(placement: .topBarLeading) {
                                    Button(action: { showModelPicker.toggle() }) {
                                        Image(systemName: "xmark")
                                    }
                                }
                            }
                        #endif
                    }
                    #if os(iOS)
                    .presentationDragIndicator(.visible)
                    .if(appManager.userInterfaceIdiom == .phone) { view in
                        view.presentationDetents([.fraction(0.4)])
                    }
                    #elseif os(macOS)
                    .toolbar {
                        ToolbarItem(placement: .destructiveAction) {
                            Button(action: { showModelPicker.toggle() }) {
                                Text("close")
                            }
                        }
                    }
                    #endif
                }
                .toolbar {
                    #if os(iOS) || os(visionOS)
                    if appManager.userInterfaceIdiom == .phone {
                        ToolbarItem(placement: .topBarLeading) {
                            Button(action: {
                                appManager.playHaptic()
                                showChats.toggle()
                            }) {
                                Image(systemName: "list.bullet")
                            }
                        }
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: {
                            appManager.playHaptic()
                            showSettings.toggle()
                        }) {
                            Image(systemName: "gear")
                        }
                    }
                    #elseif os(macOS)
                    ToolbarItem(placement: .primaryAction) {
                        Button(action: {
                            appManager.playHaptic()
                            showSettings.toggle()
                        }) {
                            Label("settings", systemImage: "gear")
                        }
                    }
                    #endif
                }
        }
    }

    private func generate() {
        if !isPromptEmpty {
            if currentThread == nil {
                let newThread = Thread()
                currentThread = newThread
                modelContext.insert(newThread)
                try? modelContext.save()
            }

            if let currentThread = currentThread {
                generatingThreadID = currentThread.id
                Task {
                    let messageText = prompt
                    let imageData = selectedImage.flatMap { ImageCompressor.compressForThumbnail($0) }
                    prompt = ""
                    let pickedImage = selectedImage
                    selectedImage = nil
                    photoPickerItem = nil
                    appManager.playHaptic()
                    
                    // User message with optional image
                    sendMessage(Message(
                        role: .user,
                        content: messageText,
                        thread: currentThread,
                        imageData: imageData
                    ))
                    isPromptFocused = true
                    
                    if let modelName = appManager.currentModelName {
                        // Pass inference-quality image data (higher res)
                        let inferenceImageData = pickedImage.flatMap { ImageCompressor.compressForInference($0) }
                        let output = await llm.generate(
                            modelName: modelName,
                            thread: currentThread,
                            systemPrompt: appManager.systemPrompt,
                            imageData: inferenceImageData
                        )
                        let wasCancelled = llm.cancelled
                        let assistantMsg = Message(
                            role: .assistant,
                            content: output,
                            thread: currentThread,
                            generatingTime: llm.thinkingTime
                        )
                        assistantMsg.isComplete = !wasCancelled
                        sendMessage(assistantMsg)
                        generatingThreadID = nil
                    }
                }
            }
        }
    }

    /// Retry the last generation after an error
    private func retryLastGeneration() {
        guard let currentThread = currentThread,
              let lastUserMessage = currentThread.sortedMessages.last(where: { $0.role == .user }),
              let modelName = appManager.currentModelName else {
            return
        }

        generatingThreadID = currentThread.id
        Task {
            let output = await llm.generate(
                modelName: modelName,
                thread: currentThread,
                systemPrompt: appManager.systemPrompt
            )
            let assistantMsg = Message(
                role: .assistant,
                content: output,
                thread: currentThread,
                generatingTime: llm.thinkingTime
            )
            sendMessage(assistantMsg)
            generatingThreadID = nil
        }
    }

    private func sendMessage(_ message: Message) {
        appManager.playHaptic()
        modelContext.insert(message)
        try? modelContext.save()
    }

    #if os(macOS)
    private func handleShiftReturn() {
        if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
            prompt.append("\n")
            isPromptFocused = true
        } else {
            generate()
        }
    }
    #endif
}

#Preview {
    @FocusState var isPromptFocused: Bool
    ChatView(currentThread: .constant(nil), isPromptFocused: $isPromptFocused, showChats: .constant(false), showSettings: .constant(false))
}
