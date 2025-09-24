//
//  ConversationManager.swift
//  elmer iOS
//
//  Manages conversation storage and retrieval
//

import Foundation

class ConversationManager: ObservableObject {
    @Published var conversations: [Conversation] = []
    private let userDefaults = UserDefaults.standard
    private let conversationsKey = "SavedConversations"
    
    init() {
        loadConversations()
    }
    
    // MARK: - Storage
    
    func saveConversations() {
        do {
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
            
            let data = try JSONEncoder().encode(lightweightConversations)
            userDefaults.set(data, forKey: conversationsKey)
            // print("💾 Saved \(conversations.count) conversations")
        } catch {
            print("❌ Failed to save conversations: \(error)")
        }
    }
    
    func loadConversations() {
        guard let data = userDefaults.data(forKey: conversationsKey) else {
            // print("📖 No saved conversations found")
            return
        }
        
        do {
            conversations = try JSONDecoder().decode([Conversation].self, from: data)
            // Sort by most recently updated
            conversations.sort { $0.updatedAt > $1.updatedAt }
            // print("📖 Loaded \(conversations.count) conversations")
        } catch {
            print("❌ Failed to load conversations: \(error)")
            conversations = []
        }
    }
    
    // MARK: - Conversation Management
    
    func createConversation(serviceName: String, modelName: String?) -> Conversation {
        // For CloudKit relay, we use serviceName as serviceID since we don't have separate IDs
        let conversation = Conversation(serviceID: serviceName, serviceName: serviceName)
        conversations.insert(conversation, at: 0) // Add to top
        saveConversations()
        return conversation
    }
    
    func updateConversation(_ conversation: Conversation) {
        if let index = conversations.firstIndex(where: { $0.id == conversation.id }) {
            conversations[index] = conversation
            
            // Move to top of list
            let updated = conversations.remove(at: index)
            conversations.insert(updated, at: 0)
            
            saveConversations()
        }
    }
    
    func deleteConversation(_ conversation: Conversation) {
        conversations.removeAll { $0.id == conversation.id }
        saveConversations()
    }
    
    func clearAllConversations() {
        conversations.removeAll()
        saveConversations()
    }
    
    // MARK: - Convenience
    
    func getConversationsForService(_ serviceName: String) -> [Conversation] {
        return conversations.filter { $0.serviceName == serviceName }
    }
    
    func getMostRecentConversation(for serviceName: String, model: String?) -> Conversation? {
        return conversations.first { conversation in
            conversation.serviceName == serviceName && 
            !conversation.messages.isEmpty
        }
    }
}