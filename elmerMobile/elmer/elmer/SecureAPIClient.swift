//
//  SecureAPIClient.swift
//  elmer (iOS)
//
//  API client using CloudKit relay - no longer needs encryption
//

import Foundation

class SecureAPIClient {
    private let relayManager: RelayConnectionManager
    private let service: AIService
    
    init(service: AIService, relayManager: RelayConnectionManager) {
        self.service = service
        self.relayManager = relayManager
    }
    
    // MARK: - Tool Support Detection
    
    // Cache of models we've tested for tool support
    private static var toolSupportCache: [String: Bool] = [:]
    
    // Manual override for testing - can be called to force enable/disable tools for a model
    static func setToolSupport(for model: String, enabled: Bool) {
        toolSupportCache[model] = enabled
        print(enabled ? "🔧 Manually enabled tools for '\(model)'" : "⚠️ Manually disabled tools for '\(model)'")
    }
    
    // Clear cache for testing
    static func clearToolSupportCache() {
        toolSupportCache.removeAll()
        print("🗑️ Tool support cache cleared")
    }
    
    // Test a specific model's tool support and update cache
    func testModelToolSupport(model: String) async -> Bool {
        let result = await testToolSupportDynamically(for: model)
        await MainActor.run {
            Self.toolSupportCache[model] = result
        }
        return result
    }
    
    private func shouldUseTools(for model: String) -> Bool {
        // Check cache first
        if let cached = Self.toolSupportCache[model] {
            print(cached ? "🔧 Model '\(model)' supports tools (cached)" : "⚠️ Model '\(model)' doesn't support tools (cached)")
            return cached
        }
        
        // For unknown models, we'll test dynamically in the background
        // But for immediate requests, use heuristic detection as fallback
        let heuristicResult = detectToolSupportHeuristic(for: model)
        
        // Start async test in background to update cache for future requests
        Task {
            let dynamicResult = await testToolSupportDynamically(for: model)
            await MainActor.run {
                Self.toolSupportCache[model] = dynamicResult
                if dynamicResult != heuristicResult {
                    print("🔄 Updated cache for '\(model)': heuristic=\(heuristicResult), dynamic=\(dynamicResult)")
                }
            }
        }
        
        // Cache the heuristic result for now
        Self.toolSupportCache[model] = heuristicResult
        
        if heuristicResult {
            print("🔧 Model '\(model)' likely supports tools (heuristic) - testing in background")
        } else {
            print("⚠️ Model '\(model)' likely doesn't support tools (heuristic) - testing in background")
        }
        
        return heuristicResult
    }
    
    private func detectToolSupportHeuristic(for model: String) -> Bool {
        let modelLower = model.lowercased()
        
        // Models that explicitly don't support tools
        let incompatiblePatterns = ["gemma", "phi", "tinyllama", "codegen", "starcoder", "llama-2", "llama2", "vicuna", "alpaca"]
        for pattern in incompatiblePatterns {
            if modelLower.contains(pattern) {
                print("❌ Model '\(model)' explicitly doesn't support tools: contains '\(pattern)'")
                return false
            }
        }
        
        // Known compatible model patterns with detailed matching
        let compatiblePatterns: [(pattern: String, description: String)] = [
            // OpenAI GPT models
            ("gpt-3.5", "OpenAI GPT-3.5"),
            ("gpt-4", "OpenAI GPT-4 series"),
            ("gpt", "General GPT models"),
            
            // Llama 3.1+ (tool support started in 3.1)
            ("llama3.1", "Llama 3.1 series"),
            ("llama3.2", "Llama 3.2 series"),
            ("llama-3.1", "Llama 3.1 (alt naming)"),
            ("llama-3.2", "Llama 3.2 (alt naming)"),
            ("llama-3_1", "Llama 3.1 (underscore naming)"),
            ("llama3_1", "Llama 3.1 (underscore naming)"),
            
            // Mistral models with tool support
            ("mistral-7b-instruct", "Mistral 7B Instruct"),
            ("mistral-8x7b", "Mixtral 8x7B"),
            ("mixtral", "Mixtral series"),
            ("mistral-large", "Mistral Large"),
            ("mistral", "General Mistral models"),
            
            // Qwen models
            ("qwen2.5", "Qwen 2.5 series"),
            ("qwen-2.5", "Qwen 2.5 (alt naming)"),
            ("qwen2_5", "Qwen 2.5 (underscore naming)"),
            
            // Function-calling specialized models
            ("hermes", "Nous Hermes"),
            ("functionary", "Functionary models"),
            ("gorilla", "Gorilla models"),
            
            // Commercial models
            ("claude-3", "Anthropic Claude 3"),
            ("claude", "General Claude models"),
            ("command-r", "Cohere Command-R"),
            ("command", "Cohere Command models"),
            
            // Other known tool-compatible models
            ("codellama", "Code Llama (some versions)"),
            ("deepseek", "DeepSeek models"),
            ("yi-34b", "Yi 34B models")
        ]
        
        // Check for exact and partial matches
        for (pattern, description) in compatiblePatterns {
            if modelLower.contains(pattern) {
                // Additional version checks for Llama to ensure it's 3.1+
                if pattern.contains("llama") {
                    if isLlamaVersionSupported(modelLower) {
                        print("✅ Detected tool-compatible model: \(description)")
                        return true
                    }
                } else {
                    print("✅ Detected tool-compatible model: \(description)")
                    return true
                }
            }
        }
        
        // Check for version-specific patterns that might not match above
        if hasVersionIndicatingToolSupport(modelLower) {
            print("✅ Model appears to support tools based on version indicators")
            return true
        }
        
        // For unknown models, be very conservative - default to no tools for safety
        // This prevents 400 errors from models that don't support tools
        print("📝 Unknown model '\(model)' - defaulting to no tools for safety (will test dynamically in background)")
        return false
    }
    
