//
//  ChatView+ImagePicker.swift
//  elmer
//
//  Extensions to ChatView for handling image selection and upload
//

import SwiftUI
import PhotosUI

extension ChatView {
    
    // MARK: - Image Picker UI
    
    @ViewBuilder
    var imagePickerButton: some View {
        if service.baseService.type == .languageModel {
            // Only show for language models that might support vision
            Button(action: {
                showingImagePicker = true
            }) {
                Image(systemName: selectedImage != nil ? "photo.fill" : "photo")
                    .font(.system(size: 20))
                    .foregroundColor(selectedImage != nil ? ElmeriOSTheme.accentColor : ElmeriOSTheme.textSecondary)
            }
            .photosPicker(
                isPresented: $showingImagePicker,
                selection: $selectedImageItem,
                matching: .images,
                photoLibrary: .shared()
            )
        }
    }
    
    @ViewBuilder
    var selectedImagePreview: some View {
        if let image = selectedImage {
            HStack {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 100)
                    .cornerRadius(8)
                    .overlay(
                        Button(action: {
                            selectedImage = nil
                            selectedImageData = nil
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.white)
                                .background(Circle().fill(Color.black.opacity(0.5)))
                        }
                        .padding(4),
                        alignment: .topTrailing
                    )
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
    }
    
    // MARK: - Image Processing
    
    func loadSelectedImage() {
        guard let selectedImageItem = selectedImageItem else { return }
        
        Task {
            if let data = try? await selectedImageItem.loadTransferable(type: Data.self) {
                if let uiImage = UIImage(data: data) {
                    await MainActor.run {
                        self.selectedImage = uiImage
                        self.selectedImageData = data
                    }
                }
            }
        }
    }
    
    // MARK: - Send Message with Image
    
    @MainActor
    func sendMessageWithImage() async {
        guard !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedImage != nil else { return }
        guard serviceStore.getConnectionStatus(for: service) == .connected else {
            errorMessage = "Not connected to service. Please check your connection."
            return
        }
        
        let userMessageText = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        let imageToSend = selectedImage
        let imageDataToSend = selectedImageData
        
        // Clear inputs
        messageText = ""
        selectedImage = nil
        selectedImageData = nil
        selectedImageItem = nil
        isLoading = true
        errorMessage = nil
        
        // Create or get current conversation
        if currentConversation == nil {
            let newConversation = cloudKitConversationManager.createConversation(
                serviceID: service.id.uuidString,
                serviceName: service.name
            )
            currentConversation = newConversation
            
            let _ = conversationManager.createConversation(
                serviceName: service.name,
                modelName: selectedModel?.id
            )
        }
        
        // Create image metadata if we have an image
        var imageMetadata: ImageMetadata?
        if let image = imageToSend, let imageData = imageDataToSend {
            imageMetadata = ImageMetadata(
                width: Int(image.size.width),
                height: Int(image.size.height),
                format: "JPEG",
                sizeBytes: imageData.count
            )
        }
        
        // Add user message with image
        let userMessage = ChatMessage(
            role: .user,
            content: userMessageText.isEmpty && imageToSend != nil ? "📷 Image" : userMessageText,
            imageData: imageDataToSend,
            imageMetadata: imageMetadata
        )
        
        // Add message to conversation and force UI update
        currentConversation?.messages.append(userMessage)
        conversationManager.updateConversation(currentConversation!)
        
        do {
            // Prepare messages for API with image support
            var messages: [[String: Any]] = []
            
            for message in currentConversation?.messages ?? [] {
                if message.hasImage && message.imageData != nil {
                    // Message with image - use multimodal format
                    var content: [[String: Any]] = []
                    
                    // Add text if present
                    if !message.content.isEmpty && message.content != "📷 Image" {
                        content.append([
                            "type": "text",
                            "text": message.content
                        ])
                    }
                    
                    // Add image
                    if let imageData = message.imageData {
                        let base64Image = imageData.base64EncodedString()
                        content.append([
                            "type": "image_url",
                            "image_url": [
                                "url": "data:image/jpeg;base64,\(base64Image)"
                            ]
                        ])
                    }
                    
                    messages.append([
                        "role": message.role.rawValue,
                        "content": content
                    ])
                } else {
                    // Regular text message
                    messages.append([
                        "role": message.role.rawValue,
                        "content": message.content
                    ])
                }
            }
            
            // Send message through CloudKit relay
            let response = try await apiClient.sendChatMessage(
                messages: messages,
                model: selectedModel?.id ?? "default"
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
}

// MARK: - Image Picker State
struct ImagePickerState {
    var showingImagePicker = false
    var selectedImageItem: PhotosPickerItem? = nil
    var selectedImage: UIImage? = nil
    var selectedImageData: Data? = nil
}