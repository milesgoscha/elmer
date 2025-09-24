//
//  ChatView+ImageGeneration.swift
//  elmer
//
//  Extensions to ChatView for handling image generation
//

import SwiftUI
import UIKit

extension ChatView {
    
    // MARK: - Image Generation Methods
    
    func generateImage(prompt: String) async {
        // Start tracking this generation task
        let taskId = await MainActor.run {
            isLoading = true
            messageText = ""
            
            // Create or get current conversation first
            if currentConversation == nil {
                currentConversation = conversationManager.createConversation(
                    serviceName: service.name,
                    modelName: nil
                )
            }
            
            return serviceStore.startImageGeneration(
                for: service.id,
                prompt: prompt,
                conversationId: currentConversation!.id
            )
        }
        
        // Add user prompt to conversation
        let userMessage = ChatMessage(role: .user, content: prompt)
        currentConversation?.messages.append(userMessage)
        conversationManager.updateConversation(currentConversation!)
        
        do {
            let apiClient = serviceStore.createAPIClient(for: service)
            
            if service.baseService.apiFormat == .comfyui {
                // ComfyUI image generation
                try await generateComfyUIImage(prompt: prompt, apiClient: apiClient)
            } else {
                // DALL-E style image generation (OpenAI compatible)
                try await generateOpenAIImage(prompt: prompt, apiClient: apiClient)
            }
            
        } catch {
            print("❌ Image generation failed: \(error)")
            
            // Add error message to conversation
            let errorMessage = ChatMessage(
                role: .assistant,
                content: "Sorry, I couldn't generate the image. Error: \(error.localizedDescription)"
            )
            
            await MainActor.run {
                currentConversation?.messages.append(errorMessage)
                conversationManager.updateConversation(currentConversation!)
            }
        }
        
        await MainActor.run {
            isLoading = false
            serviceStore.completeImageGeneration(taskId: taskId)
        }
        
        // Save to CloudKit if available
        if let conversation = currentConversation,
           let lastMessage = conversation.messages.last {
            Task {
                try? await cloudKitConversationManager.addMessage(to: conversation, message: lastMessage)
            }
        }
    }
    
    private func generateComfyUIImage(prompt: String, apiClient: SecureAPIClient) async throws {
        // Use the first available workflow, or create a basic one if none available
        let workflow: [String: Any]
        if let firstWorkflow = service.workflows.first {
            workflow = try modifyWorkflowWithPrompt(firstWorkflow.workflowJSON, prompt: prompt)
            print("🎨 Using uploaded workflow: \(firstWorkflow.name)")
        } else {
            workflow = createBasicComfyUIWorkflow(prompt: prompt)
            print("🎨 Using basic fallback workflow (no uploaded workflows found)")
        }
        
        // Send workflow to ComfyUI
        let response = try await apiClient.sendComfyUIRequest(workflow: workflow)
        
        // Extract images from ComfyUI response
        if let imageUrls = response["images"] as? [String], let firstImageUrl = imageUrls.first {
            // Convert data URL to actual image data
            if let dataUrl = URL(string: firstImageUrl),
               let imageData = try? Data(contentsOf: dataUrl) {
                
                // Verify we got valid image data
                guard let image = UIImage(data: imageData) else {
                    throw ImageGenerationError.invalidImageData
                }
                
                // Create image metadata
                let metadata = ImageMetadata(
                    width: Int(image.size.width),
                    height: Int(image.size.height),
                    format: "PNG",
                    sizeBytes: imageData.count
                )
                
                // Add generated image to conversation
                let assistantMessage = ChatMessage(
                    role: .assistant,
                    content: "Here's the image I generated using your ComfyUI workflow:",
                    imageData: imageData,
                    imageMetadata: metadata
                )
                
                await MainActor.run {
                    currentConversation?.messages.append(assistantMessage)
                    conversationManager.updateConversation(currentConversation!)
                }
            } else {
                throw ImageGenerationError.invalidImageData
            }
        } else {
            throw ImageGenerationError.generationFailed("No images returned from ComfyUI")
        }
    }
    
