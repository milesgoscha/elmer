//
//  ServiceStore.swift
//  elmer (iOS)
//
//  Service store using CloudKit relay
//

import Foundation
import SwiftUI
import Combine

@MainActor
class ServiceStore: ObservableObject {
    @Published var services: [RemoteService] = []
    @Published var connectionStatus: ConnectionStatus = .disconnected
    @Published var deviceName: String?
    @Published var serviceUpdateTimestamp: Date = Date()
    @Published var relayStatistics = RelayStatistics(
        totalRequests: 0,
        successfulRequests: 0,
        failedRequests: 0,
        averageProcessingTime: 0,
        lastRequestTime: nil
    )
    
    // Image generation tracking
    @Published var activeGenerationTasks: [String: ImageGenerationTask] = [:]
    
    let relayManager = RelayConnectionManager()
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        // Listen for manual service loading notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleLoadServicesNotification),
            name: Notification.Name("LoadServicesFromMac"),
            object: nil
        )
        
        // Observe relay manager state
        relayManager.$isConnected
            .receive(on: DispatchQueue.main)
            .sink { [weak self] connected in
                self?.connectionStatus = connected ? .connected : .disconnected
            }
            .store(in: &cancellables)
        
        relayManager.$targetDeviceName
            .receive(on: DispatchQueue.main)
            .sink { [weak self] name in
                self?.deviceName = name
            }
            .store(in: &cancellables)
        
        relayManager.$relayStatistics
            .receive(on: DispatchQueue.main)
            .sink { [weak self] stats in
                self?.relayStatistics = stats
            }
            .store(in: &cancellables)
        
        // Watch for updates to available Macs to update current services
        relayManager.$availableMacs
            .receive(on: DispatchQueue.main)
            .sink { [weak self] macs in
                self?.handleUpdatedMacAnnouncements(macs)
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Handle Updated Mac Announcements
    
    private func handleUpdatedMacAnnouncements(_ macs: [DeviceAnnouncement]) {
        // If we're currently connected to a Mac, check if there's an updated announcement for it
        guard let currentDeviceID = relayManager.targetDeviceID else { 
            // Not connected yet
            print("📱 No target device ID set, skipping service update")
            return 
        }
        
        // Find the announcement for our currently connected Mac
        if let updatedMac = macs.first(where: { $0.deviceID == currentDeviceID }) {
            print("📱 Received updated announcement from connected Mac: \(updatedMac.deviceName)")
            print("📱 Checking \(updatedMac.services.count) announced services vs \(services.count) current services")
            
            // Check if the services have changed (different count, IDs, or running status)
            // Also load services if this is the first connection (services.isEmpty)
            if services.isEmpty || hasServicesChanged(current: services, announced: updatedMac.services) {
                print("🔄 \(services.isEmpty ? "Loading initial services" : "Services changed, updating")...")
                loadServicesFromAnnouncement(updatedMac)
            } else {
                print("✅ Services unchanged")
            }
        }
    }
    
    private func hasServicesChanged(current: [RemoteService], announced: [QRServiceInfo]) -> Bool {
        // Different count means definitely changed
        if current.count != announced.count {
            return true
        }
        
        // Check if any service has changed running status or been replaced
        for qrService in announced {
            if let currentService = current.first(where: { $0.id.uuidString == qrService.id }) {
                if currentService.baseService.isRunning != qrService.isRunning {
                    print("🔄 Service \(qrService.name) status changed: \(currentService.baseService.isRunning) → \(qrService.isRunning)")
                    return true
                }
            } else {
                // Service not found in current list, something changed
                return true
            }
        }
        
        return false
    }
    
    // MARK: - QR Code Connection
    
    func connectWithQRCode(_ qrData: Data) {
        relayManager.connectWithQRCode(qrData)
        
        // Parse QR payload to get services
        if let qrPayload = try? JSONDecoder().decode(QRPayload.self, from: qrData),
           let qrServices = qrPayload.services {
            // Convert QR services to RemoteService objects
            services = qrServices.map { qrService in
                let serviceType = ServiceType(rawValue: qrService.type) ?? .custom
                let apiFormat = APIFormat(rawValue: qrService.apiFormat) ?? .custom
                
                // Create AIService with the exact ID from Mac
                let serviceID = UUID(uuidString: qrService.id) ?? UUID()
                let baseService = AIService(
                    name: qrService.name,
                    type: serviceType,
                    localPort: qrService.port,
                    healthCheckEndpoint: "/",
                    apiFormat: apiFormat,
                    isRunning: qrService.isRunning,
                    id: serviceID
                )
                
                // Create RemoteService with the exact ID from Mac
                print("📱 Creating service: \(qrService.name) with ID: \(serviceID.uuidString) (from QR: \(qrService.id), Running: \(qrService.isRunning))")
                
                return RemoteService(
                    name: qrService.name,
                    type: serviceType,
                    baseService: baseService,
                    id: serviceID
                )
            }
            
            print("📱 Loaded \(services.count) services from QR code")
        } else {
            // Fallback to mock services for older QR codes
            print("📱 Using fallback mock services (older QR format)")
            services = createMockServices()
        }
    }
    
    private func createMockServices() -> [RemoteService] {
        return [
            RemoteService(
                name: "Local Ollama",
                type: .languageModel,
                baseService: AIService(
                    name: "Ollama",
                    type: .languageModel,
                    localPort: 11434,
                    healthCheckEndpoint: "/api/tags",
                    apiFormat: .openai
                )
            )
        ]
    }
    
    // MARK: - Connection Management
    
    func disconnect() {
        relayManager.disconnect()
        services = []
        connectionStatus = .disconnected
    }
    
    func refreshConnection() {
        relayManager.refreshConnection()
    }
    
    @objc private func handleLoadServicesNotification(_ notification: Notification) {
        if let announcement = notification.userInfo?["announcement"] as? DeviceAnnouncement {
            print("📱 Received notification to load services from \(announcement.deviceName)")
            loadServicesFromAnnouncement(announcement)
        }
    }
    
    func loadServicesFromAnnouncement(_ announcement: DeviceAnnouncement) {
        print("📱 loadServicesFromAnnouncement called with \(announcement.services.count) services from \(announcement.deviceName)")
        
        // Convert QRServiceInfo to RemoteService
        let remoteServices = announcement.services.map { qrService in
            // Map the service type string to ServiceType enum
            let serviceType = ServiceType(rawValue: qrService.type) ?? .custom
            
            // IMPORTANT: Use the exact same UUID from the Mac
            let serviceID = UUID(uuidString: qrService.id) ?? UUID()
            
            let baseService = AIService(
                name: qrService.name,
                type: serviceType,
                localPort: qrService.port,
                healthCheckEndpoint: "/health",
                apiFormat: APIFormat(rawValue: qrService.apiFormat) ?? .openai,
                isRunning: qrService.isRunning,
                isAutoDetected: false,
                detectionStatus: .running,
                customName: qrService.baseURL, // Store remote URL in customName
                id: serviceID  // Pass the ID to AIService
            )
            
            print("📱 Loading service: \(qrService.name) with ID: \(serviceID.uuidString) (from Mac: \(qrService.id), Running: \(qrService.isRunning))")
            
            return RemoteService(
                name: qrService.name,
                type: serviceType,
                baseService: baseService,
                workflows: qrService.workflows ?? [],
                id: serviceID
            )
        }
        
        self.services = remoteServices
        self.serviceUpdateTimestamp = Date()
        
        // Force UI update by triggering objectWillChange
        self.objectWillChange.send()
        
        print("📱 Loaded \(remoteServices.count) services from Mac announcement - UI should update now")
    }
    
    // MARK: - Service Status
    
    func getConnectionStatus(for service: RemoteService) -> ServiceConnectionStatus {
        guard connectionStatus == .connected else {
            return .failed
        }
        
        // If we're connected to the relay, assume services are available
        // The actual service status will be determined when trying to use it
        // This avoids showing "Not running" for services that are actually working
        return .connected
    }
    
    // MARK: - API Client Creation
    
    func createAPIClient(for service: RemoteService) -> SecureAPIClient {
        return SecureAPIClient(service: service.baseService, relayManager: relayManager)
    }
    
    // MARK: - Push Notification Handling
    
    func handleRemoteNotification(_ userInfo: [AnyHashable: Any]) {
        relayManager.handleRemoteNotification(userInfo)
    }
    
    // MARK: - Image Generation Task Tracking
    
    func startImageGeneration(for serviceId: UUID, prompt: String, conversationId: UUID) -> String {
        let taskId = UUID().uuidString
        let task = ImageGenerationTask(
            id: taskId,
            serviceId: serviceId,
            conversationId: conversationId,
            prompt: prompt,
            startTime: Date()
        )
        activeGenerationTasks[taskId] = task
        return taskId
    }
    
    func completeImageGeneration(taskId: String) {
        activeGenerationTasks.removeValue(forKey: taskId)
    }
    
    func isGeneratingForService(_ serviceId: UUID) -> Bool {
        return activeGenerationTasks.values.contains { $0.serviceId == serviceId }
    }
    
    func getActiveGenerationTask(for serviceId: UUID) -> ImageGenerationTask? {
        return activeGenerationTasks.values.first { $0.serviceId == serviceId }
    }
}

// MARK: - Supporting Types

enum ConnectionStatus {
    case disconnected
    case connecting
    case connected
}

enum ServiceConnectionStatus {
    case connected
    case connecting
    case failed
}

struct RemoteService: Identifiable {
    let id: UUID
    let name: String
    let type: ServiceType
    let baseService: AIService
    let workflows: [ComfyUIWorkflow]
    
    init(name: String, type: ServiceType, baseService: AIService, workflows: [ComfyUIWorkflow] = [], id: UUID? = nil) {
        self.id = id ?? UUID()
        self.name = name
        self.type = type
        self.baseService = baseService
        self.workflows = workflows
    }
}

struct ImageGenerationTask {
    let id: String
    let serviceId: UUID
    let conversationId: UUID
    let prompt: String
    let startTime: Date
}
