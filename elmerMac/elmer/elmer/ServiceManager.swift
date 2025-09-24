import Foundation
import Combine
import CloudKit

class ServiceManager: ObservableObject {
    @Published var services: [AIService] = []
    @Published var detectedServices: [ServiceDetector.DetectedService] = []
    @Published var hiddenServiceIds: Set<UUID> = []
    @Published var isMonitoring = false
    @Published var lastQRGeneration: Date?
    @Published var isRelayActive = false
    @Published var relayStatistics = RelayStatistics(
        totalRequests: 0,
        successfulRequests: 0,
        failedRequests: 0,
        averageProcessingTime: 0,
        lastRequestTime: nil
    )
    
    private var timer: Timer?
    private var detectionTimer: Timer?
    
    // CloudKit Relay integration
    var relayManager: CloudKitRelayManager?
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        loadServices()
        loadHiddenServices()
        
        // Initialize CloudKit Relay manager and start relay
        Task { @MainActor in
            relayManager = CloudKitRelayManager(serviceManager: self)
            relayManager?.startListening()
            relayManager?.startAutomaticCleanup(intervalHours: 6)
            isRelayActive = true
            
            // Observe relay statistics
            relayManager?.$statistics
                .receive(on: DispatchQueue.main)
                .sink { [weak self] stats in
                    self?.relayStatistics = stats
                }
                .store(in: &cancellables)
        }
        
