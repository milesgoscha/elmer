//
//  CloudKitRelay.swift
//  elmer
//
//  Simplified CloudKit relay architecture for private database communication
//

import Foundation
import CloudKit
#if os(iOS)
import UIKit
#endif

// MARK: - CloudKit Relay Configuration
struct CloudKitRelayConfig {
    static let requestRecordType = "AIRequest"
    static let responseRecordType = "AIResponse"
    static let deviceAnnouncementRecordType = "DeviceAnnouncement"
    static let requestSubscriptionID = "ai-request-subscription"
    static let responseSubscriptionID = "ai-response-subscription"
    static let deviceAnnouncementSubscriptionID = "device-announcement-subscription"
    
    // Use private database for each user's iCloud
    static var container: CKContainer {
        return CKContainer(identifier: "iCloud.com.elmer.relay")
    }
    
    static var privateDB: CKDatabase {
        return container.privateCloudDatabase
    }
}

// MARK: - AI Request Record
struct AIRequest: Codable {
    var id: String
    let serviceID: String
    let serviceName: String
    let endpoint: String
    let method: String
    let headers: [String: String]
    let body: Data?
    var timestamp: Date
    let deviceID: String  // Which device should process this
    var status: RequestStatus
    
    init(serviceID: String, serviceName: String, endpoint: String, 
         method: String = "POST", headers: [String: String] = [:], 
         body: Data? = nil, deviceID: String) {
        self.id = UUID().uuidString
        self.serviceID = serviceID
        self.serviceName = serviceName
        self.endpoint = endpoint
        self.method = method
        self.headers = headers
        self.body = body
        self.timestamp = Date()
        self.deviceID = deviceID
        self.status = .pending
    }
}

// MARK: - AI Response Record
struct AIResponse: Codable {
    var id: String
    let requestID: String  // Links back to request
    let statusCode: Int
    let headers: [String: String]
    let body: Data?
    let error: String?
    var timestamp: Date
    let processingTime: TimeInterval
    
    init(requestID: String, statusCode: Int, headers: [String: String] = [:], 
         body: Data? = nil, error: String? = nil, processingTime: TimeInterval = 0) {
        self.id = UUID().uuidString
        self.requestID = requestID
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
        self.error = error
        self.timestamp = Date()
        self.processingTime = processingTime
    }
}

// MARK: - Request Status
enum RequestStatus: String, Codable {
    case pending = "pending"
    case processing = "processing"
    case completed = "completed"
    case failed = "failed"
    case cancelled = "cancelled"
}

// MARK: - CloudKit Record Extensions for Relay
extension CKRecord {
    // Create CKRecord from AIRequest
    convenience init(aiRequest: AIRequest) {
        let recordID = CKRecord.ID(recordName: aiRequest.id)
        self.init(recordType: CloudKitRelayConfig.requestRecordType, recordID: recordID)
        
        self["serviceID"] = aiRequest.serviceID
        self["serviceName"] = aiRequest.serviceName
        self["endpoint"] = aiRequest.endpoint
        self["method"] = aiRequest.method
        self["timestamp"] = aiRequest.timestamp
        self["deviceID"] = aiRequest.deviceID
        self["status"] = aiRequest.status.rawValue
        
        // Store headers as JSON
        if let headersData = try? JSONEncoder().encode(aiRequest.headers),
           let headersString = String(data: headersData, encoding: .utf8) {
            self["headers"] = headersString
        }
        
        // Store body as CKAsset if large, otherwise as data
        if let body = aiRequest.body {
            if body.count > 900_000 { // Leave buffer under 1MB limit
                // Save to temp file and create asset
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("\(aiRequest.id).data")
                try? body.write(to: tempURL)
                self["bodyAsset"] = CKAsset(fileURL: tempURL)
            } else {
                self["bodyData"] = body as CKRecordValue
            }
        }
    }
    
    // Create CKRecord from AIResponse
    convenience init(aiResponse: AIResponse) {
        let recordID = CKRecord.ID(recordName: aiResponse.id)
        self.init(recordType: CloudKitRelayConfig.responseRecordType, recordID: recordID)
        
        self["requestID"] = aiResponse.requestID
        self["statusCode"] = aiResponse.statusCode
        self["timestamp"] = aiResponse.timestamp
        self["processingTime"] = aiResponse.processingTime
        
        if let error = aiResponse.error {
            self["error"] = error
        }
        
        // Store headers as JSON
        if let headersData = try? JSONEncoder().encode(aiResponse.headers),
           let headersString = String(data: headersData, encoding: .utf8) {
            self["headers"] = headersString
        }
        
        // Store body as CKAsset if large
        if let body = aiResponse.body {
            if body.count > 900_000 {
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("\(aiResponse.id).data")
                try? body.write(to: tempURL)
                self["bodyAsset"] = CKAsset(fileURL: tempURL)
            } else {
                self["bodyData"] = body as CKRecordValue
            }
        }
    }
    
