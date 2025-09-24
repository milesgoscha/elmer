import Foundation
import AppKit

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
    
    var color: NSColor {
        switch self {
        case .running: return .systemGreen
        case .installed: return .systemYellow
        case .manual: return .systemBlue
        case .unknown: return .systemGray
        }
    }
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
    
    // Health check with stability improvements
    func checkHealth() async -> Bool {
        let url = URL(string: "http://localhost:\(localPort)\(healthCheckEndpoint)")!
        
        // Try the check twice to avoid flaky network timing issues
        for attempt in 1...2 {
            do {
                var request = URLRequest(url: url)
                request.httpMethod = "GET"
                request.timeoutInterval = 1.5  // Slightly shorter timeout
                
                let (_, response) = try await URLSession.shared.data(for: request)
                
                if let httpResponse = response as? HTTPURLResponse {
                    let isHealthy = httpResponse.statusCode >= 200 && httpResponse.statusCode < 400
                    if isHealthy {
                        return true  // If we get a successful response, service is definitely running
                    }
                }
            } catch {
                // On connection errors, wait briefly before retry (only on first attempt)
                if attempt == 1 {
                    try? await Task.sleep(nanoseconds: 200_000_000)  // 200ms
                }
            }
        }
        return false  // Failed both attempts
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