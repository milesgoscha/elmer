//
//  RelayConnectionManager.swift
//  elmer (iOS)
//
//  Simplified connection manager using CloudKit relay
//

import Foundation
import CloudKit
import Combine

@MainActor
class RelayConnectionManager: ObservableObject {
    @Published var isConnected = false
    @Published var targetDeviceID: String?
    @Published var targetDeviceName: String?
    @Published var availableMacs: [DeviceAnnouncement] = []
    @Published var isDiscovering = false
    @Published var relayStatistics = RelayStatistics(
        totalRequests: 0,
        successfulRequests: 0,
        failedRequests: 0,
        averageProcessingTime: 0,
        lastRequestTime: nil
    )
    
    private var relayClient: CloudKitRelayClient
    private var cancellables = Set<AnyCancellable>()
    private var discoveryTimer: Timer?
    
    init() {
        self.relayClient = CloudKitRelayClient()
        
        // Observe relay client state
        relayClient.$isConnected
            .receive(on: DispatchQueue.main)
            .sink { [weak self] connected in
                self?.isConnected = connected
            }
            .store(in: &cancellables)
        
        relayClient.$statistics
            .receive(on: DispatchQueue.main)
            .sink { [weak self] stats in
                self?.relayStatistics = stats
            }
            .store(in: &cancellables)
        
        // Load saved connection if any
        loadSavedConnection()
    }
    
    // MARK: - QR Code Connection
    
    func connectWithQRCode(_ qrData: Data) {
        do {
            let payload = try JSONDecoder().decode(QRPayload.self, from: qrData)
            
            targetDeviceID = payload.deviceID
            targetDeviceName = DeviceIdentityManager.getDeviceName()
            
            // Connect relay client
            relayClient.connectToMac(deviceID: payload.deviceID)
            
            // Save connection and services
            saveConnection()
            if let services = payload.services {
                saveServices(services)
            }
            
            print("✅ Connected to Mac: \(payload.deviceID)")
            
        } catch {
            print("❌ Failed to decode QR payload: \(error)")
        }
    }
    
    // MARK: - Automatic Device Discovery
    
    func startDiscovery() {
        isDiscovering = true
        
        // Discover immediately
        Task {
            await discoverMacs()
        }
        
        // Schedule periodic discovery every 10 seconds
        discoveryTimer?.invalidate()
        discoveryTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { _ in
            Task {
                await self.discoverMacs()
            }
        }
    }
    
    func stopDiscovery() {
        print("🛑 stopDiscovery() called - stopping background monitoring")
        isDiscovering = false
        discoveryTimer?.invalidate()
        discoveryTimer = nil
    }
    
