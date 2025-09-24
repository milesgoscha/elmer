//
//  CloudKitConversationManager.swift
//  elmer
//
//  Manages conversation storage in CloudKit for cross-device sync
//  and proper handling of large content
//

import Foundation
import CloudKit
import SwiftUI

// MARK: - CloudKit Record Types
extension CloudKitRelayConfig {
    // Permanent storage record types (not cleaned up)
    static let conversationRecordType = "Conversation"
    static let chatMessageRecordType = "ChatMessage"
    static let chatAssetRecordType = "ChatAsset"
}

// MARK: - CloudKit Conversation Manager
class CloudKitConversationManager: ObservableObject {
    @Published var conversations: [Conversation] = []
    @Published var isSyncing = false
    @Published var syncError: Error?
    
    private let database = CloudKitRelayConfig.privateDB
    private let localCache = ConversationCache()
    private var subscriptions: [CKSubscription] = []
    
    // Thresholds for storage decisions
    private let maxRecordFieldSize = 1_000_000 // 1MB - store as field vs CKAsset
    private let maxLocalCacheConversations = 10 // Keep 10 most recent locally
    
    init() {
        setupSubscriptions()
        fetchRecentConversations()
    }
    
    // MARK: - Schema Setup
    
    private func ensureSchemaExists() async {
        // CloudKit record types are automatically created when first record is saved
        // No need to manually create schemas in production
        print("🔧 CloudKit schemas will be created automatically on first save")
    }
    
    // MARK: - Conversation Management
    
    func createConversation(serviceID: String, serviceName: String) -> Conversation {
        let conversation = Conversation(serviceID: serviceID, serviceName: serviceName)
        
        // Update local state immediately on main thread
        DispatchQueue.main.async {
            self.conversations.insert(conversation, at: 0)
            self.updateLocalCache()
        }
        
        // Save to CloudKit asynchronously
        Task {
            await saveConversationToCloudKit(conversation)
        }
        
        return conversation
    }
    
    func addMessage(to conversation: Conversation, message: ChatMessage) async throws {
        var updatedConversation = conversation
        
        // Check if message already exists to prevent duplicates
        if !updatedConversation.messages.contains(where: { $0.id == message.id }) {
            updatedConversation.messages.append(message)
        }
        updatedConversation.updatedAt = Date()
        
        // Save message to CloudKit
        try await saveMessageToCloudKit(message, conversationID: conversation.id.uuidString)
        
        // Update conversation metadata
        await saveConversationToCloudKit(updatedConversation)
        
        // Update local state on main thread
        let conversationToUpdate = updatedConversation
        await MainActor.run {
            if let index = conversations.firstIndex(where: { $0.id == conversation.id }) {
                conversations[index] = conversationToUpdate
            }
            updateLocalCache()
        }
    }
    
    func deleteConversation(_ conversation: Conversation) async {
        // Remove from local list immediately for responsive UI
        await MainActor.run {
            conversations.removeAll { $0.id == conversation.id }
            updateLocalCache()
        }
        
        // Delete from CloudKit
        let recordID = CKRecord.ID(recordName: conversation.id.uuidString)
        
        do {
            try await database.deleteRecord(withID: recordID)
            print("✅ Deleted conversation from CloudKit: \(conversation.id)")
        } catch {
            print("❌ Failed to delete conversation from CloudKit: \(error)")
            // Optionally re-add to local list if delete failed
            await MainActor.run {
                self.syncError = error
            }
        }
        
        // Note: Associated ChatMessage records will be automatically deleted
        // due to the .deleteSelf reference action we set up
    }
    
    // MARK: - CloudKit Operations
    
    private func saveConversationToCloudKit(_ conversation: Conversation) async {
        do {
            // First try to fetch existing record to update it
            let recordID = CKRecord.ID(recordName: conversation.id.uuidString)
            let record: CKRecord
            
            do {
                record = try await database.record(for: recordID)
                print("📝 Updating existing conversation: \(conversation.id)")
            } catch {
                // Record doesn't exist, create new one
                record = CKRecord(recordType: CloudKitRelayConfig.conversationRecordType, recordID: recordID)
                print("📝 Creating new conversation: \(conversation.id)")
            }
            
            // Update record fields
            record["serviceID"] = conversation.serviceID
            record["serviceName"] = conversation.serviceName
            record["createdAt"] = conversation.createdAt
            record["updatedAt"] = conversation.updatedAt
            record["messageCount"] = conversation.messages.count
            
            try await database.save(record)
            print("✅ Saved conversation to CloudKit: \(conversation.id)")
        } catch {
            print("❌ Failed to save conversation: \(error)")
            await MainActor.run {
                self.syncError = error
            }
        }
    }
    
