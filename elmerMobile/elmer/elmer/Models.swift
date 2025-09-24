import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum ServiceType: String, CaseIterable, Codable {
    case languageModel = "Language Model"
    case imageGeneration = "Image Generation"
    case voiceGeneration = "Voice Generation"
    case musicGeneration = "Music Generation"
    case custom = "Custom"
    
    var icon: String {
        switch self {
        case .languageModel: return "brain"
        case .imageGeneration: return "photo"
        case .voiceGeneration: return "waveform"
        case .musicGeneration: return "music.note"
        case .custom: return "gear"
        }
    }
}

enum APIFormat: String, Codable {
    case openai = "OpenAI"
    case comfyui = "ComfyUI"
    case gradio = "Gradio"
    case custom = "Custom"
}

enum ServiceDetectionStatus: String, Codable {
    case running
    case installed
    case manual
    case unknown
    
    var displayName: String {
        switch self {
        case .running: return "Running"
        case .installed: return "Installed"
        case .manual: return "Manual"
        case .unknown: return "Unknown"
        }
    }
    
    #if os(macOS)
    var color: NSColor {
        switch self {
        case .running: return .systemGreen
        case .installed: return .systemYellow
        case .manual: return .systemBlue
        case .unknown: return .systemGray
        }
    }
    #else
    var color: UIColor {
        switch self {
        case .running: return .systemGreen
        case .installed: return .systemYellow
        case .manual: return .systemBlue
        case .unknown: return .systemGray
        }
    }
    #endif
}

struct AIService: Identifiable, Codable {
    let id: UUID
    let name: String  // Original/detected name
    var customName: String?  // User-defined custom name
    let type: ServiceType
    let localPort: Int
    let healthCheckEndpoint: String
    let apiFormat: APIFormat
    var isRunning: Bool
    var isAutoDetected: Bool
    var detectionStatus: ServiceDetectionStatus
    
    // Computed property to get display name
    var displayName: String {
        return customName ?? name
    }
    
    init(name: String, type: ServiceType, localPort: Int, healthCheckEndpoint: String, apiFormat: APIFormat, isRunning: Bool = false, isAutoDetected: Bool = false, detectionStatus: ServiceDetectionStatus = .manual, customName: String? = nil, id: UUID? = nil) {
        self.id = id ?? UUID()
        self.name = name
        self.customName = customName
        self.type = type
        self.localPort = localPort
        self.healthCheckEndpoint = healthCheckEndpoint
        self.apiFormat = apiFormat
        self.isRunning = isRunning
        self.isAutoDetected = isAutoDetected
        self.detectionStatus = detectionStatus
    }
    
    // Custom coding to handle new properties gracefully
    enum CodingKeys: String, CodingKey {
        case id, name, customName, type, localPort, healthCheckEndpoint, apiFormat, isRunning, isAutoDetected, detectionStatus
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.customName = try container.decodeIfPresent(String.self, forKey: .customName)
        self.type = try container.decode(ServiceType.self, forKey: .type)
        self.localPort = try container.decode(Int.self, forKey: .localPort)
        self.healthCheckEndpoint = try container.decode(String.self, forKey: .healthCheckEndpoint)
        self.apiFormat = try container.decode(APIFormat.self, forKey: .apiFormat)
        self.isRunning = try container.decodeIfPresent(Bool.self, forKey: .isRunning) ?? false
        self.isAutoDetected = try container.decodeIfPresent(Bool.self, forKey: .isAutoDetected) ?? false
        self.detectionStatus = try container.decodeIfPresent(ServiceDetectionStatus.self, forKey: .detectionStatus) ?? .manual
    }
    
    // Legacy defaults - will be replaced by auto-detection
    static let defaults: [AIService] = []
    
    // Health check
    func checkHealth() async -> Bool {
        let url = URL(string: "http://localhost:\(localPort)\(healthCheckEndpoint)")!
        
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 2.0
            
            let (_, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                return httpResponse.statusCode >= 200 && httpResponse.statusCode < 400
            }
            return false
        } catch {
            return false
        }
    }
}

// MARK: - Chat and Conversation Models

struct Conversation: Identifiable, Codable, Equatable {
    let id: UUID
    let serviceID: String
    let serviceName: String
    var messages: [ChatMessage]
    let createdAt: Date
    var updatedAt: Date
    
