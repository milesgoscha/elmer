import SwiftUI

struct ComfyUIView: View {
    let service: RemoteService
    
    var body: some View {
        ImageGenerationView(service: service)
    }
}

// MARK: - Universal Image Generation View

struct GeneratedImage: Identifiable {
    let id = UUID()
    let imageURL: String
    let prompt: String
    let timestamp: Date
}

struct ImageGenerationView: View {
    let service: RemoteService
    
    @EnvironmentObject var serviceStore: ServiceStore
    @State private var prompt: String = ""
    @State private var isGenerating: Bool = false
    @State private var generationHistory: [GeneratedImage] = []
    @State private var errorMessage: String?
    @State private var imageSize: String = "1024x1024"
    
    // Available models for this service
    @State private var availableModels: [AIModel] = []
    @State private var selectedModel: AIModel?
    @State private var isLoadingModels = false
    
    // Workflow management
    @State private var selectedWorkflow: ComfyUIWorkflow?
    @State private var showingModelPicker = false
    
    private var apiClient: SecureAPIClient {
        serviceStore.createAPIClient(for: service)
    }
    
    private var isComfyUI: Bool {
        service.baseService.apiFormat == .comfyui
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Main content area
            ScrollView {
                LazyVStack(spacing: 20) {
                    // Show generation history as a feed
                    if generationHistory.isEmpty {
                        EmptyFeedState()
                    } else {
                        ForEach(generationHistory.reversed()) { generatedImage in
                            GeneratedImageCard(
                                imageURL: generatedImage.imageURL,
                                prompt: generatedImage.prompt,
                                timestamp: generatedImage.timestamp
                            )
                        }
                    }
                    
                    // Settings (moved to bottom of feed)
                    if !generationHistory.isEmpty {
                        Divider()
                            .padding(.vertical, 8)
                        
                        ImageGenerationSettings(
                            imageSize: $imageSize,
                            isComfyUI: isComfyUI,
                            selectedWorkflow: selectedWorkflow,
                            selectedModel: selectedModel
                        )
                    }
                }
                .padding(20)
            }
            .background(ElmeriOSTheme.backgroundColor)
            
            // Bottom input area
            ImagePromptInput(
                prompt: $prompt,
                isGenerating: isGenerating,
                onGenerate: generateImage
            )
        }
        .background(ElmeriOSTheme.backgroundColor)
        .navigationTitle(service.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Button(action: {
                    if isComfyUI && !service.workflows.isEmpty || !availableModels.isEmpty {
                        showingModelPicker = true
                    }
                }) {
                    HStack(spacing: 4) {
                        LoadingTextView(
                            text: service.name,
                            isLoading: isLoadingModels && availableModels.isEmpty,
                            font: .system(size: 15, weight: .medium),
                            baseColor: ElmeriOSTheme.textTertiary,
                            fillColor: ElmeriOSTheme.textColor
                        )
                        
                        if !isLoadingModels && ((isComfyUI && !service.workflows.isEmpty) || !availableModels.isEmpty) {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(ElmeriOSTheme.textTertiary)
                                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(isLoadingModels)
            }
        }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .sheet(isPresented: $showingModelPicker) {
            ModelWorkflowPickerView(
                isComfyUI: isComfyUI,
                workflows: service.workflows,
                selectedWorkflow: $selectedWorkflow,
                availableModels: availableModels,
                selectedModel: $selectedModel
            )
        }
        .onAppear {
            setupInitialState()
        }
    }
    
    private func generateImage() {
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard serviceStore.getConnectionStatus(for: service) == .connected else {
            errorMessage = "Not connected to service. Please check your connection."
            return
        }
        
        isGenerating = true
        errorMessage = nil
        
        Task {
            do {
                let imageURL: String
                
                if isComfyUI {
                    // Use selected workflow or create basic one
                    let workflow: [String: Any]
                    if let selectedWorkflow = selectedWorkflow {
                        workflow = try modifyWorkflowWithPrompt(selectedWorkflow.workflowJSON, prompt: prompt)
                    } else {
                        workflow = createBasicComfyUIWorkflow(prompt: prompt)
                    }
                    let response = try await apiClient.sendComfyUIRequest(workflow: workflow)
                    
                    // Extract image URL from ComfyUI response
                    if let images = response["images"] as? [String], let firstImage = images.first {
                        imageURL = firstImage
                    } else {
                        throw APIError.invalidResponse
                    }
                } else {
                    // For DALL-E style APIs
                    imageURL = try await apiClient.sendImageGenerationRequest(
                        prompt: prompt,
                        size: imageSize
                    )
                }
                
                await MainActor.run {
                    let newImage = GeneratedImage(
                        imageURL: imageURL,
                        prompt: prompt,
                        timestamp: Date()
                    )
                    generationHistory.append(newImage)
                    isGenerating = false
                    prompt = "" // Clear prompt after successful generation
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to generate image: \(error.localizedDescription)"
                    isGenerating = false
                }
            }
        }
    }
    
    private func setupInitialState() {
        print("🖼️ ImageGenerationView: Setting up \(service.name) with \(service.workflows.count) workflows")
        
        // Set default workflow (first available or nil for built-in)
        selectedWorkflow = service.workflows.first
        
        // Fetch models for this service
        Task {
            await fetchModels()
        }
    }
    
    @MainActor
    private func fetchModels() async {
        isLoadingModels = true
        
        do {
            let models = try await apiClient.fetchAvailableModels()
            availableModels = models
            
            // Set first model as default if none selected
            if selectedModel == nil {
                selectedModel = models.first
            }
            
            print("✅ Fetched \(models.count) models for \(service.name)")
        } catch {
            print("⚠️ Failed to fetch models for \(service.name): \(error)")
            // Fallback to a default model
            availableModels = [AIModel(id: "sd_xl_base_1.0.safetensors", name: "SDXL Base", description: "Default model")]
            selectedModel = availableModels.first
        }
        
        isLoadingModels = false
    }
    
    private func createBasicComfyUIWorkflow(prompt: String) -> [String: Any] {
        // Generate random seed for each request
        let randomSeed = Int.random(in: 0...4294967294)
        
        print("🎨 Creating Qwen ComfyUI workflow")
        print("🎨 Workflow prompt: \(prompt)")
        
        // Qwen-based ComfyUI workflow adapted from user's working setup
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
        
        print("🔧 Generated Qwen workflow with \(workflow.count) nodes")
        return workflow
    }
    
    // MARK: - Workflow Parameter Modification
    
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
            
            // Also update model if we have a selected model and this is a checkpoint loader
            if classType == "CheckpointLoaderSimple" || classType == "CheckpointLoader",
               let selectedModel = selectedModel {
                modifiedInputs["ckpt_name"] = selectedModel.id
                print("📝 Modified checkpoint in node \(nodeId) to \(selectedModel.name)")
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
}

// MARK: - Supporting Components

struct GeneratedImageCard: View {
    let imageURL: String
    let prompt: String
    let timestamp: Date
    
    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }
    
    var body: some View {
        VStack(spacing: 12) {
            AsyncImage(url: URL(string: imageURL)) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } placeholder: {
                Rectangle()
                    .fill(ElmeriOSTheme.surfaceColor)
                    .overlay(
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: ElmeriOSTheme.textSecondary))
                    )
            }
            .frame(maxHeight: 400)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(ElmeriOSTheme.borderColor, lineWidth: 1)
            )
            
            // Prompt and timestamp
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(timeFormatter.string(from: timestamp))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(ElmeriOSTheme.textTertiary)
                    
                    Spacer()
                }
                
                Text(prompt)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(ElmeriOSTheme.textSecondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            // Image actions
            HStack(spacing: 12) {
                Button("Save to Photos") {
                    // TODO: Implement save to photos
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(ElmeriOSTheme.accentColor)
                
                Spacer()
                
                Button("Share") {
                    // TODO: Implement share
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(ElmeriOSTheme.accentColor)
            }
        }
    }
}

