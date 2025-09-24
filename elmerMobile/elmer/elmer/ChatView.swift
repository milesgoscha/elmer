//
//  ChatView.swift
//  elmer iOS
//
//  Chat interface using CloudKit relay system
//

import SwiftUI
import Combine
import PhotosUI

struct ChatView: View {
    let service: RemoteService
    
    @EnvironmentObject var serviceStore: ServiceStore
    @EnvironmentObject internal var conversationManager: ConversationManager
    @EnvironmentObject internal var cloudKitConversationManager: CloudKitConversationManager
    @State internal var currentConversation: Conversation?
    @State internal var messageText: String = ""
    @State internal var isLoading: Bool = false
    @State internal var errorMessage: String?
    @State private var showingModelPicker: Bool = false
    @State internal var selectedModel: AIModel?
    @State private var showingSidebar: Bool = false
    @State private var keyboardHeight: CGFloat = 0
    
    // Image picker state
    @State internal var showingImagePicker: Bool = false
    @State internal var selectedImageItem: PhotosPickerItem? = nil
    @State internal var selectedImage: UIImage? = nil
    @State internal var selectedImageData: Data? = nil
    
    // Available models for this service
    @State private var availableModels: [AIModel] = []
    @State private var isLoadingModels = false
    
    internal var apiClient: SecureAPIClient {
        serviceStore.createAPIClient(for: service)
    }
    