    private func saveMessageToCloudKit(_ message: ChatMessage, conversationID: String) async throws {
        let record = CKRecord(recordType: CloudKitRelayConfig.chatMessageRecordType,
                             recordID: CKRecord.ID(recordName: message.id.uuidString))
        
        // Reference to parent conversation
        let conversationRef = CKRecord.Reference(
            recordID: CKRecord.ID(recordName: conversationID),
            action: .deleteSelf // Delete message if conversation is deleted
        )
        record["conversation"] = conversationRef
        
        // Message metadata
        record["role"] = message.role.rawValue
        record["timestamp"] = message.timestamp
        
        // Handle content based on size
        if let contentData = message.content.data(using: .utf8) {
            if contentData.count < maxRecordFieldSize {
                // Small content - store as field (uses 10GB database quota)
                record["content"] = message.content
                record["storageType"] = "field"
            } else {
                // Large content - store as CKAsset (uses 100MB free, then personal iCloud)
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                try contentData.write(to: tempURL)
                
                let asset = CKAsset(fileURL: tempURL)
                record["contentAsset"] = asset
                record["storageType"] = "asset"
            }
        }
        
        // Handle image data if present
        if let imageData = message.imageData {
            if imageData.count < maxRecordFieldSize {
                // Small image - store as base64 field
                record["imageData"] = imageData.base64EncodedString()
                record["imageStorageType"] = "field"
            } else {
                // Large image - store as CKAsset
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString + ".jpg")
                try imageData.write(to: tempURL)
                
                let asset = CKAsset(fileURL: tempURL)
                record["imageAsset"] = asset
                record["imageStorageType"] = "asset"
                
                // Clean up temp file after CloudKit processes it
                Task.detached {
                    try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
                    try? FileManager.default.removeItem(at: tempURL)
                }
            }
        }
        
        // Store image metadata if present
        if let metadata = message.imageMetadata {
            let metadataData = try JSONEncoder().encode(metadata)
            record["imageMetadata"] = String(data: metadataData, encoding: .utf8)
        }
        
        // Store asset URL if present (for reconstructing from CloudKit)
        if let assetURL = message.imageAssetURL {
            record["imageAssetURL"] = assetURL
        }
        
