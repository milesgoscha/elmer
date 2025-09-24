//
//  CloudKitRelayManager.swift
//  elmer (Mac)
//
//  Manages CloudKit relay on Mac side - listens for requests and sends responses
//

import Foundation
import CloudKit
import Combine

@MainActor
final class CloudKitRelayManager: ObservableObject {
    @Published var isListening = false
    @Published var requestsProcessed = 0
    @Published var lastRequestTime: Date?
    @Published var statistics = RelayStatistics(
        totalRequests: 0,
        successfulRequests: 0,
        failedRequests: 0,
        averageProcessingTime: 0,
        lastRequestTime: nil
    )
    
    private let deviceID: String
    private let container = CloudKitRelayConfig.container
    private let privateDB = CloudKitRelayConfig.privateDB
    private var requestSubscription: CKQuerySubscription?
    private var activeRequests: Set<String> = []
    private var announcementTimer: Timer?
    private var pollingTimer: Timer?
    
    // Reference to ServiceManager for making local API calls
    weak var serviceManager: ServiceManager?
    
    init(serviceManager: ServiceManager? = nil) {
        self.deviceID = DeviceIdentityManager.getOrCreateDeviceID()
        self.serviceManager = serviceManager
        
        print("🎧 CloudKit Relay Manager initialized with device ID: \(deviceID)")
    }
    
    // MARK: - Start Listening
    
    func startListening() {
        guard !isListening else { return }
        
        Task {
            await setupSubscription()
            await cleanupStalePendingRequests() // Clean stale requests first
            await processExistingRequests()
            
            isListening = true
            
            print("✅ CloudKit Relay listening for requests")
            print("📝 Note: \"Unknown Item\" errors are normal on first run - CloudKit will auto-create schema")
            
            // Start announcing this device
            await startAnnouncingDevice()
            
            // Start polling for requests every 5 seconds as backup
            await startPollingForRequests()
        }
    }
    
    // MARK: - Setup Push Notification Subscription
    
    private func setupSubscription() async {
        // Create subscription for requests targeting this device
        let predicate = NSPredicate(format: "deviceID == %@", deviceID)
        
        let subscription = CKQuerySubscription(
            recordType: CloudKitRelayConfig.requestRecordType,
            predicate: predicate,
            subscriptionID: CloudKitRelayConfig.requestSubscriptionID,
            options: [.firesOnRecordCreation, .firesOnRecordUpdate]
        )
        
        // Configure notification
        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true
        notificationInfo.alertBody = "New AI request received"
        subscription.notificationInfo = notificationInfo
        
        do {
            let _ = try await privateDB.save(subscription)
            print("✅ CloudKit subscription created for incoming requests")
        } catch {
            if let ckError = error as? CKError {
                switch ckError.code {
                case .serverRejectedRequest:
                    print("⚠️ Request subscription already exists")
                case .unknownItem:
                    print("📝 CloudKit schema will be created automatically on first record save")
                default:
                    print("❌ Failed to create subscription: \(error)")
                }
            } else {
                print("❌ Failed to create subscription: \(error)")
            }
        }
    }
    
    // MARK: - Process Existing Requests
    