    private func isLlamaVersionSupported(_ modelName: String) -> Bool {
        // Llama 3.1+ supports tools, earlier versions don't
        if modelName.contains("llama3.1") || modelName.contains("llama-3.1") || modelName.contains("llama3_1") {
            return true
        }
        if modelName.contains("llama3.2") || modelName.contains("llama-3.2") || modelName.contains("llama3_2") {
            return true
        }
        // Llama 3.0 and earlier don't support tools natively
        if modelName.contains("llama3.0") || modelName.contains("llama-3.0") {
            return false
        }
        if modelName.contains("llama2") || modelName.contains("llama-2") {
            return false
        }
        // Generic "llama3" without version - assume it's 3.1+ if it's recent
        if modelName.contains("llama3") && !modelName.contains("3.0") {
            return true
        }
        return false
    }
    
    private func hasVersionIndicatingToolSupport(_ modelName: String) -> Bool {
        // Look for keywords that suggest tool/function calling support
        let toolKeywords = ["function", "tool", "instruct", "chat", "agent"]
        for keyword in toolKeywords {
            if modelName.contains(keyword) {
                // Additional check to avoid false positives
                if !modelName.contains("base") && !modelName.contains("foundation") {
                    return true
                }
            }
        }
        return false
    }
    
    // MARK: - Dynamic Tool Support Testing
    