    var body: some View {
        ZStack {
            // Full background that extends everywhere
            ElmeriOSTheme.backgroundColor
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Messages Area
                messagesView

                // Input Area
                chatInput
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(false)
        .onChange(of: selectedImageItem) { _, _ in
            loadSelectedImage()
        }
        .onChange(of: cloudKitConversationManager.conversations) { _, newConversations in
            // If current conversation was updated in CloudKit, refresh it but preserve local messages
            if let updatedConversation = newConversations.first(where: { $0.id == currentConversation?.id }) {
                // Only update if CloudKit has more messages (indicating sync completed)
                // This prevents losing local messages that haven't been synced yet
                if updatedConversation.messages.count >= (currentConversation?.messages.count ?? 0) {
                    currentConversation = updatedConversation
                }
            } else if currentConversation != nil && !newConversations.contains(where: { $0.id == currentConversation?.id }) {
                // Current conversation was deleted
                currentConversation = nil
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Button(action: {
                    if !availableModels.isEmpty {
                        showingModelPicker = true
                    }
                }) {
                    HStack(spacing: 3) {
                        LoadingTextView(
                            text: service.name,
                            isLoading: isLoadingModels && availableModels.isEmpty,
                            font: .system(size: 15, weight: .medium),
                            baseColor: ElmeriOSTheme.textTertiary,
                            fillColor: ElmeriOSTheme.textColor
                        )
                        
                        if let modelName = selectedModel?.name {
                            Text(modelName)
                                .font(.system(size: 15, weight: .regular))
                                .foregroundColor(ElmeriOSTheme.textSecondary)
                                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                        }
                        
                        if !availableModels.isEmpty && !isLoadingModels {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(ElmeriOSTheme.textTertiary)
                                .padding(.leading, 2)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(isLoadingModels || availableModels.isEmpty)
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showingSidebar = true }) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(ElmeriOSTheme.textSecondary)
                }
            }
        }
        .sheet(isPresented: $showingModelPicker) {
            ThemedModelPicker(
                models: availableModels,
                selectedModel: $selectedModel,
                isPresented: $showingModelPicker
            )
        }
        .sheet(isPresented: $showingSidebar) {
            ConversationSidebar(
                service: service,
                selectedConversation: $currentConversation,
                isPresented: $showingSidebar
            )
        }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .onAppear {
            setupInitialState()
        }
        .onDisappear {
            saveCurrentConversation()
        }
    }
    
    // MARK: - Messages View
    
    private var messagesView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    if let conversation = currentConversation {
                        ForEach(conversation.messages) { message in
                            // Use ThinkingMessageView for assistant messages that might have thinking
                            // Use regular MultimodalMessageView for user messages
                            if message.role == .assistant {
                                ThinkingMessageView(message: message)
                                    .id(message.id)
                            } else {
                                MultimodalMessageView(message: message)
                                    .id(message.id)
                            }
                        }
                    } else {
                        // Welcome message for new chat
                        welcomeMessage
                    }
                    
                    // Loading indicator
                    if isLoading {
                        ThemedLoadingBubble()
                            .id("loading")
                        
                        // Invisible spacer for scroll anchor that respects padding
                        Color.clear
                            .frame(height: 1)
                            .id("loadingBottom")
                    }
                    
                    // Error message
                    if let errorMessage = errorMessage {
                        errorBubble(errorMessage)
                    }
                }
                .padding(.vertical, 12)
            }
            .onChange(of: currentConversation?.messages.count) {
                // Scroll to bottom when new message added
                DispatchQueue.main.async {
                    withAnimation(.easeOut(duration: 0.2)) {
                        if let lastMessage = currentConversation?.messages.last {
                            proxy.scrollTo(lastMessage.id, anchor: UnitPoint.bottom)
                        } else if isLoading {
                            proxy.scrollTo("loadingBottom", anchor: UnitPoint.bottom)
                        }
                    }
                }
            }
            .onChange(of: currentConversation?.id) {
                // Scroll to bottom when conversation changes (e.g., from sidebar)
                DispatchQueue.main.async {
                    withAnimation(.easeOut(duration: 0.2)) {
                        if let lastMessage = currentConversation?.messages.last {
                            proxy.scrollTo(lastMessage.id, anchor: UnitPoint.bottom)
                        } else if isLoading {
                            proxy.scrollTo("loadingBottom", anchor: UnitPoint.bottom)
                        }
                    }
                }
            }
            .onChange(of: isLoading) { _, newValue in
                // Scroll to loading indicator when it appears, without animation to avoid conflicts
                if newValue {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        proxy.scrollTo("loadingBottom", anchor: UnitPoint.bottom)
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
                // Scroll to bottom when keyboard appears
                if let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                    keyboardHeight = keyboardFrame.height
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation(.easeOut(duration: 0.2)) {
                            if let lastMessage = currentConversation?.messages.last {
                                proxy.scrollTo(lastMessage.id, anchor: UnitPoint.bottom)
                            } else if isLoading {
                                proxy.scrollTo("loadingBottom", anchor: UnitPoint.bottom)
                            }
                        }
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                keyboardHeight = 0
            }
        }
    }
    
    private var welcomeMessage: some View {
        VStack(spacing: 16) {
            Image(systemName: service.type.icon)
                .font(.system(size: 48, weight: .regular))
                .foregroundColor(ElmeriOSTheme.textTertiary)
            
            VStack(spacing: 8) {
                Text("Start a conversation")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(ElmeriOSTheme.textColor)
                
                Text("Connected to \(service.name) via CloudKit relay.\nYour messages are encrypted end-to-end.")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(ElmeriOSTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .padding(.horizontal, 40)
            }
        }
        .padding(.top, 48)
    }
    
    private func errorBubble(_ message: String) -> some View {
        HStack {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(ElmeriOSTheme.errorColor)
                
                Text(message)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(ElmeriOSTheme.textColor)
                
                Spacer()
                
                Button("Retry") {
                    Task { await sendMessage() }
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(ElmeriOSTheme.accentColor)
            }
            .padding(14)
            .background(ElmeriOSTheme.errorColor.opacity(0.1))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(ElmeriOSTheme.errorColor.opacity(0.3), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
            
            Spacer(minLength: 60)
        }
    }
    
    // MARK: - Chat Input
    
    private var chatInput: some View {
        VStack(spacing: 0) {
            // Show image generation input for image services, regular chat input for others
            if service.baseService.type == .imageGeneration || service.baseService.apiFormat == .comfyui {
                imageGenerationInput
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            } else {
                VStack(spacing: 0) {
                    // Show selected image preview if present
                    selectedImagePreview
                    
                    ThemedChatInput(
                        text: $messageText,
                        onSend: {
                            if selectedImage != nil {
                                Task { await sendMessageWithImage() }
                            } else {
                                Task { await sendMessage() }
                            }
                        },
                        isLoading: isLoading,
                        canSend: serviceStore.getConnectionStatus(for: service) == .connected,
                        leadingContent: {
                            imagePickerButton
                        }
                    )
                }
            }
        }
    }
    
    // MARK: - Setup and Actions
    
    private func setupInitialState() {
        print("📱 ChatView: Using service \(service.name) with ID: \(service.id.uuidString)")
        
        // Start with empty models array and loading state
        availableModels = []
        selectedModel = nil
        isLoadingModels = true
        
        // Try to load most recent conversation for this service from CloudKit
        currentConversation = nil
        
        // Load from CloudKit cache first
        cloudKitConversationManager.loadFromCache()
        
        // Try to find the most recent conversation for this service from CloudKit
        let serviceConversations = cloudKitConversationManager.conversations
            .filter { $0.serviceName == service.name }
            .sorted { $0.updatedAt > $1.updatedAt }
        
        if let mostRecentConversation = serviceConversations.first {
            currentConversation = mostRecentConversation
            print("📚 Loaded existing conversation: \(mostRecentConversation.id) with \(mostRecentConversation.messages.count) messages")
        }
        
        // Fetch real models from the service immediately
        Task {
            // Wait a moment for CloudKit connection to be fully established
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            await fetchRealModels()
            
            // Also refresh CloudKit conversations and try to find matching one
            cloudKitConversationManager.fetchRecentConversations()
            
            // Wait a bit for CloudKit to fetch
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            
            await MainActor.run {
                // If we don't have a conversation yet, try to find one from CloudKit
                if currentConversation == nil || currentConversation?.messages.isEmpty == true {
                    let serviceConversations = cloudKitConversationManager.conversations
                        .filter { $0.serviceName == service.name }
                        .sorted { $0.updatedAt > $1.updatedAt }
                    
                    if let mostRecentConversation = serviceConversations.first {
                        currentConversation = mostRecentConversation
                        print("📚 Loaded CloudKit conversation: \(mostRecentConversation.id) with \(mostRecentConversation.messages.count) messages")
                        
                        // If messages are empty, fetch them
                        if mostRecentConversation.messages.isEmpty {
                            Task {
                                await cloudKitConversationManager.fetchMessages(for: mostRecentConversation)
                            }
                        }
                    }
                }
            }
        }
    }
    
    @MainActor
    private func fetchRealModels() async {
        isLoadingModels = true
        
        // Try up to 3 times with increasing delays
        for attempt in 1...3 {
            do {
                let realModels = try await apiClient.fetchAvailableModels()
                if !realModels.isEmpty {
                    availableModels = realModels
                    // Set the first model if we don't have one selected, or update if current selection is invalid
                    if selectedModel == nil {
                        selectedModel = realModels.first
                    } else if let currentModel = selectedModel,
                       !realModels.contains(where: { $0.id == currentModel.id }) {
                        selectedModel = realModels.first
                    }
                    print("✅ Fetched \(realModels.count) models from service \(service.name)")
                    isLoadingModels = false
                    return
                }
            } catch {
                print("⚠️ Attempt \(attempt): Failed to fetch models - \(error.localizedDescription)")
                if attempt < 3 {
                    // Wait before retrying (1s, 2s)
                    try? await Task.sleep(nanoseconds: UInt64(attempt) * 1_000_000_000)
                }
            }
        }
        
        print("❌ Failed to fetch models after 3 attempts")
        // If we completely fail to get models, create a simple fallback
        availableModels = [AIModel(id: "default", name: "Default Model", description: "Service default")]
        selectedModel = availableModels.first
        isLoadingModels = false
    }
    
    
    @MainActor
    private func sendMessage() async {
        guard !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard serviceStore.getConnectionStatus(for: service) == .connected else {
            errorMessage = "Not connected to service. Please check your connection."
            return
        }
        
        let userMessageText = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        messageText = ""
        isLoading = true
        errorMessage = nil
        
        // Create or get current conversation
        if currentConversation == nil {
            // Create in CloudKit (this creates the conversation locally and saves to CloudKit)
            currentConversation = cloudKitConversationManager.createConversation(
                serviceID: service.id.uuidString,
                serviceName: service.name
            )
            
            // Also create in old manager for backward compatibility
            let _ = conversationManager.createConversation(
                serviceName: service.name,
                modelName: selectedModel?.id
            )
        }
        
        // Add user message
        let userMessage = ChatMessage(role: .user, content: userMessageText)
        currentConversation?.messages.append(userMessage)
        conversationManager.updateConversation(currentConversation!)
        
        do {
            // Prepare messages for API
            let messages = currentConversation?.messages.map { message in
                [
                    "role": message.role.rawValue,
                    "content": message.content
                ]
            } ?? []
            
            // Try to send with tools if the model supports them
            let modelId = selectedModel?.id ?? "default"
            
            // First try with tools (the API will check if model supports them)
            let response = try await apiClient.sendChatMessage(
                messages: messages,
                model: modelId,
                tools: [], // Tools are now handled by Mac app via UserToolManager
                toolChoice: "auto"
            )
            
            // Add assistant response
            let assistantMessage = ChatMessage(role: .assistant, content: response)
            currentConversation?.messages.append(assistantMessage)
            conversationManager.updateConversation(currentConversation!)
            
            // Save both messages to CloudKit
            if let conversation = currentConversation {
                Task {
                    // Save user message
                    if let userMsg = conversation.messages.dropLast().last {
                        try? await cloudKitConversationManager.addMessage(to: conversation, message: userMsg)
                    }
                    // Save assistant message
                    try? await cloudKitConversationManager.addMessage(to: conversation, message: assistantMessage)
                }
            }
            
        } catch {
            errorMessage = "Failed to send message: \(error.localizedDescription)"
            print("❌ Chat error: \(error)")
        }
        
        isLoading = false
    }
    
    // MARK: - Tool Call Processing
    
    private func processAssistantResponse(_ response: [String: Any]) async throws -> String {
        guard let choices = response["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any] else {
            throw APIError.invalidResponse
        }
        
        // No client-side tool execution needed - Mac handles all tool calls
        // Just return the content from the assistant response
        if let content = message["content"] as? String {
            return content.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            throw APIError.invalidResponse
        }
    }
    
    private func saveCurrentConversation() {
        guard let conversation = currentConversation else { return }
        conversationManager.updateConversation(conversation)
    }
}

// MARK: - Loading Text View

struct LoadingTextView: View {
    let text: String
    let isLoading: Bool
    let font: Font
    let baseColor: Color
    let fillColor: Color
    
    @State private var animationProgress: CGFloat = 0
    
    init(text: String, isLoading: Bool, 
         font: Font = .system(size: 15, weight: .medium),
         baseColor: Color = GeistIOSTheme.textTertiary,
         fillColor: Color = GeistIOSTheme.textColor) {
        self.text = text
        self.isLoading = isLoading
        self.font = font
        self.baseColor = baseColor
        self.fillColor = fillColor
    }
    
    var body: some View {
        Text(text)
            .font(font)
            .foregroundColor(isLoading ? baseColor : fillColor)
            .overlay(
                GeometryReader { geometry in
                    if isLoading {
                        Text(text)
                            .font(font)
                            .foregroundColor(fillColor)
                            .mask(
                                Rectangle()
                                    .fill(
                                        LinearGradient(
                                            gradient: Gradient(colors: [
                                                Color.clear,
                                                fillColor.opacity(0.3),
                                                fillColor,
                                                fillColor.opacity(0.3),
                                                Color.clear
                                            ]),
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: geometry.size.width * 0.5)
                                    .offset(x: -geometry.size.width * 0.5 + (geometry.size.width * 1.5 * animationProgress))
                            )
                    }
                }
            )
            .animation(
                isLoading ? 
                Animation.linear(duration: 2.0)
                    .repeatForever(autoreverses: false) : .default,
                value: animationProgress
            )
            .onChange(of: isLoading) { _, newValue in
                if newValue {
                    animationProgress = 1.0
                } else {
                    animationProgress = 0
                }
            }
            .onAppear {
                if isLoading {
                    animationProgress = 1.0
                }
            }
    }
}

#Preview {
    NavigationView {
        ChatView(service: RemoteService(
            name: "Local Ollama",
            type: .languageModel,
            baseService: AIService(
                name: "Ollama",
                type: .languageModel,
                localPort: 11434,
                healthCheckEndpoint: "/api/tags",
                apiFormat: .openai
            )
        ))
        .environmentObject(ServiceStore())
        .environmentObject(ConversationManager())
    }
}