    private func processExistingRequests() async {
        // Query for pending requests for this device
        let predicate = NSPredicate(
            format: "deviceID == %@ AND status == %@", 
            deviceID, 
            RequestStatus.pending.rawValue
        )
        
        let query = CKQuery(
            recordType: CloudKitRelayConfig.requestRecordType, 
            predicate: predicate
        )
        query.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: true)]
        
        do {
            let results = try await privateDB.records(matching: query)
            
            for (_, result) in results.matchResults {
                if case .success(let record) = result {
                    await processRequest(record)
                }
            }
            
            print("✅ Processed \(results.matchResults.count) existing requests")
        } catch {
            if let ckError = error as? CKError, ckError.code == .unknownItem {
                print("📝 No existing requests found - CloudKit schema will be created on first use")
            } else {
                print("❌ Failed to query existing requests: \(error)")
            }
        }
    }
    
    // MARK: - Handle Push Notification
    
    func handleRemoteNotification(_ userInfo: [AnyHashable: Any]) {
        print("📬 Received CloudKit notification for new request")
        
        // Extract record ID from notification
        if let ckNotification = CKNotification(fromRemoteNotificationDictionary: userInfo),
           let queryNotification = ckNotification as? CKQueryNotification,
           let recordID = queryNotification.recordID {
            
            Task {
                await fetchAndProcessRequest(recordID)
            }
        }
    }
    
    // MARK: - Fetch and Process Request
    
    private func fetchAndProcessRequest(_ recordID: CKRecord.ID) async {
        do {
            let record = try await privateDB.record(for: recordID)
            await processRequest(record)
        } catch {
            print("❌ Failed to fetch request record: \(error)")
        }
    }
    
    // MARK: - Tool Support
    
    private func shouldAddToolsToRequest(_ request: AIRequest) -> Bool {
        // Check if this is a language model service with OpenAI API format
        guard let serviceManager = serviceManager else { return false }
        
        let availableServices = serviceManager.visibleServices
        guard let service = availableServices.first(where: { $0.id.uuidString == request.serviceID }) else {
            return false
        }
        
        // Only add tools to OpenAI-compatible language model services
        return service.type == .languageModel && service.apiFormat == .openai
    }
    
    private func addToolsToRequestBody(_ originalBody: Data?) -> Data? {
        guard let originalBody = originalBody else { return nil }
        
        do {
            // Parse existing request JSON
            guard let json = try JSONSerialization.jsonObject(with: originalBody) as? [String: Any] else {
                return originalBody
            }
            
            var modifiedJson = json
            
            // Add user-defined tools to the request
            let userTools = UserToolManager.shared.availableTools
            if !userTools.isEmpty {
                modifiedJson["tools"] = userTools
                modifiedJson["tool_choice"] = "auto"
                
                // Debug: Show what tools are available  
                let mcpToolCount = UserToolManager.shared.mcpToolCount
                let jsonToolCount = userTools.count - mcpToolCount // Calculate JSON tools
                print("🔧 JSON tools loaded: \(jsonToolCount)")
                print("🔧 MCP tools available: \(mcpToolCount)")
                print("🔧 Total tools loaded: \(userTools.count)")
                
                // List MCP tools specifically
                if mcpToolCount > 0 {
                    let mcpTools = MCPServerManager.shared.availableTools
                    print("🔧 MCP tools: \(mcpTools.map { "mcp__\($0.serverName)__\($0.name)" }.joined(separator: ", "))")
                }
                
                // List running MCP servers
                let runningServers = MCPServerManager.shared.runningServers
                if !runningServers.isEmpty {
                    print("🔧 Running MCP servers: \(runningServers.joined(separator: ", "))")
                } else {
                    print("⚠️ No MCP servers are running!")
                }
                
                print("🔧 Added \(userTools.count) tools (JSON + MCP) to request")
            }
            
            // Convert back to JSON
            return try JSONSerialization.data(withJSONObject: modifiedJson)
        } catch {
            print("⚠️ Failed to add tools to request: \(error)")
            return originalBody
        }
    }
    
    private func handleToolCallsInResponse(_ responseBody: Data, for request: AIRequest, with service: AIService, startTime: Date) async throws -> Data {
        do {
            guard let json = try JSONSerialization.jsonObject(with: responseBody) as? [String: Any] else {
                return responseBody  // No tool calls, return original response
            }
            
            // Check if response contains tool calls
            if let choices = json["choices"] as? [[String: Any]],
               let firstChoice = choices.first,
               let message = firstChoice["message"] as? [String: Any],
               let toolCalls = message["tool_calls"] as? [[String: Any]] {
                
                print("🔧 Executing \(toolCalls.count) tool calls")
                
                // Execute tools and collect results
                var toolResults: [[String: Any]] = []
                for toolCall in toolCalls {
                    // Always get a result, even if it's an error
                    let toolResult = await executeToolCall(toolCall) ?? [
                        "tool_call_id": toolCall["id"] as? String ?? "unknown",
                        "role": "tool",
                        "content": "Tool execution failed - no result returned"
                    ]
                    toolResults.append(toolResult)
                }
                
                // Create follow-up request with tool results
                return try await sendFollowUpWithToolResults(
                    originalRequest: request, 
                    toolCalls: toolCalls, 
                    toolResults: toolResults, 
                    service: service,
                    startTime: startTime
                )
            }
            
            return responseBody  // No tool calls, return original response
            
        } catch {
            print("❌ Error handling tool calls: \(error)")
            return responseBody  // Return original response on error
        }
    }
    
    
    private func executeToolCall(_ toolCall: [String: Any]) async -> [String: Any]? {
        guard let id = toolCall["id"] as? String,
              let function = toolCall["function"] as? [String: Any],
              let name = function["name"] as? String,
              let argumentsString = function["arguments"] as? String else {
            print("❌ Invalid tool call format")
            return nil
        }
        
        // Parse arguments
        guard let argumentsData = argumentsString.data(using: .utf8),
              let arguments = try? JSONSerialization.jsonObject(with: argumentsData) as? [String: Any] else {
            print("❌ Failed to parse tool arguments")
            return nil
        }
        
        do {
            let result = try await UserToolManager.shared.executeTool(name: name, arguments: arguments)
            
            return [
                "tool_call_id": id,
                "role": "tool", 
                "content": result
            ]
        } catch {
            print("❌ Tool execution failed: \(error)")
            return [
                "tool_call_id": id,
                "role": "tool",
                "content": "Error executing \(name): \(error.localizedDescription)"
            ]
        }
    }
    
    private func sendFollowUpWithToolResults(
        originalRequest: AIRequest,
        toolCalls: [[String: Any]], 
        toolResults: [[String: Any]],
        service: AIService,
        startTime: Date
    ) async throws -> Data {
        print("🔄 Starting follow-up request with \(toolResults.count) tool results")
        print("🔄 Tool results: \(toolResults)")
        // Parse original request to get messages
        guard let originalBody = originalRequest.body,
              let originalJson = try JSONSerialization.jsonObject(with: originalBody) as? [String: Any],
              let messages = originalJson["messages"] as? [[String: Any]] else {
            throw NSError(domain: "ToolError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not parse original messages"])
        }
        
        // Build new messages array with tool call and results
        var newMessages = messages
        
        // Add assistant message with tool calls
        newMessages.append([
            "role": "assistant",
            "content": NSNull(),
            "tool_calls": toolCalls
        ] as [String: Any])
        
        // Add tool result messages
        for toolResult in toolResults {
            newMessages.append(toolResult)
        }
        
        // Create new request body
        var newRequestBody = originalJson
        newRequestBody["messages"] = newMessages
        // Remove tools from follow-up request to avoid infinite loops
        newRequestBody.removeValue(forKey: "tools")
        newRequestBody.removeValue(forKey: "tool_choice")
        
        let requestData = try JSONSerialization.data(withJSONObject: newRequestBody)
        
        print("🔄 Sending follow-up request to LLM with tool results...")
        
        // Make follow-up request to service
        let baseURL: String
        if let customURL = service.customName, customURL.hasPrefix("http") {
            baseURL = customURL
        } else {
            baseURL = "http://localhost:\(service.localPort)"
        }
        let serviceURL = "\(baseURL)\(originalRequest.endpoint)"
        
        guard let url = URL(string: serviceURL) else {
            throw URLError(.badURL)
        }
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = originalRequest.method
        urlRequest.httpBody = requestData
        
        // Set headers
        for (key, value) in originalRequest.headers {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }
        
        urlRequest.timeoutInterval = 300
        
        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        
        if let httpResponse = response as? HTTPURLResponse {
            print("🔄 Follow-up request completed with status: \(httpResponse.statusCode)")
        }
        
        print("🔄 Follow-up response size: \(data.count) bytes")
        return data
    }
    
    // MARK: - Process Request
    
    private func processRequest(_ record: CKRecord) async {
        // Only process AIRequest records, skip other types like Conversation
        guard record.recordType == CloudKitRelayConfig.requestRecordType else {
            print("⚠️ Skipping non-request record type: \(record.recordType)")
            return
        }
        
        guard let request = record.toAIRequest() else {
            print("❌ Failed to parse request record")
            return
        }
        
        print("📥 Processing request for \(request.serviceName)")
        
        // Check if this request is for us
        guard request.deviceID == deviceID else {
            print("⚠️ Request is for different device: \(request.deviceID)")
            return
        }
        
        // Avoid processing the same request multiple times
        guard !activeRequests.contains(request.id) else {
            print("⚠️ Request \(request.id) already being processed")
            return
        }
        
        activeRequests.insert(request.id)
        let startTime = Date()
        
        
        // Update request status to processing
        record["status"] = RequestStatus.processing.rawValue
        do {
            try await privateDB.save(record)
        } catch {
            if let ckError = error as? CKError, ckError.code == .unknownItem {
                print("📝 Creating CloudKit request schema...")
            } else {
                print("⚠️ Failed to update request status: \(error)")
            }
        }
        
        // Find the service (use visibleServices to respect hidden services)
        let availableServices = serviceManager?.visibleServices ?? []
        
        guard let service = availableServices.first(where: { $0.id.uuidString == request.serviceID }) else {
            print("❌ Service not found for request")
            await sendErrorResponse(for: request, error: "Service not found")
            activeRequests.remove(request.id)
            return
        }
        
        // Build the URL - use baseURL for remote services, localhost for local services  
        let baseURL: String
        if let customURL = service.customName, customURL.hasPrefix("http") {
            // Remote service - use the full URL stored in customName
            baseURL = customURL
        } else {
            // Local service - use localhost with the port
            baseURL = "http://localhost:\(service.localPort)"
        }
        let serviceURL = "\(baseURL)\(request.endpoint)"
        
        do {
            // Make the API call (local or remote)
            guard let url = URL(string: serviceURL) else {
                throw URLError(.badURL)
            }
            
            var urlRequest = URLRequest(url: url)
            urlRequest.httpMethod = request.method
            
            // Add tools to request if applicable
            let requestBody = shouldAddToolsToRequest(request) ? addToolsToRequestBody(request.body) : request.body
            urlRequest.httpBody = requestBody
            
            // Set headers
            for (key, value) in request.headers {
                urlRequest.setValue(value, forHTTPHeaderField: key)
            }
            
            // Increase timeout for AI requests
            urlRequest.timeoutInterval = 300 // 5 minutes
            
            let (data, response) = try await URLSession.shared.data(for: urlRequest)
            
            let httpResponse = response as? HTTPURLResponse
            let statusCode = httpResponse?.statusCode ?? 200
            
            // Extract response headers
            var responseHeaders: [String: String] = [:]
            if let headerFields = httpResponse?.allHeaderFields as? [String: String] {
                responseHeaders = headerFields
            }
            
            let processingTime = Date().timeIntervalSince(startTime)
            
            // Log response details for debugging
            if statusCode >= 400 {
                print("❌ Service returned error \(statusCode)")
                if let errorString = String(data: data, encoding: .utf8) {
                    print("❌ Error details: \(errorString)")
                }
            }
            
            // Handle tool calls in response if applicable
            let finalResponseData: Data
            do {
                finalResponseData = try await handleToolCallsInResponse(data, for: request, with: service, startTime: startTime)
            } catch {
                print("❌ Tool handling failed, returning original response: \(error)")
                // If tool handling fails, return the original response so iOS still gets something
                finalResponseData = data
            }
            
            
            // Create and save response with final data
            let aiResponse = AIResponse(
                requestID: request.id,
                statusCode: statusCode,
                headers: responseHeaders,
                body: finalResponseData,
                processingTime: processingTime
            )
            
            print("📤 Created AIResponse for request \(request.id) with status \(statusCode)")
            await saveResponse(aiResponse)
            
            // Update request status
            record["status"] = RequestStatus.completed.rawValue
            do {
                try await privateDB.save(record)
            } catch {
                print("⚠️ Failed to update request status to completed: \(error)")
            }
            
            // Update statistics
            updateStatistics(success: true, processingTime: processingTime)
            
            print("✅ Request completed for \(request.serviceName) in \(String(format: "%.2f", processingTime))s")
            
        } catch {
            print("❌ Request failed: \(error)")
            let processingTime = Date().timeIntervalSince(startTime)
            await sendErrorResponse(for: request, error: error.localizedDescription, processingTime: processingTime)
            
            // Update request status
            record["status"] = RequestStatus.failed.rawValue
            do {
                try await privateDB.save(record)
            } catch {
                print("⚠️ Failed to update request status to failed: \(error)")
            }
            
            updateStatistics(success: false, processingTime: processingTime)
        }
        
        activeRequests.remove(request.id)
    }
    
    // MARK: - Save Response
    
    private func saveResponse(_ response: AIResponse) async {
        let record = CKRecord(aiResponse: response)
        
        print("💾 Saving AIResponse record with ID: \(response.id) for request: \(response.requestID)")
        print("💾 Record type: \(record.recordType)")
        
        do {
            let _ = try await privateDB.save(record)
            print("✅ Successfully saved AIResponse record: \(response.id)")
        } catch {
            if let ckError = error as? CKError, ckError.code == .unknownItem {
                print("📝 Creating CloudKit response schema on first save...")
                // Try again - CloudKit should auto-create schema
                do {
                    let _ = try await privateDB.save(record)
                    print("✅ Successfully saved AIResponse record after schema creation: \(response.id)")
                } catch {
                    print("❌ Failed to save response after schema creation: \(error)")
                }
            } else {
                print("❌ Failed to save response: \(error)")
            }
        }
    }
    
    // MARK: - Send Error Response
    
    private func sendErrorResponse(for request: AIRequest, error: String, processingTime: TimeInterval = 0) async {
        let response = AIResponse(
            requestID: request.id,
            statusCode: 500,
            headers: ["Content-Type": "text/plain"],
            body: error.data(using: .utf8),
            error: error,
            processingTime: processingTime
        )
        
        await saveResponse(response)
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
        
        requestsProcessed = total
        lastRequestTime = Date()
    }
    
    // MARK: - Stop Listening
    
    func stopListening() {
        isListening = false
        
        // Remove subscription
        if let subscriptionID = requestSubscription?.subscriptionID {
            privateDB.delete(withSubscriptionID: subscriptionID) { _, error in
                if let error = error {
                    print("❌ Failed to delete subscription: \(error)")
                }
            }
        }
        
        print("🛑 CloudKit Relay stopped listening")
    }
    
    // MARK: - Cleanup Old Records
    
    func cleanupOldRecords(olderThan hours: Int = 24) async {
        let cutoffDate = Date().addingTimeInterval(-Double(hours * 3600))
        
        // Clean up old requests
        let requestPredicate = NSPredicate(
            format: "timestamp < %@ AND status != %@",
            cutoffDate as NSDate,
            RequestStatus.pending.rawValue
        )
        
        await deleteRecords(
            ofType: CloudKitRelayConfig.requestRecordType,
            matching: requestPredicate
        )
        
        // Clean up old responses
        let responsePredicate = NSPredicate(
            format: "timestamp < %@",
            cutoffDate as NSDate
        )
        
        await deleteRecords(
            ofType: CloudKitRelayConfig.responseRecordType,
            matching: responsePredicate
        )
    }
    
    // Clean up stale pending requests (for service ID mismatches)
    func cleanupStalePendingRequests() async {
        // Get current service IDs
        let currentServiceIDs = Set(serviceManager?.services.map { $0.id.uuidString } ?? [])
        
        // Query all pending requests
        let predicate = NSPredicate(
            format: "deviceID == %@ AND status == %@",
            deviceID,
            RequestStatus.pending.rawValue
        )
        
        let query = CKQuery(
            recordType: CloudKitRelayConfig.requestRecordType,
            predicate: predicate
        )
        
        do {
            let results = try await privateDB.records(matching: query)
            var cleanedCount = 0
            
            for (recordID, result) in results.matchResults {
                if case .success(let record) = result,
                   let request = record.toAIRequest() {
                    
                    // Check if this request's service ID is stale
                    if !currentServiceIDs.contains(request.serviceID) {
                        do {
                            try await privateDB.deleteRecord(withID: recordID)
                            cleanedCount += 1
                        } catch {
                            print("⚠️ Failed to delete stale request: \(error)")
                        }
                    }
                }
            }
            
            if cleanedCount > 0 {
                print("🧹 Cleaned up \(cleanedCount) stale requests")
            }
            
        } catch {
            if let ckError = error as? CKError, ckError.code == .unknownItem {
                print("📝 No pending requests found (normal)")
            } else {
                print("❌ Failed to query pending requests: \(error)")
            }
        }
    }
    
    private func deleteRecords(ofType recordType: String, matching predicate: NSPredicate) async {
        let query = CKQuery(recordType: recordType, predicate: predicate)
        
        do {
            let results = try await privateDB.records(matching: query)
            var deletedCount = 0
            
            for (recordID, _) in results.matchResults {
                do {
                    try await privateDB.deleteRecord(withID: recordID)
                    deletedCount += 1
                } catch {
                    print("⚠️ Failed to delete record \(recordID): \(error)")
                }
            }
            
            if deletedCount > 0 {
                print("🧹 Cleaned up \(deletedCount) old records")
            }
        } catch {
            if let ckError = error as? CKError, ckError.code == .unknownItem {
                // This is expected when no records exist yet
                print("📝 No \(recordType) records to cleanup (normal on first run)")
            } else {
                print("❌ Failed to cleanup records: \(error)")
            }
        }
    }
    
    // MARK: - Automatic Cleanup Timer
    
    func startAutomaticCleanup(intervalHours: Int = 6) {
        Timer.scheduledTimer(withTimeInterval: Double(intervalHours * 3600), repeats: true) { _ in
            Task {
                await self.cleanupOldRecords(olderThan: 24)
            }
        }
        
        // Run initial cleanup
        Task {
            await cleanupOldRecords(olderThan: 24)
        }
    }
    
    // MARK: - Polling for Requests (Backup)
    
    func startPollingForRequests() async {
        pollingTimer?.invalidate()
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            Task {
                await self.processExistingRequests()
            }
        }
    }
    
    func stopPollingForRequests() {
        pollingTimer?.invalidate()
        pollingTimer = nil
    }
    
    // MARK: - Device Announcement for Auto-Discovery
    
    func startAnnouncingDevice() async {
        // Announce immediately
        await announceDevice()
        
        // Schedule periodic announcements every 30 seconds
        announcementTimer?.invalidate()
        announcementTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { _ in
            Task {
                await self.announceDevice()
            }
        }
    }
    
    func stopAnnouncingDevice() {
        announcementTimer?.invalidate()
        announcementTimer = nil
        
        // Mark device as inactive
        Task {
            await markDeviceInactive()
        }
    }
    
    func announceDevice() async {
        guard let serviceManager = serviceManager else { return }
        
        // Discover ComfyUI workflows from filesystem
        let discoveredWorkflows = ServiceDetector.findComfyUIWorkflows()
        
        // Get imported workflows from WorkflowManager
        let importedWorkflows = await getImportedWorkflows()
        
        // Combine discovered and imported workflows
        let allWorkflows = discoveredWorkflows + importedWorkflows
        
        // Convert services to QRServiceInfo format - only include running and visible services
        let services = serviceManager.visibleServices
            .filter { $0.isRunning }
            .map { service in
                // Include workflows for ComfyUI services
                let workflows = (service.apiFormat == .comfyui || service.type == .imageGeneration) ? allWorkflows : nil
                
                return QRServiceInfo(
                    id: service.id.uuidString,
                    name: service.name,
                    type: service.type.rawValue,
                    port: service.localPort,
                    apiFormat: service.apiFormat.rawValue,
                    isRunning: service.isRunning,
                    workflows: workflows,
                    baseURL: service.customName // For remote services, customName contains the full URL
                )
            }
        
        let announcement = DeviceAnnouncement(
            deviceID: deviceID,
            deviceName: DeviceIdentityManager.getDeviceName(),
            deviceType: "mac",
            services: services
        )
        
        // Try to fetch existing record first
        let recordID = CKRecord.ID(recordName: deviceID)
        
        do {
            // Try to fetch existing record
            if let existingRecord = try? await privateDB.record(for: recordID) {
                // Update existing record
                existingRecord["deviceName"] = announcement.deviceName
                existingRecord["deviceType"] = announcement.deviceType
                existingRecord["lastSeen"] = announcement.lastSeen
                existingRecord["isActive"] = 1
                
                // Update services
                if let servicesData = try? JSONEncoder().encode(announcement.services),
                   let servicesString = String(data: servicesData, encoding: .utf8) {
                    existingRecord["services"] = servicesString
                }
                
                _ = try await privateDB.save(existingRecord)
            } else {
                // Create new record
                let record = CKRecord(deviceAnnouncement: announcement)
                _ = try await privateDB.save(record)
            }
        } catch {
            if let ckError = error as? CKError {
                switch ckError.code {
                case .unknownItem:
                    print("📝 Device announcement schema will be created on first save")
                case .serverRecordChanged:
                    // Record exists but was modified, try updating
                    await announceDevice() // Retry once
                default:
                    print("❌ Failed to announce device: \(error)")
                }
            } else {
                print("❌ Failed to announce device: \(error)")
            }
        }
    }
    
    private func markDeviceInactive() async {
        let recordID = CKRecord.ID(recordName: deviceID)
        
        do {
            let record = try await privateDB.record(for: recordID)
            record["isActive"] = 0
            record["lastSeen"] = Date()
            _ = try await privateDB.save(record)
        } catch {
            print("⚠️ Failed to mark device inactive: \(error)")
        }
    }
    
    // MARK: - Helper Methods
    
    @MainActor
    private func getImportedWorkflows() async -> [ComfyUIWorkflow] {
        let importedWorkflows = WorkflowManager.shared.workflows
        
        return importedWorkflows.map { imported in
            ComfyUIWorkflow(
                id: imported.id,
                name: imported.name,
                filename: imported.filename,
                workflowJSON: imported.workflowJSON
            )
        }
    }
    
    deinit {
        // Clean up timers directly since deinit can't call MainActor methods
        announcementTimer?.invalidate()
        announcementTimer = nil
        pollingTimer?.invalidate()
        pollingTimer = nil
    }
}