    private func testToolSupportDynamically(for model: String) async -> Bool {
        print("🧪 Testing tool support dynamically for model: \(model)")
        
        // Create a minimal test request with a simple tool
        let testTool: [String: Any] = [
            "type": "function",
            "function": [
                "name": "test_tool",
                "description": "A test tool to check if model supports function calling",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "test": [
                            "type": "string",
                            "description": "A test parameter"
                        ]
                    ],
                    "required": ["test"]
                ]
            ]
        ]
        
        let testMessage = [
            "role": "user",
            "content": "This is a test message to check tool support. Please ignore."
        ]
        
        let requestBody: [String: Any] = [
            "model": model,
            "messages": [testMessage],
            "tools": [testTool],
            "max_tokens": 1 // Minimal response to save resources
        ]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: requestBody)
            
            let (_, httpResponse) = try await relayManager.sendRequest(
                to: service,
                endpoint: "/v1/chat/completions",
                method: "POST",
                headers: ["Content-Type": "application/json"],
                body: jsonData
            )
            
            // If we get a 200, model supports tools
            if httpResponse.statusCode == 200 {
                print("✅ Model '\(model)' supports tools (dynamic test: 200)")
                return true
            }
            // If we get 400, check if it's specifically about tool support
            else if httpResponse.statusCode == 400 {
                print("❌ Model '\(model)' doesn't support tools (dynamic test: 400)")
                return false
            }
            // Other errors might be unrelated to tool support
            else {
                print("⚠️ Ambiguous result for '\(model)' (status: \(httpResponse.statusCode)) - falling back to heuristic")
                return detectToolSupportHeuristic(for: model)
            }
            
        } catch {
            print("⚠️ Error testing tool support for '\(model)': \(error) - falling back to heuristic")
            return detectToolSupportHeuristic(for: model)
        }
    }
    
    // MARK: - Tool Definitions (DEPRECATED - tools now handled by Mac app)
    
    @available(*, deprecated, message: "Tools are now handled by Mac app via UserToolManager")
    static let availableTools: [[String: Any]] = []
    
    // MARK: - Tool Execution
    
    @available(*, deprecated, message: "Tools are now handled by Mac app via UserToolManager")
    func executeTool(name: String, arguments: [String: Any]) async throws -> String {
        throw APIError.apiError("Client-side tool execution is deprecated - tools are handled by Mac app")
    }
    
    // MARK: - Deprecated tool implementations (removed - tools now handled by Mac app)
    
    func sendChatMessage(messages: [[String: Any]], model: String = "default", tools: [[String: Any]]? = nil, toolChoice: Any? = nil) async throws -> String {
        // Prepare request body
        var requestBody: [String: Any] = [
            "model": model,
            "messages": messages,
            "temperature": 0.7
            // Don't set max_tokens - let the model use its default/configured limit
            // This is especially important for thinking models that need more tokens
        ]
        
        // Smart tool detection - only add tools for compatible models
        let useTools = shouldUseTools(for: model)
        
        if useTools, let tools = tools {
            requestBody["tools"] = tools
            if let toolChoice = toolChoice {
                requestBody["tool_choice"] = toolChoice
            }
        }
        
        // Add explicit flag for Mac relay to respect iPhone's tool detection
        requestBody["_use_tools"] = useTools
        
        // Convert to JSON
        let jsonData = try JSONSerialization.data(withJSONObject: requestBody)
        
        // Send through CloudKit relay
        let (responseData, httpResponse) = try await relayManager.sendRequest(
            to: service,
            endpoint: "/v1/chat/completions",
            method: "POST",
            headers: ["Content-Type": "application/json"],
            body: jsonData
        )
        
        // Check status code
        if httpResponse.statusCode >= 400 {
            throw APIError.httpError(httpResponse.statusCode)
        }
        
        // Parse response
        guard let json = try JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
            print("❌ Failed to parse JSON response from relay")
            if let responseString = String(data: responseData, encoding: .utf8) {
                print("❌ Response data: \(responseString.prefix(500))...")
            }
            throw APIError.invalidResponse
        }
        
        // Debug: Print the full response structure to understand what we're getting
        print("📱 iPhone received response structure: \(json.keys)")
        if let choices = json["choices"] as? [[String: Any]], let firstChoice = choices.first {
            print("📱 First choice keys: \(firstChoice.keys)")
            if let message = firstChoice["message"] as? [String: Any] {
                print("📱 Message keys: \(message.keys)")
                print("📱 Message content type: \(type(of: message["content"]))")
                if let content = message["content"] {
                    print("📱 Content: \(String(describing: content).prefix(200))...")
                }
            }
        }
        
        // Check for error in response
        if let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            throw APIError.apiError(message)
        }
        
        // Extract message from response
        if let choices = json["choices"] as? [[String: Any]],
           let firstChoice = choices.first,
           let message = firstChoice["message"] as? [String: Any] {
            
            // Try to get content first
            if let content = message["content"] as? String, !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return content.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            
            // If content is empty or null, check if this is a tool call response
            // In some cases, the LLM might return tool calls without content, or content might be null
            if let toolCalls = message["tool_calls"] as? [[String: Any]], !toolCalls.isEmpty {
                // Return a message indicating tools were executed (the actual results are handled by the Mac)
                let toolNames = toolCalls.compactMap { $0["function"] as? [String: Any] }.compactMap { $0["name"] as? String }
                return "Executed tools: \(toolNames.joined(separator: ", "))"
            }
            
            // If content is null but role exists, return empty content
            if message["role"] != nil {
                return ""
            }
        }
        
        throw APIError.invalidResponse
    }
    
    // Enhanced chat function that returns full message structure (including tool calls)
    func sendChatMessageWithTools(messages: [[String: Any]], model: String = "default", tools: [[String: Any]]? = nil, toolChoice: Any? = nil) async throws -> [String: Any] {
        // Prepare request body
        var requestBody: [String: Any] = [
            "model": model,
            "messages": messages,
            "temperature": 0.7
            // Don't set max_tokens - let the model use its default/configured limit
        ]
        
        // Smart tool detection - only add tools for compatible models
        let useTools = shouldUseTools(for: model)
        
        if useTools, let tools = tools {
            requestBody["tools"] = tools
            if let toolChoice = toolChoice {
                requestBody["tool_choice"] = toolChoice
            }
        }
        
        // Add explicit flag for Mac relay to respect iPhone's tool detection
        requestBody["_use_tools"] = useTools
        
        // Convert to JSON
        let jsonData = try JSONSerialization.data(withJSONObject: requestBody)
        
        // Send through CloudKit relay
        let (responseData, httpResponse) = try await relayManager.sendRequest(
            to: service,
            endpoint: "/v1/chat/completions",
            method: "POST",
            headers: ["Content-Type": "application/json"],
            body: jsonData
        )
        
        // Check status code
        if httpResponse.statusCode >= 400 {
            throw APIError.httpError(httpResponse.statusCode)
        }
        
        // Parse response
        guard let json = try JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
            throw APIError.invalidResponse
        }
        
        // Check for error in response
        if let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            throw APIError.apiError(message)
        }
        
        // Return full response for tool handling
        return json
    }
    
    func sendImageGenerationRequest(prompt: String, size: String = "1024x1024") async throws -> String {
        let requestBody: [String: Any] = [
            "prompt": prompt,
            "n": 1,
            "size": size,
            "response_format": "url"
        ]
        
        let jsonData = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (responseData, httpResponse) = try await relayManager.sendRequest(
            to: service,
            endpoint: "/v1/images/generations",
            method: "POST",
            headers: ["Content-Type": "application/json"],
            body: jsonData
        )
        
        if httpResponse.statusCode >= 400 {
            throw APIError.httpError(httpResponse.statusCode)
        }
        
        guard let json = try JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
            throw APIError.invalidResponse
        }
        
        if let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            throw APIError.apiError(message)
        }
        
        if let data = json["data"] as? [[String: Any]],
           let firstImage = data.first,
           let imageUrl = firstImage["url"] as? String {
            return imageUrl
        }
        
        throw APIError.invalidResponse
    }
    
    func sendComfyUIRequest(workflow: [String: Any]) async throws -> [String: Any] {
        // Generate a client ID for tracking
        let clientID = UUID().uuidString
        
        let requestBody: [String: Any] = [
            "prompt": workflow,
            "client_id": clientID
        ]
        
        let jsonData = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (responseData, httpResponse) = try await relayManager.sendRequest(
            to: service,
            endpoint: "/prompt",
            method: "POST",
            headers: ["Content-Type": "application/json"],
            body: jsonData
        )
        
        if httpResponse.statusCode >= 400 {
            throw APIError.httpError(httpResponse.statusCode)
        }
        
        guard let json = try JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
            throw APIError.invalidResponse
        }
        
        // Extract prompt_id from response
        guard let promptId = json["prompt_id"] as? String else {
            throw APIError.invalidResponse
        }
        
        // Poll for results using the prompt_id
        return try await pollForComfyUIResults(promptId: promptId)
    }
    
    private func pollForComfyUIResults(promptId: String) async throws -> [String: Any] {
        // Poll for results with timeout
        let maxAttempts = 240 // 20 minutes with 5-second intervals  
        var attempt = 0
        
        while attempt < maxAttempts {
            let (responseData, httpResponse) = try await relayManager.sendRequest(
                to: service,
                endpoint: "/history/\(promptId)",
                method: "GET",
                headers: [:],
                body: nil
            )
            
            if httpResponse.statusCode >= 400 {
                throw APIError.httpError(httpResponse.statusCode)
            }
            
            guard let json = try JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
                throw APIError.invalidResponse
            }
            
            // Check if the prompt exists in history (means it's completed)
            if let promptHistory = json[promptId] as? [String: Any],
               let outputs = promptHistory["outputs"] as? [String: Any] {
                
                // Extract image URLs from outputs
                var imageUrls: [String] = []
                
                // Look for SaveImage nodes in outputs
                for (_, output) in outputs {
                    if let outputData = output as? [String: Any],
                       let images = outputData["images"] as? [[String: Any]] {
                        for imageInfo in images {
                            if let filename = imageInfo["filename"] as? String {
                                let subfolder = imageInfo["subfolder"] as? String ?? ""
                                let type = imageInfo["type"] as? String ?? "output"
                                // Fetch image data through relay and convert to data URL
                                do {
                                    let imageData = try await fetchComfyUIImage(filename: filename, subfolder: subfolder, type: type)
                                    let base64String = imageData.base64EncodedString()
                                    let dataUrl = "data:image/png;base64,\(base64String)"
                                    imageUrls.append(dataUrl)
                                    print("✅ Successfully fetched ComfyUI image: \(filename) (type: \(type))")
                                } catch {
                                    print("⚠️ Failed to fetch image \(filename): \(error)")
                                }
                            }
                        }
                    }
                }
                
                return ["images": imageUrls]
            }
            
            // Wait before polling again
            try await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
            attempt += 1
        }
        
        throw APIError.apiError("ComfyUI workflow timed out")
    }
    
    private func fetchComfyUIImage(filename: String, subfolder: String, type: String = "output") async throws -> Data {
        let endpoint = "/view?filename=\(filename)&subfolder=\(subfolder)&type=\(type)"
        print("🖼️ Fetching ComfyUI image: \(endpoint)")
        
        let (imageData, httpResponse) = try await relayManager.sendRequest(
            to: service,
            endpoint: endpoint,
            method: "GET",
            headers: [:],
            body: nil
        )
        
        if httpResponse.statusCode >= 400 {
            throw APIError.httpError(httpResponse.statusCode)
        }
        
        return imageData
    }
    
    func fetchAvailableModels() async throws -> [AIModel] {
        // For ComfyUI services, fetch checkpoints instead of OpenAI-style models
        if service.apiFormat == .comfyui || service.apiFormat == .custom {
            return try await fetchComfyUIModels()
        }
        
        // For OpenAI-style services
        let (responseData, httpResponse) = try await relayManager.sendRequest(
            to: service,
            endpoint: "/v1/models",
            method: "GET",
            headers: [:],
            body: nil
        )
        
        if httpResponse.statusCode >= 400 {
            throw APIError.httpError(httpResponse.statusCode)
        }
        
        guard let json = try JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
            throw APIError.invalidResponse
        }
        
        // Parse OpenAI-style models response
        if let data = json["data"] as? [[String: Any]] {
            return data.compactMap { modelDict in
                guard let id = modelDict["id"] as? String else { return nil }
                let name = modelDict["name"] as? String ?? id
                let description = modelDict["description"] as? String
                let contextLength = modelDict["context_length"] as? Int
                
                return AIModel(id: id, name: name, description: description, contextLength: contextLength)
            }
        }
        
        // Fallback: return a default model if the service doesn't support /v1/models
        return [AIModel(id: "default", name: "Default Model", description: "Service default model")]
    }
    
    private func fetchComfyUIModels() async throws -> [AIModel] {
        // Try different model endpoints as ComfyUI installations vary
        let modelEndpoints = [
            "/models/checkpoints",
            "/models/diffusion_models",
            "/models"
        ]
        
        for endpoint in modelEndpoints {
            do {
                let (responseData, httpResponse) = try await relayManager.sendRequest(
                    to: service,
                    endpoint: endpoint,
                    method: "GET",
                    headers: [:],
                    body: nil
                )
                
                if httpResponse.statusCode < 400 {
                    // Try to parse the response
                    if let modelFilenames = try? JSONSerialization.jsonObject(with: responseData) as? [String],
                       !modelFilenames.isEmpty {
                        
                        print("✅ Found \(modelFilenames.count) models in \(endpoint): \(modelFilenames)")
                        
                        // Convert filenames to AIModel objects
                        return modelFilenames.map { filename in
                            let cleanName = filename.replacingOccurrences(of: ".safetensors", with: "")
                                                   .replacingOccurrences(of: ".ckpt", with: "")
                                                   .replacingOccurrences(of: ".pt", with: "")
                            
                            return AIModel(
                                id: filename,
                                name: cleanName,
                                description: determineModelType(from: filename)
                            )
                        }
                    }
                }
                
                print("⚠️ Endpoint \(endpoint) returned \(httpResponse.statusCode) or empty results")
            } catch {
                print("❌ Failed to fetch models from \(endpoint): \(error)")
            }
        }
        
        // If no endpoints returned models, throw an error
        throw APIError.invalidResponse
    }
    
    private func determineModelType(from filename: String) -> String {
        let lowercased = filename.lowercased()
        
        if lowercased.contains("xl") || lowercased.contains("sdxl") {
            return "Stable Diffusion XL"
        } else if lowercased.contains("flux") {
            return "Flux"
        } else if lowercased.contains("sd3") {
            return "Stable Diffusion 3"
        } else if lowercased.contains("1.5") || lowercased.contains("15") {
            return "Stable Diffusion 1.5"
        } else if lowercased.contains("2.1") || lowercased.contains("21") {
            return "Stable Diffusion 2.1"
        } else {
            return "Stable Diffusion Model"
        }
    }
}

enum APIError: LocalizedError {
    case invalidURL
    case serializationFailed
    case httpError(Int)
    case apiError(String)
    case invalidResponse
    case serviceNotAvailable
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .serializationFailed:
            return "Failed to serialize request data"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .apiError(let message):
            return "API error: \(message)"
        case .invalidResponse:
            return "Invalid response from server"
        case .serviceNotAvailable:
            return "Service not available"
        }
    }
}