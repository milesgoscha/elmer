//
//  CloudKitRelayClient.swift
//  elmer (iOS)
//
//  Manages CloudKit relay on iPhone side - sends requests and receives responses
//

import Foundation
import CloudKit
import Combine

class CloudKitRelayClient: ObservableObject {
    @Published var isConnected = false
    @Published var pendingRequests: [String: AIRequest] = [:]
    @Published var lastResponseTime: Date?
    @Published var statistics = RelayStatistics(
        totalRequests: 0,
        successfulRequests: 0,
        failedRequests: 0,
        averageProcessingTime: 0,
        lastRequestTime: nil
    )
    
    private let container = CloudKitRelayConfig.container
    private let privateDB = CloudKitRelayConfig.privateDB
    private var targetDeviceID: String?
    private var responseSubscription: CKQuerySubscription?
    private var responseCallbacks: [String: (Result<AIResponse, Error>) -> Void] = [:]
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        print("📱 CloudKit Relay Client initialized")
        Task {
            await setupResponseSubscription()
        }
        checkAuthentication()
    }
    
    // MARK: - Authentication Check
    
    private func checkAuthentication() {
        container.accountStatus { [weak self] status, error in
            DispatchQueue.main.async {
                switch status {
                case .available:
                    // Don't set isConnected here - iCloud being available doesn't mean we're connected to a Mac
                    print("✅ iCloud account available")
                case .noAccount:
                    self?.isConnected = false
                    print("❌ No iCloud account - user needs to sign in")
                case .restricted, .couldNotDetermine:
                    self?.isConnected = false
                    print("⚠️ iCloud account restricted or undetermined")
                default:
                    self?.isConnected = false
                }
            }
        }
    }
    
    // MARK: - Connect to Macok 
    func connectToMac(deviceID: String) {
        self.targetDeviceID = deviceID
        self.isConnected = true  // Set connected status
        print("🔗 Connected to Mac device: \(deviceID)")
        
        // Start listening for responses
        Task {
            await setupResponseSubscription()
        }
    }
    
    // MARK: - Setup Response Subscription
    
    private func setupResponseSubscription() async {
        print("📡 Setting up CloudKit subscription for AIResponse records")
        print("📡 Record type: \(CloudKitRelayConfig.responseRecordType)")
        print("📡 Subscription ID: \(CloudKitRelayConfig.responseSubscriptionID)")
        
        // Subscribe to responses for requests we sent
        let predicate = NSPredicate(value: true) // We'll filter by requestID locally
        
        let subscription = CKQuerySubscription(
            recordType: CloudKitRelayConfig.responseRecordType,
            predicate: predicate,
            subscriptionID: CloudKitRelayConfig.responseSubscriptionID,
            options: [.firesOnRecordCreation]
        )
        
        // Configure notification
        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true
        subscription.notificationInfo = notificationInfo
        
        do {
            let _ = try await privateDB.save(subscription)
            print("✅ CloudKit subscription created for responses")
            print("✅ Subscription record type: \(subscription.recordType ?? "nil")")
            print("✅ Subscription ID: \(subscription.subscriptionID)")
        } catch {
            if let ckError = error as? CKError {
                switch ckError.code {
                case .serverRejectedRequest:
                    print("⚠️ Response subscription already exists - this is normal")
                case .unknownItem:
                    print("📝 CloudKit schema will be created automatically on first record save")
                default:
                    print("❌ Failed to create response subscription: \(error)")
                }
            } else {
                print("❌ Failed to create response subscription: \(error)")
            }
        }
    }
    
    // MARK: - Send Request
    
    func sendRequest(
        serviceID: String,
        serviceName: String,
        endpoint: String,
        method: String = "POST",
        headers: [String: String] = [:],
        body: Data? = nil
    ) async throws -> AIResponse {
        
        guard let deviceID = targetDeviceID else {
            throw RelayError.notConnected
        }
        
        // Create request
        let request = AIRequest(
            serviceID: serviceID,
            serviceName: serviceName,
            endpoint: endpoint,
            method: method,
            headers: headers,
            body: body,
            deviceID: deviceID
        )
        
        // Store pending request
        await MainActor.run {
            pendingRequests[request.id] = request
        }
        
        print("📤 Sending request \(request.id) to service: \(serviceName)")
        
        // Save to CloudKit
        let record = CKRecord(aiRequest: request)
        
        do {
            let _ = try await privateDB.save(record)
            print("✅ Request saved to CloudKit")
        } catch {
            if let ckError = error as? CKError, ckError.code == .unknownItem {
                print("📝 Creating CloudKit request schema on first save...")
                // Try again - CloudKit should auto-create schema
                do {
                    let _ = try await privateDB.save(record)
                    print("✅ Request saved (schema created)")
                } catch {
                    await MainActor.run {
                        _ = pendingRequests.removeValue(forKey: request.id)
                    }
                    throw RelayError.failedToSendRequest(error)
                }
            } else {
                await MainActor.run {
                    _ = pendingRequests.removeValue(forKey: request.id)
                }
                throw RelayError.failedToSendRequest(error)
            }
        }
        
        // Wait for response with timeout (5 minutes should be enough for tool execution)
        return try await waitForResponse(requestID: request.id, timeout: 300)
    }
    
    // MARK: - Wait for Response
    
    private func waitForResponse(requestID: String, timeout: TimeInterval) async throws -> AIResponse {
        return try await withCheckedThrowingContinuation { continuation in
            // Store callback for push notifications
            responseCallbacks[requestID] = { result in
                continuation.resume(with: result)
            }
            
            // Start polling for response (handles its own timeout)
            Task {
                await self.pollForResponse(requestID: requestID)
            }
        }
    }
    
    // MARK: - Poll for Response
    
    private func pollForResponse(requestID: String) async {
        var attempts = 0
        let maxAttempts = 60 // Poll for up to 5 minutes (5 second intervals)
        
        print("📡 Starting to poll for response: \(requestID)")
        
        while attempts < maxAttempts {
            // Check if callback still exists (not completed by push notification)
            guard responseCallbacks[requestID] != nil else { 
                print("📡 Polling stopped - response already received for \(requestID)")
                return // Response was handled by push notification
            }
            
            print("📡 Polling attempt \(attempts + 1)/\(maxAttempts) for response: \(requestID)")
            
            // Query for response
            let predicate = NSPredicate(format: "requestID == %@", requestID)
            let query = CKQuery(
                recordType: CloudKitRelayConfig.responseRecordType,
                predicate: predicate
            )
            
            do {
                let results = try await privateDB.records(matching: query)
                
                print("📡 Found \(results.matchResults.count) potential response records")
                
                if let (_, result) = results.matchResults.first,
                   case .success(let record) = result,
                   let response = record.toAIResponse() {
                    
                    print("✅ Received response for request: \(requestID)")
                    print("✅ Response status: \(response.statusCode), body size: \(response.body?.count ?? 0) bytes")
                    
                    // Call the callback
                    if let callback = responseCallbacks.removeValue(forKey: requestID) {
                        callback(.success(response))
                    }
                    
                    // Update statistics
                    await updateStatistics(success: true, processingTime: response.processingTime)
                    
                    // Clean up pending request
                    await MainActor.run {
                        self.pendingRequests.removeValue(forKey: requestID)
                        self.lastResponseTime = Date()
                    }
                    
                    return
                } else if !results.matchResults.isEmpty {
                    for (recordID, result) in results.matchResults {
                        switch result {
                        case .success(_):
                            print("📡 Found record but failed to parse: \(recordID.recordName)")
                        case .failure(let error):
                            print("📡 Found record with error: \(error)")
                        }
                    }
                }
            } catch {
                if let ckError = error as? CKError, ckError.code == .unknownItem {
                    print("📝 No responses found yet - waiting for Mac to process request")
                } else {
                    print("❌ Failed to query for response: \(error)")
                }
            }
            
            // Wait before next poll
            try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
            attempts += 1
        }
        
        print("⏰ Polling timeout after \(attempts) attempts for request: \(requestID)")
        
        // Handle timeout - remove callback and resume with error
        if let callback = responseCallbacks.removeValue(forKey: requestID) {
            callback(.failure(RelayError.timeout))
            
            // Clean up pending request
            await MainActor.run {
                _ = self.pendingRequests.removeValue(forKey: requestID)
            }
        }
    }
    
    // MARK: - Handle Push Notification
    
    func handleRemoteNotification(_ userInfo: [AnyHashable: Any]) {
        print("📬 CloudKitRelayClient: Received CloudKit notification")
        print("📬 Notification userInfo: \(userInfo)")
        
        // Extract record ID from notification
        if let ckNotification = CKNotification(fromRemoteNotificationDictionary: userInfo) {
            print("📬 CKNotification type: \(type(of: ckNotification))")
            print("📬 CKNotification ID: \(ckNotification.notificationID?.description ?? "nil")")
            
            if let queryNotification = ckNotification as? CKQueryNotification {
                print("📬 Query notification subscription ID: \(queryNotification.subscriptionID ?? "nil")")
                print("📬 Query notification reason: \(queryNotification.queryNotificationReason.rawValue)")
                
                if let recordID = queryNotification.recordID {
                    print("📬 Record ID: \(recordID.recordName)")
                    print("📬 Starting fetchResponse task for record: \(recordID.recordName)")
                    Task {
                        print("📬 Inside Task - calling fetchResponse for: \(recordID.recordName)")
                        await fetchResponse(recordID)
                        print("📬 Completed fetchResponse for: \(recordID.recordName)")
                    }
                } else {
                    print("📬 No record ID in query notification")
                }
            } else {
                print("📬 Not a query notification")
            }
        } else {
            print("📬 Failed to create CKNotification from userInfo")
        }
    }
    
    // MARK: - Fetch Response
    
    private func fetchResponse(_ recordID: CKRecord.ID) async {
        print("🔍 fetchResponse called for record: \(recordID.recordName)")
        do {
            print("🔍 Fetching record from CloudKit...")
            let record = try await privateDB.record(for: recordID)
            print("🔍 Record fetched successfully, type: \(record.recordType)")
            
            // Check if this is actually a response record
            guard record.recordType == CloudKitRelayConfig.responseRecordType else {
                print("📝 Ignoring non-response record: \(record.recordType)")
                return
            }
            
            guard let response = record.toAIResponse() else {
                print("❌ Failed to parse response record")
                return
            }
            
            // Check if we have a callback waiting for this response
            print("🔍 Checking for callback for request ID: \(response.requestID)")
            if let callback = responseCallbacks.removeValue(forKey: response.requestID) {
                print("✅ Found callback for request ID: \(response.requestID)")
                callback(.success(response))
                
                await updateStatistics(success: true, processingTime: response.processingTime)
                
                await MainActor.run {
                    self.pendingRequests.removeValue(forKey: response.requestID)
                    self.lastResponseTime = Date()
                }
                print("✅ Response delivered successfully for request: \(response.requestID)")
            } else {
                print("⚠️ No callback found for request ID: \(response.requestID)")
                print("⚠️ Available callbacks: \(responseCallbacks.keys)")
            }
        } catch {
            print("❌ Failed to fetch response record: \(error)")
        }
    }
    
    // MARK: - Update Statistics
    
    @MainActor
    private func updateStatistics(success: Bool, processingTime: TimeInterval) {
        let total = statistics.totalRequests + 1
        let successful = statistics.successfulRequests + (success ? 1 : 0)
        let failed = statistics.failedRequests + (success ? 0 : 1)
        
        // Calculate new average
        let totalTime = statistics.averageProcessingTime * Double(statistics.totalRequests)
        let newAverage = (totalTime + processingTime) / Double(total)
        
        statistics = RelayStatistics(
            totalRequests: total,
            successfulRequests: successful,
            failedRequests: failed,
            averageProcessingTime: newAverage,
            lastRequestTime: Date()
        )
    }
    
    // MARK: - Cancel Request
    
    func cancelRequest(_ requestID: String) {
        responseCallbacks.removeValue(forKey: requestID)
        pendingRequests.removeValue(forKey: requestID)
        
        // Update request status in CloudKit
        Task {
            let recordID = CKRecord.ID(recordName: requestID)
            do {
                let record = try await privateDB.record(for: recordID)
                record["status"] = RequestStatus.cancelled.rawValue
                try await privateDB.save(record)
            } catch {
                print("❌ Failed to cancel request: \(error)")
            }
        }
    }
    
    // MARK: - Clear All Pending
    
    func clearAllPending() {
        responseCallbacks.removeAll()
        pendingRequests.removeAll()
    }
    
    // MARK: - Disconnect
    
    func disconnect() {
        targetDeviceID = nil
        clearAllPending()
        isConnected = false
    }
    
    // MARK: - Cleanup Old Records
    
    func cleanupOldRecords(olderThan hours: Int = 24) async {
        let cutoffDate = Date().addingTimeInterval(-Double(hours * 3600))
        
        // Clean up old requests we created
        let requestPredicate = NSPredicate(
            format: "timestamp < %@",
            cutoffDate as NSDate
        )
        
        let requestQuery = CKQuery(
            recordType: CloudKitRelayConfig.requestRecordType,
            predicate: requestPredicate
        )
        
        // Clean up old responses we received
        let responseQuery = CKQuery(
            recordType: CloudKitRelayConfig.responseRecordType,
            predicate: requestPredicate
        )
        
        do {
            // Delete old requests
            let requestResults = try await privateDB.records(matching: requestQuery)
            for (recordID, _) in requestResults.matchResults {
                _ = try? await privateDB.deleteRecord(withID: recordID)
            }
            
            // Delete old responses
            let responseResults = try await privateDB.records(matching: responseQuery)
            for (recordID, _) in responseResults.matchResults {
                _ = try? await privateDB.deleteRecord(withID: recordID)
            }
            
            let totalDeleted = requestResults.matchResults.count + responseResults.matchResults.count
            if totalDeleted > 0 {
                print("🧹 Cleaned up \(totalDeleted) old records")
            }
        } catch {
            if let ckError = error as? CKError, ckError.code == .unknownItem {
                print("📝 No old records to cleanup (normal on first run)")
            } else {
                print("❌ Failed to cleanup records: \(error)")
            }
        }
    }
}

// MARK: - Relay Errors
enum RelayError: LocalizedError {
    case notConnected
    case timeout
    case failedToSendRequest(Error)
    case invalidResponse
    
    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to Mac device"
        case .timeout:
            return "Request timed out"
        case .failedToSendRequest(let error):
            return "Failed to send request: \(error.localizedDescription)"
        case .invalidResponse:
            return "Received invalid response"
        }
    }
}