    init(serviceID: String, serviceName: String) {
        self.id = UUID()
        self.serviceID = serviceID
        self.serviceName = serviceName
        self.messages = []
        self.createdAt = Date()
        self.updatedAt = Date()
    }
    
    // Additional initializer for CloudKit reconstruction
    init(id: UUID, serviceID: String, serviceName: String, messages: [ChatMessage] = [], createdAt: Date, updatedAt: Date) {
        self.id = id
        self.serviceID = serviceID
        self.serviceName = serviceName
        self.messages = messages
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    // Custom decoding to handle old conversations without serviceID
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        self.id = try container.decode(UUID.self, forKey: .id)
        self.serviceName = try container.decode(String.self, forKey: .serviceName)
        self.messages = try container.decode([ChatMessage].self, forKey: .messages)
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        
        // Handle missing serviceID field in old conversations
        if let serviceID = try container.decodeIfPresent(String.self, forKey: .serviceID) {
            self.serviceID = serviceID
        } else {
            // For old conversations, use serviceName as serviceID
            self.serviceID = self.serviceName
            print("🗜️ Migrated old conversation: using serviceName as serviceID")
        }
    }
    
    private enum CodingKeys: String, CodingKey {
        case id, serviceID, serviceName, messages, createdAt, updatedAt
    }
}

struct ChatMessage: Identifiable, Codable, Equatable {
    let id: UUID
    let role: MessageRole
    let content: String
    let timestamp: Date
    
    // Multimodal support
    let imageData: Data?           // Small images stored directly
    let imageAssetURL: String?     // CKAsset URL for large images
    let imageMetadata: ImageMetadata? // Image dimensions, format, etc.
    
    var isUser: Bool {
        return role == .user
    }
    
    var hasImage: Bool {
        return imageData != nil || imageAssetURL != nil
    }
    
    init(role: MessageRole, content: String, imageData: Data? = nil, imageAssetURL: String? = nil, imageMetadata: ImageMetadata? = nil) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.timestamp = Date()
        self.imageData = imageData
        self.imageAssetURL = imageAssetURL
        self.imageMetadata = imageMetadata
    }
    
    // Additional initializer for CloudKit reconstruction
    init(id: UUID, role: MessageRole, content: String, timestamp: Date, imageData: Data? = nil, imageAssetURL: String? = nil, imageMetadata: ImageMetadata? = nil) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.imageData = imageData
        self.imageAssetURL = imageAssetURL
        self.imageMetadata = imageMetadata
    }
}

// MARK: - Image Metadata
struct ImageMetadata: Codable, Equatable {
    let width: Int
    let height: Int
    let format: String // "PNG", "JPEG", etc.
    let sizeBytes: Int
    
    init(width: Int, height: Int, format: String, sizeBytes: Int) {
        self.width = width
        self.height = height
        self.format = format
        self.sizeBytes = sizeBytes
    }
}

enum MessageRole: String, Codable, Equatable {
    case user = "user"
    case assistant = "assistant"
    case system = "system"
}

struct AIModel: Identifiable, Codable {
    let id: String
    let name: String
    let description: String?
    let contextLength: Int?
    
    init(id: String, name: String, description: String? = nil, contextLength: Int? = nil) {
        self.id = id
        self.name = name
        self.description = description
        self.contextLength = contextLength
    }
}

struct ComfyUIWorkflow: Identifiable, Codable {
    let id: String
    let name: String
    let filename: String
    let workflowJSON: [String: Any]
    
    init(id: String, name: String, filename: String, workflowJSON: [String: Any]) {
        self.id = id
        self.name = name
        self.filename = filename
        self.workflowJSON = workflowJSON
    }
    
    // Custom coding for workflowJSON
    enum CodingKeys: String, CodingKey {
        case id, name, filename, workflowJSON
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.filename = try container.decode(String.self, forKey: .filename)
        
        // Decode JSON as Data then convert to dictionary
        if let jsonData = try container.decodeIfPresent(Data.self, forKey: .workflowJSON),
           let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
            self.workflowJSON = json
        } else {
            self.workflowJSON = [:]
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(filename, forKey: .filename)
        
        // Encode dictionary as Data
        let jsonData = try JSONSerialization.data(withJSONObject: workflowJSON)
        try container.encode(jsonData, forKey: .workflowJSON)
    }
}

// Simplified config for CloudKit relay - no longer need complex service configs