        try await database.save(record)
        print("✅ Saved message to CloudKit (type: \(record["storageType"] ?? "unknown"))")
    }
    
    // MARK: - Fetching
    
    func fetchRecentConversations() {
        Task {
            await MainActor.run {
                isSyncing = true
            }
            
            do {
                // Fetch conversation metadata from last 30 days
                let thirtyDaysAgo = Date().addingTimeInterval(-30 * 24 * 3600)
                let predicate = NSPredicate(format: "updatedAt > %@", thirtyDaysAgo as NSDate)
                let query = CKQuery(recordType: CloudKitRelayConfig.conversationRecordType,
                                   predicate: predicate)
                query.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]
                
                let results = try await database.records(matching: query)
                
                var fetchedConversations: [Conversation] = []
                
                for (_, result) in results.matchResults {
                    if let record = try? result.get(),
                       let conversation = conversationFromRecord(record) {
                        fetchedConversations.append(conversation)
                    }
                }
                
                let finalConversations = fetchedConversations
                await MainActor.run {
                    self.conversations = finalConversations
                    self.updateLocalCache()
                    self.isSyncing = false
                }
                
                // Fetch messages for recent conversations
                await fetchMessagesForRecentConversations()
                
            } catch {
                if let ckError = error as? CKError, ckError.code == .unknownItem {
                    print("🔧 CloudKit record types don't exist yet - will be created on first save")
                } else {
                    print("❌ Failed to fetch conversations: \(error)")
                    await MainActor.run {
                        self.syncError = error
                    }
                }
                await MainActor.run {
                    self.isSyncing = false
                }
            }
        }
    }
    
    private func fetchMessagesForRecentConversations() async {
        // Fetch full messages for the 5 most recent conversations
        let recentConversations = Array(conversations.prefix(5))
        
        for conversation in recentConversations {
            await fetchMessages(for: conversation)
        }
    }
    
    func fetchMessages(for conversation: Conversation) async {
        do {
            let conversationRef = CKRecord.Reference(
                recordID: CKRecord.ID(recordName: conversation.id.uuidString),
                action: .none
            )
            
            let predicate = NSPredicate(format: "conversation == %@", conversationRef)
            let query = CKQuery(recordType: CloudKitRelayConfig.chatMessageRecordType,
                              predicate: predicate)
            query.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: true)]
            
            let results = try await database.records(matching: query)
            
            var messages: [ChatMessage] = []
            var seenMessageIDs = Set<UUID>()
            
            for (_, result) in results.matchResults {
                if let record = try? result.get(),
                   let message = await messageFromRecord(record) {
                    // Only add if we haven't seen this message ID yet
                    if !seenMessageIDs.contains(message.id) {
                        messages.append(message)
                        seenMessageIDs.insert(message.id)
                    } else {
                        print("⚠️ Skipping duplicate message ID: \(message.id)")
                    }
                }
            }
            
            // Update conversation with fetched messages
            let finalMessages = messages
            await MainActor.run {
                if let index = conversations.firstIndex(where: { $0.id == conversation.id }) {
                    conversations[index].messages = finalMessages
                    updateLocalCache()
                }
            }
            
        } catch {
            print("❌ Failed to fetch messages: \(error)")
        }
    }
    
    // MARK: - Record Conversion
    
    private func conversationFromRecord(_ record: CKRecord) -> Conversation? {
        guard let serviceID = record["serviceID"] as? String,
              let serviceName = record["serviceName"] as? String else {
            return nil
        }
        
        // Preserve the conversation ID from CloudKit record name
        guard let conversationID = UUID(uuidString: record.recordID.recordName) else {
            print("❌ Invalid conversation ID in CloudKit record: \(record.recordID.recordName)")
            return nil
        }
        
        let createdAt = record["createdAt"] as? Date ?? Date()
        let updatedAt = record["updatedAt"] as? Date ?? Date()
        
        // Reconstruct conversation with original ID
        let conversation = Conversation(
            id: conversationID,
            serviceID: serviceID,
            serviceName: serviceName,
            messages: [], // Messages will be fetched separately
            createdAt: createdAt,
            updatedAt: updatedAt
        )
        
        return conversation
    }
    
    private func messageFromRecord(_ record: CKRecord) async -> ChatMessage? {
        guard let roleString = record["role"] as? String,
              let role = MessageRole(rawValue: roleString),
              let _ = record["timestamp"] as? Date else {
            return nil
        }
        
        // Fetch content based on storage type
        var content = ""
        if record["storageType"] as? String == "asset" {
            // Large content stored as CKAsset
            if let asset = record["contentAsset"] as? CKAsset,
               let url = asset.fileURL,
               let data = try? Data(contentsOf: url),
               let text = String(data: data, encoding: .utf8) {
                content = text
            }
        } else {
            // Small content stored as field
            content = record["content"] as? String ?? ""
        }
        
        // Fetch image data if present
        var imageData: Data?
        var imageAssetURL: String?
        
        if record["imageStorageType"] as? String == "asset" {
            // Large image stored as CKAsset
            if let asset = record["imageAsset"] as? CKAsset,
               let url = asset.fileURL {
                imageData = try? Data(contentsOf: url)
                imageAssetURL = url.absoluteString
            }
        } else if let base64String = record["imageData"] as? String {
            // Small image stored as base64 field
            imageData = Data(base64Encoded: base64String)
        }
        
        // Fetch image metadata if present
        var imageMetadata: ImageMetadata?
        if let metadataString = record["imageMetadata"] as? String,
           let metadataData = metadataString.data(using: .utf8) {
            imageMetadata = try? JSONDecoder().decode(ImageMetadata.self, from: metadataData)
        }
        
        // Preserve the message ID from CloudKit record name
        guard let messageID = UUID(uuidString: record.recordID.recordName) else {
            print("❌ Invalid message ID in CloudKit record: \(record.recordID.recordName)")
            return nil
        }
        
        let timestamp = record["timestamp"] as? Date ?? Date()
        
        let message = ChatMessage(
            id: messageID,
            role: role,
            content: content,
            timestamp: timestamp,
            imageData: imageData,
            imageAssetURL: imageAssetURL,
            imageMetadata: imageMetadata
        )
        return message
    }
    
    // MARK: - Subscriptions for real-time sync
    
    private func setupSubscriptions() {
        // Subscribe to conversation changes
        let conversationSubscription = CKQuerySubscription(
            recordType: CloudKitRelayConfig.conversationRecordType,
            predicate: NSPredicate(value: true),
            subscriptionID: "conversation-changes",
            options: [.firesOnRecordCreation, .firesOnRecordUpdate]
        )
        
        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true
        conversationSubscription.notificationInfo = notificationInfo
        
        database.save(conversationSubscription) { subscription, error in
            if let error = error {
                if let ckError = error as? CKError, ckError.code == .unknownItem {
                    print("🔧 Conversation subscription will be created after first record save")
                } else {
                    print("❌ Failed to create subscription: \(error)")
                }
            } else {
                print("✅ Created conversation subscription")
            }
        }
    }
    
    // MARK: - Local Cache Management
    
    private func updateLocalCache() {
        // Keep only the most recent conversations in local cache for offline access
        let recentConversations = Array(conversations.prefix(maxLocalCacheConversations))
        localCache.save(conversations: recentConversations)
    }
    
    func loadFromCache() {
        conversations = localCache.load()
    }
}

// MARK: - Local Cache for Offline Support
private class ConversationCache {
    private let cacheKey = "CloudKitConversationCache"
    
    func save(conversations: [Conversation]) {
        // Create lightweight versions without image data to avoid UserDefaults size limits
        let lightweightConversations = conversations.map { conversation in
            var lightConversation = conversation
            // Remove image data from messages to keep cache small
            lightConversation.messages = conversation.messages.map { message in
                ChatMessage(
                    id: message.id,
                    role: message.role,
                    content: message.content,
                    timestamp: message.timestamp,
                    imageData: nil, // Remove image data from cache
                    imageAssetURL: message.imageAssetURL,
                    imageMetadata: message.imageMetadata
                )
            }
            return lightConversation
        }
        
        guard let data = try? JSONEncoder().encode(lightweightConversations) else { return }
        UserDefaults.standard.set(data, forKey: cacheKey)
    }
    
    func load() -> [Conversation] {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let conversations = try? JSONDecoder().decode([Conversation].self, from: data) else {
            return []
        }
        return conversations
    }
}