    @MainActor
    private func switchToBackgroundMonitoring() {
        // Continue discovery but at a slower interval for background monitoring
        discoveryTimer?.invalidate()
        discoveryTimer = nil
        
        // Create timer that runs on main run loop for reliability
        let timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] timer in
            if !timer.isValid { return }
            guard let self = self else { return }
            Task { @MainActor in
                await self.backgroundDiscoverMacs()
            }
        }
        
        // Ensure timer runs in common modes to survive UI updates
        RunLoop.main.add(timer, forMode: .common)
        discoveryTimer = timer
    }
    
    @MainActor
    private func discoverMacs() async {
        let query = CKQuery(
            recordType: CloudKitRelayConfig.deviceAnnouncementRecordType,
            predicate: NSPredicate(format: "deviceType == %@", "mac")
        )
        query.sortDescriptors = [NSSortDescriptor(key: "lastSeen", ascending: false)]
        
        do {
            let results = try await CloudKitRelayConfig.privateDB.records(matching: query)
            
            var macs: [DeviceAnnouncement] = []
            for (_, result) in results.matchResults {
                if case .success(let record) = result,
                   let announcement = record.toDeviceAnnouncement() {
                    // Only show Macs seen in last 2 minutes
                    let twoMinutesAgo = Date().addingTimeInterval(-120)
                    if announcement.lastSeen > twoMinutesAgo {
                        macs.append(announcement)
                    }
                }
            }
            
            self.availableMacs = macs
            
            if !macs.isEmpty {
                
                // Auto-connect logic (same as before but less verbose)
                if let savedTarget = targetDeviceID, !isConnected {
                    if let matchingMac = macs.first(where: { $0.deviceID == savedTarget }) {
                        print("📱 Reconnecting to \(matchingMac.deviceName)")
                        connectToMac(matchingMac)
                    }
                }
                
                if macs.count == 1 && !isConnected {
                    let mac = macs[0]
                    print("🤖 Auto-connecting to \(mac.deviceName)")
                    connectToMac(mac)
                }
            }
            
        } catch {
            if let ckError = error as? CKError, ckError.code == .unknownItem {
                // Silent - normal on first run
            } else {
                print("❌ Failed to discover Macs: \(error)")
            }
        }
        
        isDiscovering = false
    }
    
    @MainActor
    private func backgroundDiscoverMacs() async {
        // Silent background discovery - same logic as discoverMacs() but no logging
        let query = CKQuery(
            recordType: CloudKitRelayConfig.deviceAnnouncementRecordType,
            predicate: NSPredicate(format: "deviceType == %@", "mac")
        )
        query.sortDescriptors = [NSSortDescriptor(key: "lastSeen", ascending: false)]
        
        do {
            let results = try await CloudKitRelayConfig.privateDB.records(matching: query)
            
            var macs: [DeviceAnnouncement] = []
            for (_, result) in results.matchResults {
                if case .success(let record) = result,
                   let announcement = record.toDeviceAnnouncement() {
                    let twoMinutesAgo = Date().addingTimeInterval(-120)
                    if announcement.lastSeen > twoMinutesAgo {
                        macs.append(announcement)
                    }
                }
            }
            
            self.availableMacs = macs
            
            if !macs.isEmpty {
                // Auto-connect logic (silent)
                if let savedTarget = targetDeviceID, !isConnected {
                    if let matchingMac = macs.first(where: { $0.deviceID == savedTarget }) {
                        connectToMac(matchingMac)
                    }
                }
                
                if macs.count == 1 && !isConnected {
                    let mac = macs[0]
                    connectToMac(mac)
                }
            }
            
        } catch {
            // Silent background errors unless critical
            if let ckError = error as? CKError, ckError.code != .unknownItem {
                print("❌ Background discovery failed: \(error)")
            }
        }
    }
    
    func connectToMac(_ announcement: DeviceAnnouncement) {
        targetDeviceID = announcement.deviceID
        targetDeviceName = announcement.deviceName
        
        // Connect relay client
        relayClient.connectToMac(deviceID: announcement.deviceID)
        
        // Set connected state immediately (relay client also sets it but there might be a delay)
        isConnected = true
        
        // Clear any old services first
        UserDefaults.standard.removeObject(forKey: "relay.services")
        
        // Save connection and services
        saveConnection()
        saveServices(announcement.services)
        
        print("✅ Connected to \(announcement.deviceName) with \(announcement.services.count) services")
        
        // Notify ServiceStore to load services from this announcement
        NotificationCenter.default.post(
            name: Notification.Name("LoadServicesFromMac"),
            object: nil,
            userInfo: ["announcement": announcement]
        )
        
        // Keep discovery running to receive real-time service updates
        // Switch to slower background monitoring for connected Mac
        Task { @MainActor in
            switchToBackgroundMonitoring()
        }
    }
    
    // MARK: - API Request Forwarding
    
    func sendRequest(
        to service: AIService,
        endpoint: String,
        method: String = "POST",
        headers: [String: String] = [:],
        body: Data? = nil
    ) async throws -> (Data, HTTPURLResponse) {
        
        guard targetDeviceID != nil else {
            throw RelayError.notConnected
        }
        
        // Send through relay
        print("📤 RelayConnectionManager: Sending request to service \(service.name) with ID: \(service.id.uuidString)")
        let response = try await relayClient.sendRequest(
            serviceID: service.id.uuidString,
            serviceName: service.name,
            endpoint: endpoint,
            method: method,
            headers: headers,
            body: body
        )
        
        // Convert to HTTP response format for compatibility
        let httpResponse = HTTPURLResponse(
            url: URL(string: "http://localhost:\(service.localPort)\(endpoint)")!,
            statusCode: response.statusCode,
            httpVersion: nil,
            headerFields: response.headers
        )!
        
        return (response.body ?? Data(), httpResponse)
    }
    
    // MARK: - Connection Management
    
    func disconnect() {
        relayClient.disconnect()
        targetDeviceID = nil
        targetDeviceName = nil
        clearSavedConnection()
    }
    
    func refreshConnection() {
        print("🔄 Manual refresh triggered")
        // Trigger immediate discovery and cleanup
        Task { @MainActor in
            await discoverMacs()
            await relayClient.cleanupOldRecords(olderThan: 1)
        }
    }
    
    // MARK: - Persistence
    
    private func saveConnection() {
        UserDefaults.standard.set(targetDeviceID, forKey: "relay.deviceID")
        UserDefaults.standard.set(targetDeviceName, forKey: "relay.deviceName")
    }
    
    private func saveServices(_ services: [QRServiceInfo]) {
        if let encoded = try? JSONEncoder().encode(services) {
            UserDefaults.standard.set(encoded, forKey: "relay.services")
        }
    }
    
    private func loadSavedConnection() {
        // For now, clear any saved connection to avoid confusion
        // We'll let the user manually connect each time
        clearSavedConnection()
        
        print("📱 Starting fresh - no auto-connection")
        // Start discovery
        startDiscovery()
    }
    
    private func clearSavedConnection() {
        UserDefaults.standard.removeObject(forKey: "relay.deviceID")
        UserDefaults.standard.removeObject(forKey: "relay.deviceName")
        UserDefaults.standard.removeObject(forKey: "relay.services")
    }
    
    // MARK: - Push Notification Handling
    
    func handleRemoteNotification(_ userInfo: [AnyHashable: Any]) {
        relayClient.handleRemoteNotification(userInfo)
    }
}