    // Convert CKRecord to AIRequest
    func toAIRequest() -> AIRequest? {
        guard recordType == CloudKitRelayConfig.requestRecordType,
              let serviceID = self["serviceID"] as? String,
              let serviceName = self["serviceName"] as? String,
              let endpoint = self["endpoint"] as? String,
              let method = self["method"] as? String,
              let timestamp = self["timestamp"] as? Date,
              let deviceID = self["deviceID"] as? String,
              let statusString = self["status"] as? String,
              let status = RequestStatus(rawValue: statusString) else {
            return nil
        }
        
        // Decode headers
        var headers: [String: String] = [:]
        if let headersString = self["headers"] as? String,
           let headersData = headersString.data(using: .utf8),
           let decodedHeaders = try? JSONDecoder().decode([String: String].self, from: headersData) {
            headers = decodedHeaders
        }
        
        // Get body from data or asset
        var body: Data?
        if let bodyData = self["bodyData"] as? Data {
            body = bodyData
        } else if let bodyAsset = self["bodyAsset"] as? CKAsset,
                  let fileURL = bodyAsset.fileURL,
                  let data = try? Data(contentsOf: fileURL) {
            body = data
        }
        
        var request = AIRequest(
            serviceID: serviceID,
            serviceName: serviceName,
            endpoint: endpoint,
            method: method,
            headers: headers,
            body: body,
            deviceID: deviceID
        )
        
        // Override generated values with stored ones
        request.id = recordID.recordName
        request.timestamp = timestamp
        request.status = status
        
        return request
    }
    
    // Convert CKRecord to AIResponse
    func toAIResponse() -> AIResponse? {
        guard recordType == CloudKitRelayConfig.responseRecordType else {
            print("❌ Response parsing failed: wrong record type '\(recordType)', expected '\(CloudKitRelayConfig.responseRecordType)'")
            return nil
        }
        
        guard let requestID = self["requestID"] as? String else {
            print("❌ Response parsing failed: missing or invalid requestID")
            return nil
        }
        
        guard let statusCode = self["statusCode"] as? Int else {
            print("❌ Response parsing failed: missing or invalid statusCode")
            return nil
        }
        
        guard let timestamp = self["timestamp"] as? Date else {
            print("❌ Response parsing failed: missing or invalid timestamp")
            return nil
        }
        
        guard let processingTime = self["processingTime"] as? Double else {
            print("❌ Response parsing failed: missing or invalid processingTime")
            return nil
        }
        
        let error = self["error"] as? String
        
        // Decode headers
        var headers: [String: String] = [:]
        if let headersString = self["headers"] as? String,
           let headersData = headersString.data(using: .utf8),
           let decodedHeaders = try? JSONDecoder().decode([String: String].self, from: headersData) {
            headers = decodedHeaders
        }
        
        // Get body from data or asset
        var body: Data?
        if let bodyData = self["bodyData"] as? Data {
            body = bodyData
        } else if let bodyAsset = self["bodyAsset"] as? CKAsset,
                  let fileURL = bodyAsset.fileURL,
                  let data = try? Data(contentsOf: fileURL) {
            body = data
        }
        
        var response = AIResponse(
            requestID: requestID,
            statusCode: statusCode,
            headers: headers,
            body: body,
            error: error,
            processingTime: processingTime
        )
        
        // Override generated values
        response.id = recordID.recordName
        response.timestamp = timestamp
        
        return response
    }
}

// MARK: - Relay Statistics
struct RelayStatistics {
    let totalRequests: Int
    let successfulRequests: Int
    let failedRequests: Int
    let averageProcessingTime: TimeInterval
    let lastRequestTime: Date?
    
    var successRate: Double {
        guard totalRequests > 0 else { return 0 }
        return Double(successfulRequests) / Double(totalRequests)
    }
}

// MARK: - QR Payload for connection
struct QRPayload: Codable {
    let deviceID: String
    let timestamp: Date
    let version: Int
    let services: [QRServiceInfo]?
    
