//
//  ConversationSidebar.swift
//  elmer iOS
//
//  Slide-out sidebar for conversation history management
//

import SwiftUI

struct ConversationSidebar: View {
    let service: RemoteService
    @EnvironmentObject var conversationManager: ConversationManager
    @EnvironmentObject var cloudKitConversationManager: CloudKitConversationManager
    @Binding var selectedConversation: Conversation?
    @Binding var isPresented: Bool
    
    private var serviceConversations: [Conversation] {
        // Use CloudKit conversations, filtered by service
        cloudKitConversationManager.conversations.filter { conv in
            conv.serviceName == service.name
        }
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                // Full background
                ElmeriOSTheme.backgroundColor
                    .ignoresSafeArea(.all)
                
                ScrollView {
                    VStack(spacing: 8) {
                        if serviceConversations.isEmpty {
                            ThemedEmptyState(
                                icon: "bubble.left.and.bubble.right",
                                title: "No Conversations",
                                subtitle: "Start chatting to create conversation history"
                            )
                            .padding(.top, 60)
                        } else {
                            ForEach(serviceConversations) { conversation in
                                ConversationRow(
                                    conversation: conversation,
                                    isSelected: selectedConversation?.id == conversation.id,
                                    onTap: {
                                        selectedConversation = conversation
                                        isPresented = false
                                    },
                                    onDelete: {
                                        Task {
                                            await cloudKitConversationManager.deleteConversation(conversation)
                                        }
                                        // Also delete from old manager for backward compatibility
                                        conversationManager.deleteConversation(conversation)
                                        // Clear selection if deleting current conversation
                                        if selectedConversation?.id == conversation.id {
                                            selectedConversation = nil
                                        }
                                    }
                                )
                            }
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Conversations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        isPresented = false
                    }
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(ElmeriOSTheme.accentColor)
                }
                
                if !serviceConversations.isEmpty {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("New Chat") {
                            selectedConversation = nil
                            isPresented = false
                        }
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(ElmeriOSTheme.accentColor)
                    }
                }
            }
        }
    }
}

struct ConversationRow: View {
    let conversation: Conversation
    let isSelected: Bool
    let onTap: () -> Void
    let onDelete: () -> Void
    
    
    var body: some View {
        HStack {
            // Main content area
            VStack(alignment: .leading, spacing: 2) {
                Text(conversationTitle(for: conversation))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(ElmeriOSTheme.textColor)
                    .lineLimit(1)
                
                Text("\(conversation.messages.count) messages")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(ElmeriOSTheme.textSecondary)
            }
            
            Spacer()
            
            // Time vertically centered
            Text(formatRelativeDate(conversation.updatedAt))
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(ElmeriOSTheme.textTertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(ElmeriOSTheme.cardColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? ElmeriOSTheme.accentColor : ElmeriOSTheme.borderColor, lineWidth: 1)
        )
        .onTapGesture {
            onTap()
        }
        .contextMenu {
            Button(action: onDelete) {
                Label("Delete Conversation", systemImage: "trash")
            }
            .foregroundColor(.red)
        }
    }
    
    private func conversationTitle(for conversation: Conversation) -> String {
        // Try to get the first user message for context
        if let firstUserMessage = conversation.messages.first(where: { $0.role == .user }) {
            let content = firstUserMessage.content.trimmingCharacters(in: .whitespacesAndNewlines)
            // Truncate to reasonable length for display
            if content.count > 50 {
                return String(content.prefix(47)) + "..."
            }
            return content.isEmpty ? conversation.serviceName : content
        }
        // Fallback to service name if no user messages
        return conversation.serviceName
    }
    
    private func formatRelativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