        startAutoDetection()
        startMonitoring()
    }
    
    func startRelay() {
        Task { @MainActor in
            relayManager?.startListening()
            relayManager?.startAutomaticCleanup(intervalHours: 6)
            isRelayActive = true
            
            // Observe relay statistics
            relayManager?.$statistics
                .receive(on: DispatchQueue.main)
                .sink { [weak self] stats in
                    self?.relayStatistics = stats
                }
                .store(in: &cancellables)
        }
    }
    
    func stopRelay() {
        Task { @MainActor in
            relayManager?.stopListening()
            isRelayActive = false
            relayStatistics = RelayStatistics(
                totalRequests: 0,
                successfulRequests: 0,
                failedRequests: 0,
                averageProcessingTime: 0,
                lastRequestTime: nil as Date?
            ) // Reset statistics
        }
    }
    
    func cleanupStaleRequests() {
        Task {
            await relayManager?.cleanupStalePendingRequests()
        }
    }
    
    func startMonitoring() {
        timer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { _ in
            self.checkAllServices()
        }
        isMonitoring = true
    }
    
    // MARK: - Auto Detection
    
    func startAutoDetection() {
        // Initial detection
        Task {
            await performServiceDetection()
        }
        
        // Periodic detection every 30 seconds
        detectionTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { _ in
            Task {
                await self.performServiceDetection()
            }
        }
    }
    
    @MainActor
    func performServiceDetection() async {
        let detected = await ServiceDetector.detectAllServices()
        self.detectedServices = detected
        
        // Merge detected services with existing services  
        await mergeDetectedServices(detected)
    }
    
    @MainActor
    private func mergeDetectedServices(_ detected: [ServiceDetector.DetectedService]) async {
        var updatedServices: [AIService] = []
        
        // First, preserve all manually added services (not auto-detected)
        let manualServices = services.filter { !$0.isAutoDetected }
        updatedServices.append(contentsOf: manualServices)
        
        // Add or update auto-detected services
        for detectedService in detected {
            let aiService = ServiceDetector.createAIService(from: detectedService)
            
            // Check if we already have this service (by name and port)
            if let existingIndex = services.firstIndex(where: { 
                $0.name == aiService.name && $0.localPort == aiService.localPort 
            }) {
                // Only update if the existing service is auto-detected
                // Don't override manually added services
                if services[existingIndex].isAutoDetected {
                    // Update existing service but preserve custom name and UUID
                    let preservedId = services[existingIndex].id
                    let updatedService = AIService(
                        name: aiService.name,
                        type: aiService.type,
                        localPort: aiService.localPort,
                        healthCheckEndpoint: aiService.healthCheckEndpoint,
                        apiFormat: aiService.apiFormat,
                        isRunning: aiService.isRunning,
                        isAutoDetected: aiService.isAutoDetected,
                        detectionStatus: aiService.detectionStatus,
                        customName: services[existingIndex].customName,
                        id: preservedId // Preserve UUID!
                    )
                    print("🔄 Updating auto-detected service: \(updatedService.name) (ID: \(updatedService.id.uuidString))")
                    
                    // Replace the existing auto-detected service in updatedServices
                    if let updateIndex = updatedServices.firstIndex(where: { $0.id == preservedId }) {
                        updatedServices[updateIndex] = updatedService
                    } else {
                        updatedServices.append(updatedService)
                    }
                }
                // If existing service is manual, skip updating it
            } else {
                // Add new auto-detected service
                updatedServices.append(aiService)
            }
        }
        
        services = updatedServices
        saveServices()
    }
    
    // MARK: - Service Filtering
    
    var activeServices: [AIService] {
        services.filter { $0.isRunning }
    }
    
    var availableServices: [AIService] {
        services.filter { $0.isRunning }
    }
    
    var installedServices: [AIService] {
        services.filter { $0.detectionStatus == .installed }
    }
    
    func checkAllServices() {
        // Check service health
        for index in services.indices {
            checkService(at: index)
        }
    }
    
    func checkService(at index: Int) {
        guard index < services.count else { return }
        let service = services[index]
        let previousStatus = service.isRunning
        
        Task {
            let isRunning = await service.checkHealth()
            await MainActor.run {
                if index < self.services.count {
                    self.services[index].isRunning = isRunning
                    
                    // If status changed, immediately broadcast the update and trigger UI refresh
                    if previousStatus != isRunning {
                        print("🔄 Service \(service.name) status changed: \(previousStatus) → \(isRunning)")
                        
                        // Force UI update by triggering @Published change
                        self.objectWillChange.send()
                        
                        Task {
                            await self.relayManager?.announceDevice()
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Service Management
    
    func addService(_ service: AIService) {
        services.append(service)
        saveServices()
        
        // Immediately broadcast service changes
        Task {
            await relayManager?.announceDevice()
        }
    }
    
    func removeService(_ service: AIService) {
        services.removeAll { $0.id == service.id }
        saveServices()
        
        // Immediately broadcast service changes
        Task {
            await relayManager?.announceDevice()
        }
    }
    
    func updateService(_ service: AIService) {
        if let index = services.firstIndex(where: { $0.id == service.id }) {
            services[index] = service
            saveServices()
            
            // Immediately broadcast service changes
            Task {
                await relayManager?.announceDevice()
            }
        }
    }
    
    // MARK: - Hide/Unhide Services
    
    var visibleServices: [AIService] {
        services.filter { !hiddenServiceIds.contains($0.id) }
    }
    
    func hideService(_ service: AIService) {
        hiddenServiceIds.insert(service.id)
        saveHiddenServices()
    }
    
    func unhideService(_ service: AIService) {
        hiddenServiceIds.remove(service.id)
        saveHiddenServices()
    }
    
    func isServiceHidden(_ service: AIService) -> Bool {
        hiddenServiceIds.contains(service.id)
    }
    
    private func saveHiddenServices() {
        UserDefaults.standard.set(Array(hiddenServiceIds.map { $0.uuidString }), forKey: "HiddenServiceIds")
    }
    
    private func loadHiddenServices() {
        if let hiddenIds = UserDefaults.standard.stringArray(forKey: "HiddenServiceIds") {
            hiddenServiceIds = Set(hiddenIds.compactMap { UUID(uuidString: $0) })
        }
    }
    
    // MARK: - QR Code Generation
    
    func generateQRPayload() -> Data? {
        // Get device ID from relay manager
        let deviceID = DeviceIdentityManager.getOrCreateDeviceID()
        
        // Convert services to QR format - only include running services
        print("🏷️ Generating QR with running services:")
        let qrServices = services
            .filter { $0.isRunning }
            .map { service in
                print("  - \(service.name) (ID: \(service.id.uuidString), Running: \(service.isRunning))")
                return QRServiceInfo(
                    id: service.id.uuidString,
                    name: service.name,
                    type: service.type.rawValue,
                    port: service.localPort,
                    apiFormat: service.apiFormat.rawValue,
                    isRunning: service.isRunning,
                    workflows: nil,
                    baseURL: service.customName // For remote services, customName contains the full URL
                )
            }
        
        let payload = QRPayload(
            deviceID: deviceID,
            services: qrServices
        )
        
        lastQRGeneration = Date()
        saveQRStatus()
        
        return try? JSONEncoder().encode(payload)
    }
    
    // MARK: - Persistence
    
    private func loadServices() {
        if let data = UserDefaults.standard.data(forKey: "services"),
           let decoded = try? JSONDecoder().decode([AIService].self, from: data) {
            services = decoded
        }
    }
    
    private func saveServices() {
        if let encoded = try? JSONEncoder().encode(services) {
            UserDefaults.standard.set(encoded, forKey: "services")
        }
    }
    
    private func saveQRStatus() {
        UserDefaults.standard.set(lastQRGeneration, forKey: "lastQRGeneration")
    }
    
    private func loadQRStatus() {
        lastQRGeneration = UserDefaults.standard.object(forKey: "lastQRGeneration") as? Date
    }
    
    // MARK: - Cleanup
    
    deinit {
        timer?.invalidate()
        detectionTimer?.invalidate()
        
        // Capture relayManager directly to avoid self capture in deinit
        let relayManager = self.relayManager
        Task { @MainActor in
            relayManager?.stopListening()
        }
    }
}