struct EmptyFeedState: View {
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            VStack(spacing: 16) {
                Image(systemName: "photo.stack")
                    .font(.system(size: 64, weight: .regular))
                    .foregroundColor(ElmeriOSTheme.textTertiary)
                
                VStack(spacing: 8) {
                    Text("No images yet")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(ElmeriOSTheme.textColor)
                    
                    Text("Start generating images using the prompt below")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundColor(ElmeriOSTheme.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }
            
            Spacer()
        }
        .frame(minHeight: 300)
    }
}

struct ImageGenerationSettings: View {
    @Binding var imageSize: String
    let isComfyUI: Bool
    let selectedWorkflow: ComfyUIWorkflow?
    let selectedModel: AIModel?
    
    private let imageSizes = ["512x512", "1024x1024", "1024x1792", "1792x1024"]
    
    var body: some View {
        VStack(spacing: 16) {
            
            // ComfyUI info (workflow and model)
            if isComfyUI {
                VStack(spacing: 8) {
                    if let selectedWorkflow = selectedWorkflow {
                        HStack {
                            Text("Workflow:")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(ElmeriOSTheme.textSecondary)
                            
                            Text(selectedWorkflow.name)
                                .font(.system(size: 12, weight: .regular))
                                .foregroundColor(ElmeriOSTheme.textColor)
                            
                            Spacer()
                        }
                    } else {
                        HStack {
                            Text("Workflow:")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(ElmeriOSTheme.textSecondary)
                            
                            Text("Built-in Basic")
                                .font(.system(size: 12, weight: .regular))
                                .foregroundColor(ElmeriOSTheme.textColor)
                            
                            Spacer()
                        }
                    }
                    
                    if let selectedModel = selectedModel {
                        HStack {
                            Text("Model:")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(ElmeriOSTheme.textSecondary)
                            
                            Text(selectedModel.name)
                                .font(.system(size: 12, weight: .regular))
                                .foregroundColor(ElmeriOSTheme.textColor)
                            
                            if let description = selectedModel.description {
                                Text("(\(description))")
                                    .font(.system(size: 11, weight: .regular))
                                    .foregroundColor(ElmeriOSTheme.textTertiary)
                            }
                            
                            Spacer()
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
            
            // Size selector (only for non-ComfyUI)
            if !isComfyUI {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Size")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(ElmeriOSTheme.textColor)
                    
                    Picker("Image Size", selection: $imageSize) {
                        ForEach(imageSizes, id: \.self) { size in
                            Text(size).tag(size)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
            }
        }
    }
}

struct ImagePromptInput: View {
    @Binding var prompt: String
    let isGenerating: Bool
    let onGenerate: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                TextField("Enter prompt", text: $prompt)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(ElmeriOSTheme.textColor)
                    .submitLabel(.send)
                    .onSubmit {
                        if !prompt.isEmpty && !isGenerating {
                            onGenerate()
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
            
            Button(action: onGenerate) {
                if isGenerating {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: ElmeriOSTheme.accentColor))
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(!prompt.isEmpty ? ElmeriOSTheme.accentColor : ElmeriOSTheme.textTertiary)
                }
            }
            .disabled(prompt.isEmpty || isGenerating)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(ElmeriOSTheme.backgroundColor)
    }
}

struct ModelWorkflowPickerView: View {
    let isComfyUI: Bool
    let workflows: [ComfyUIWorkflow]
    @Binding var selectedWorkflow: ComfyUIWorkflow?
    let availableModels: [AIModel]
    @Binding var selectedModel: AIModel?
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List {
                if isComfyUI && !workflows.isEmpty {
                    Section("Workflow") {
                        Button("Built-in Basic") {
                            selectedWorkflow = nil
                            dismiss()
                        }
                        .foregroundColor(selectedWorkflow == nil ? ElmeriOSTheme.accentColor : ElmeriOSTheme.textColor)
                        
                        ForEach(workflows, id: \.id) { workflow in
                            Button(workflow.name) {
                                selectedWorkflow = workflow
                                dismiss()
                            }
                            .foregroundColor(selectedWorkflow?.id == workflow.id ? ElmeriOSTheme.accentColor : ElmeriOSTheme.textColor)
                        }
                    }
                }
                
                if !availableModels.isEmpty {
                    Section("Model") {
                        ForEach(availableModels, id: \.id) { model in
                            VStack(alignment: .leading, spacing: 2) {
                                Button(model.name) {
                                    selectedModel = model
                                    dismiss()
                                }
                                .foregroundColor(selectedModel?.id == model.id ? ElmeriOSTheme.accentColor : ElmeriOSTheme.textColor)
                                
                                if let description = model.description {
                                    Text(description)
                                        .font(.system(size: 12, weight: .regular))
                                        .foregroundColor(ElmeriOSTheme.textTertiary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}