    private func generateOpenAIImage(prompt: String, apiClient: SecureAPIClient) async throws {
        // Get image URL from DALL-E style endpoint
        let imageUrl = try await apiClient.sendImageGenerationRequest(prompt: prompt, size: "1024x1024")
        
        // Download the actual image data from the URL
        guard let url = URL(string: imageUrl) else {
            throw ImageGenerationError.invalidImageData
        }
        
        let (imageData, _) = try await URLSession.shared.data(from: url)
        
        // Verify we got valid image data
        guard let image = UIImage(data: imageData) else {
            throw ImageGenerationError.invalidImageData
        }
        
        // Create image metadata
        let metadata = ImageMetadata(
            width: Int(image.size.width),
            height: Int(image.size.height),
            format: "PNG",
            sizeBytes: imageData.count
        )
        
        // Add generated image to conversation
        let assistantMessage = ChatMessage(
            role: .assistant,
            content: "Here's the image I generated for you:",
            imageData: imageData,
            imageMetadata: metadata
        )
        
        await MainActor.run {
            currentConversation?.messages.append(assistantMessage)
            conversationManager.updateConversation(currentConversation!)
        }
    }
}

// MARK: - Image Generation Errors
enum ImageGenerationError: Error, LocalizedError {
    case noModelsAvailable
    case generationFailed(String)
    case invalidImageData
    
    var errorDescription: String? {
        switch self {
        case .noModelsAvailable:
            return "No image generation models are available"
        case .generationFailed(let reason):
            return "Image generation failed: \(reason)"
        case .invalidImageData:
            return "The generated image data is invalid"
        }
    }
}

// MARK: - UI Extensions for Image Generation
extension ChatView {
    
    // Computed property to check if generation is active (either local or persistent)
    private var isGenerationActive: Bool {
        return isLoading || serviceStore.isGeneratingForService(service.id)
    }
    
    // Get active generation task info for display
    private var activeGenerationInfo: String? {
        if let task = serviceStore.getActiveGenerationTask(for: service.id) {
            let elapsed = Date().timeIntervalSince(task.startTime)
            return "Generating: \(task.prompt.prefix(30))... (\(Int(elapsed))s)"
        }
        return nil
    }
    