    init(deviceID: String, services: [QRServiceInfo]? = nil) {
        self.deviceID = deviceID
        self.timestamp = Date()
        self.version = 4 // Simplified version without masterKey
        self.services = services
    }
}

// Service info for QR code
struct QRServiceInfo: Codable {
    let id: String
    let name: String
    let type: String
    let port: Int
    let apiFormat: String
    let isRunning: Bool
    let workflows: [ComfyUIWorkflow]?
    let baseURL: String? // For remote services, full URL like "http://192.168.1.100:11434"
    
    init(id: String, name: String, type: String, port: Int, apiFormat: String, isRunning: Bool, workflows: [ComfyUIWorkflow]? = nil, baseURL: String? = nil) {
        self.id = id
        self.name = name
        self.type = type
        self.port = port
        self.apiFormat = apiFormat
        self.isRunning = isRunning
        self.workflows = workflows
        self.baseURL = baseURL
    }
    
    // Custom coding to handle workflows
    enum CodingKeys: String, CodingKey {
        case id, name, type, port, apiFormat, isRunning, workflows, baseURL
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.type = try container.decode(String.self, forKey: .type)
        self.port = try container.decode(Int.self, forKey: .port)
        self.apiFormat = try container.decode(String.self, forKey: .apiFormat)
        self.isRunning = try container.decode(Bool.self, forKey: .isRunning)
        self.workflows = try container.decodeIfPresent([ComfyUIWorkflow].self, forKey: .workflows)
        self.baseURL = try container.decodeIfPresent(String.self, forKey: .baseURL)
    }
}

// MARK: - Device Announcement for Automatic Discovery
struct DeviceAnnouncement: Codable {
    let deviceID: String
    let deviceName: String
    let deviceType: String // "mac" or "ios"
    let services: [QRServiceInfo]
    var lastSeen: Date
    var isActive: Bool
    
    init(deviceID: String, deviceName: String, deviceType: String, services: [QRServiceInfo]) {
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.deviceType = deviceType
        self.services = services
        self.lastSeen = Date()
        self.isActive = true
    }
}

// MARK: - CloudKit Record Extensions for Device Announcement
extension CKRecord {
    convenience init(deviceAnnouncement: DeviceAnnouncement) {
        let recordID = CKRecord.ID(recordName: deviceAnnouncement.deviceID)
        self.init(recordType: CloudKitRelayConfig.deviceAnnouncementRecordType, recordID: recordID)
        
        self["deviceID"] = deviceAnnouncement.deviceID
        self["deviceName"] = deviceAnnouncement.deviceName
        self["deviceType"] = deviceAnnouncement.deviceType
        self["lastSeen"] = deviceAnnouncement.lastSeen
        self["isActive"] = deviceAnnouncement.isActive ? 1 : 0
        
        // Store services as JSON
        if let servicesData = try? JSONEncoder().encode(deviceAnnouncement.services),
           let servicesString = String(data: servicesData, encoding: .utf8) {
            self["services"] = servicesString
        }
    }
    
    func toDeviceAnnouncement() -> DeviceAnnouncement? {
        guard recordType == CloudKitRelayConfig.deviceAnnouncementRecordType,
              let deviceID = self["deviceID"] as? String,
              let deviceName = self["deviceName"] as? String,
              let deviceType = self["deviceType"] as? String,
              let lastSeen = self["lastSeen"] as? Date else {
            return nil
        }
        
        let isActive = (self["isActive"] as? Int ?? 0) == 1
        
        // Decode services
        var services: [QRServiceInfo] = []
        if let servicesString = self["services"] as? String,
           let servicesData = servicesString.data(using: .utf8),
           let decodedServices = try? JSONDecoder().decode([QRServiceInfo].self, from: servicesData) {
            services = decodedServices
        }
        
        var announcement = DeviceAnnouncement(
            deviceID: deviceID,
            deviceName: deviceName,
            deviceType: deviceType,
            services: services
        )
        announcement.lastSeen = lastSeen
        announcement.isActive = isActive
        
        return announcement
    }
}

// MARK: - Device Identity Management
class DeviceIdentityManager {
    static func getOrCreateDeviceID() -> String {
        let key = "com.elmer.deviceID"
        if let existing = UserDefaults.standard.string(forKey: key) {
            return existing
        }
        let newID = "ios-" + UUID().uuidString.lowercased().prefix(8)
        UserDefaults.standard.set(newID, forKey: key)
        return newID
    }
    
    static func getDeviceName() -> String {
        #if os(iOS)
        return UIDevice.current.name
        #else
        return "Unknown Device"
        #endif
    }
}