    @ViewBuilder
    var imageGenerationInput: some View {
        if service.baseService.type == .imageGeneration || service.baseService.apiFormat == .comfyui {
            VStack(spacing: 0) {
                // Show active generation info if available
                if let generationInfo = activeGenerationInfo {
                    HStack {
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.8)
                                .progressViewStyle(CircularProgressViewStyle(tint: ElmeriOSTheme.accentColor))
                            
                            Text(generationInfo)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(ElmeriOSTheme.textSecondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(ElmeriOSTheme.surfaceColor.opacity(0.5))
                        )
                        
                        Spacer()
                    }
                    .padding(.bottom, 8)
                }
                
                // Input area - matches ThemedChatInput exactly
                HStack(spacing: 12) {
                    HStack(spacing: 8) {
                        TextField("Describe the image you want to generate...", text: $messageText)
                            .font(.system(size: 15, weight: .regular))
                            .foregroundColor(ElmeriOSTheme.textColor)
                            .submitLabel(.send)
                            .onSubmit {
                                let prompt = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
                                if !prompt.isEmpty && !isGenerationActive {
                                    Task {
                                        await generateImage(prompt: prompt)
                                    }
                                }
                            }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 18)
                            .fill(ElmeriOSTheme.surfaceColor)
                            .overlay(
                                RoundedRectangle(cornerRadius: 18)
                                    .stroke(ElmeriOSTheme.borderColor, lineWidth: 1)
                            )
                    )
                    
                    Button(action: {
                        let prompt = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !prompt.isEmpty else { return }
                        
                        Task {
                            await generateImage(prompt: prompt)
                        }
                    }) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(!messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isGenerationActive ? ElmeriOSTheme.accentColor : ElmeriOSTheme.textTertiary)
                    }
                    .disabled(isGenerationActive || messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .background(ElmeriOSTheme.backgroundColor)
            }
        }
    }
    
    // MARK: - ComfyUI Workflow Helper Functions
    
    private func modifyWorkflowWithPrompt(_ originalWorkflow: [String: Any], prompt: String) throws -> [String: Any] {
        var modifiedWorkflow = originalWorkflow
        
        // Find and modify text prompt nodes
        for (nodeId, nodeValue) in originalWorkflow {
            guard let node = nodeValue as? [String: Any],
                  let classType = node["class_type"] as? String,
                  let inputs = node["inputs"] as? [String: Any] else {
                continue
            }
            
            var modifiedInputs = inputs
            
            // Handle different prompt node types
            switch classType {
            case "CLIPTextEncode":
                // Standard CLIP text encoding - replace the "text" input
                if inputs["text"] is String {
                    modifiedInputs["text"] = prompt
                    print("📝 Modified CLIPTextEncode node \(nodeId) with prompt")
                }
                
            case "CLIPTextEncodeSDXL", "CLIPTextEncodeFlux":
                // SDXL/Flux specific encoders
                if inputs["text"] is String {
                    modifiedInputs["text"] = prompt
                    print("📝 Modified \(classType) node \(nodeId) with prompt")
                }
                
            case "ConditioningConcat", "ConditioningCombine":
                // Some workflows use conditioning nodes
                if inputs["text_g"] is String {
                    modifiedInputs["text_g"] = prompt
                }
                if inputs["text_l"] is String {
                    modifiedInputs["text_l"] = prompt
                }
                
            default:
                // Check for common prompt field names
                for key in inputs.keys {
                    if key.lowercased().contains("prompt") || key.lowercased().contains("text") {
                        if inputs[key] is String {
                            modifiedInputs[key] = prompt
                            print("📝 Modified \(classType) node \(nodeId) field \(key) with prompt")
                        }
                    }
                }
            }
            
            // Update seed for randomization
            if classType == "KSampler" || classType == "KSamplerAdvanced" {
                modifiedInputs["seed"] = Int.random(in: 0...4294967294)
                print("📝 Randomized seed in sampler node \(nodeId)")
            }
            
            // Check if we actually modified anything by converting to JSON and comparing
            if !NSDictionary(dictionary: modifiedInputs).isEqual(to: inputs) {
                var modifiedNode = node
                modifiedNode["inputs"] = modifiedInputs
                modifiedWorkflow[nodeId] = modifiedNode
            }
        }
        
        return modifiedWorkflow
    }
    
    private func createBasicComfyUIWorkflow(prompt: String) -> [String: Any] {
        // Generate random seed for each request
        let randomSeed = Int.random(in: 0...4294967294)
        
        print("🎨 Creating basic ComfyUI workflow")
        print("🎨 Workflow prompt: \(prompt)")
        
        // Basic ComfyUI workflow
        let workflow: [String: Any] = [
            "93": [
                "inputs": [
                    "text": "jpeg compression, low quality, blurry, artifacts",
                    "clip": ["96", 0]
                ],
                "class_type": "CLIPTextEncode",
                "_meta": [
                    "title": "CLIP Text Encode (Negative)"
                ]
            ],
            "94": [
                "inputs": [
                    "vae_name": "qwen_image_vae.safetensors"
                ],
                "class_type": "VAELoader",
                "_meta": [
                    "title": "Load VAE"
                ]
            ],
            "95": [
                "inputs": [
                    "seed": randomSeed,
                    "steps": 20,
                    "cfg": 4.5,
                    "sampler_name": "euler",
                    "scheduler": "normal",
                    "denoise": 1,
                    "model": ["124", 0],
                    "positive": ["100", 0],
                    "negative": ["93", 0],
                    "latent_image": ["97", 0]
                ],
                "class_type": "KSampler",
                "_meta": [
                    "title": "KSampler"
                ]
            ],
            "96": [
                "inputs": [
                    "clip_name": "qwen_2.5_vl_7b.safetensors",
                    "type": "qwen_image",
                    "device": "default"
                ],
                "class_type": "CLIPLoader",
                "_meta": [
                    "title": "Load CLIP"
                ]
            ],
            "97": [
                "inputs": [
                    "width": 1280,
                    "height": 768,
                    "length": 1,
                    "batch_size": 1
                ],
                "class_type": "EmptyHunyuanLatentVideo",
                "_meta": [
                    "title": "EmptyHunyuanLatentVideo"
                ]
            ],
            "98": [
                "inputs": [
                    "samples": ["95", 0],
                    "vae": ["94", 0]
                ],
                "class_type": "VAEDecode",
                "_meta": [
                    "title": "VAE Decode"
                ]
            ],
            "100": [
                "inputs": [
                    "text": prompt,
                    "clip": ["96", 0]
                ],
                "class_type": "CLIPTextEncode",
                "_meta": [
                    "title": "CLIP Text Encode (Prompt)"
                ]
            ],
            "102": [
                "inputs": [
                    "images": ["98", 0]
                ],
                "class_type": "PreviewImage",
                "_meta": [
                    "title": "Preview Image"
                ]
            ],
            "124": [
                "inputs": [
                    "unet_name": "qwen-image-Q5_K_M.gguf"
                ],
                "class_type": "UnetLoaderGGUF",
                "_meta": [
                    "title": "Unet Loader (GGUF)"
                ]
            ]
        ]
        
        print("🔧 Generated basic workflow with \(workflow.count) nodes")
        return workflow
    }
}