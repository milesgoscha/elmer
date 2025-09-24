//
//  ThemedChatComponents.swift
//  elmer iOS
//
//  Canon-inspired themed components for chat interface
//

import SwiftUI

// MARK: - Height Preference Key for dynamic text field sizing
struct HeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 35
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Themed Message Bubble
struct ThemedMessageBubble: View {
    let message: ChatMessage
    
    var body: some View {
        HStack {
            if message.isUser { 
                Spacer(minLength: 60) 
            }
            
            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(ElmeriOSTheme.textColor)
                    .padding(.horizontal, message.isUser ? 16 : 0)
                    .padding(.vertical, message.isUser ? 12 : 0)
                    .background(
                        Group {
                            if message.isUser {
                                RoundedRectangle(cornerRadius: 18)
                                    .fill(ElmeriOSTheme.surfaceColor)
                            } else {
                                EmptyView()
                            }
                        }
                    )
                    .frame(maxWidth: UIScreen.main.bounds.width * 0.75, alignment: message.isUser ? .trailing : .leading)
            }
            
            if !message.isUser { 
                Spacer(minLength: 60) 
            }
        }
    }
}

// MARK: - Themed Chat Input
struct ThemedChatInput<LeadingContent: View>: View {
    @Binding var text: String
    let onSend: () -> Void
    let isLoading: Bool
    let canSend: Bool
    @ViewBuilder let leadingContent: () -> LeadingContent

    init(text: Binding<String>,
         onSend: @escaping () -> Void,
         isLoading: Bool,
         canSend: Bool,
         @ViewBuilder leadingContent: @escaping () -> LeadingContent = { EmptyView() }) {
        self._text = text
        self.onSend = onSend
        self.isLoading = isLoading
        self.canSend = canSend
        self.leadingContent = leadingContent
    }

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                leadingContent()

                TextField("Message", text: $text, axis: .vertical)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(ElmeriOSTheme.textColor)
                    .lineLimit(1...5) // Grow from 1 to 5 lines
                    .submitLabel(.send)
                    .onSubmit {
                        if canSend && !text.isEmpty {
                            onSend()
                        }
                    }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(ElmeriOSTheme.surfaceColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(ElmeriOSTheme.borderColor, lineWidth: 1)
                    )
            )

            Button(action: onSend) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(canSend && !text.isEmpty ? ElmeriOSTheme.accentColor : ElmeriOSTheme.textTertiary)
            }
            .disabled(!canSend || text.isEmpty || isLoading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(ElmeriOSTheme.backgroundColor)
    }
}

// Extension to provide backward compatibility
extension ThemedChatInput where LeadingContent == EmptyView {
    init(text: Binding<String>, onSend: @escaping () -> Void, isLoading: Bool, canSend: Bool) {
        self.init(text: text, onSend: onSend, isLoading: isLoading, canSend: canSend, leadingContent: { EmptyView() })
    }
}

// MARK: - Themed Model Selector
struct ThemedModelSelector: View {
    let selectedModel: AIModel?
    let isLoading: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "cube")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(ElmeriOSTheme.textSecondary)
                
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Text(selectedModel?.name ?? "Select Model")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(ElmeriOSTheme.textColor)
                }
                
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(ElmeriOSTheme.textSecondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(ElmeriOSTheme.surfaceColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(ElmeriOSTheme.borderColor, lineWidth: 1)
                    )
            )
        }
        .disabled(isLoading)
    }
}

// MARK: - Themed Encryption Badge
struct ThemedEncryptionBadge: View {
    let isEncrypted: Bool
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: isEncrypted ? "lock.fill" : "lock.open.fill")
                .font(.system(size: 10, weight: .medium))
            
            Text(isEncrypted ? "Encrypted" : "Unencrypted")
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundColor(isEncrypted ? ElmeriOSTheme.successColor : ElmeriOSTheme.warningColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill((isEncrypted ? ElmeriOSTheme.successColor : ElmeriOSTheme.warningColor).opacity(0.15))
        )
    }
}

// MARK: - Themed Loading Indicator
struct ThemedLoadingBubble: View {
    @State private var isAnimating = false
    
    var body: some View {
        HStack {
            HStack(spacing: 4) {
                ForEach(0..<3) { index in
                    LoadingDot(delay: Double(index) * 0.2, isAnimating: isAnimating)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(ElmeriOSTheme.surfaceColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(ElmeriOSTheme.borderColor, lineWidth: 1)
                    )
            )
            
            Spacer()
        }
        .onAppear {
            isAnimating = true
        }
        .padding(.horizontal, 16)
    }
}

struct LoadingDot: View {
    let delay: Double
    let isAnimating: Bool
    
    var body: some View {
        Circle()
            .fill(ElmeriOSTheme.textSecondary)
            .frame(width: 8, height: 8)
            .scaleEffect(isAnimating ? 1.2 : 0.6, anchor: .center)
            .opacity(isAnimating ? 1.0 : 0.4)
            .animation(
                Animation.easeInOut(duration: 0.6)
                    .repeatForever(autoreverses: true)
                    .delay(delay),
                value: isAnimating
            )
            .frame(width: 10, height: 10) // Fixed frame to contain the scaling animation
    }
}

// MARK: - Themed Model Picker
struct ThemedModelPicker: View {
    let models: [AIModel]
    @Binding var selectedModel: AIModel?
    @Binding var isPresented: Bool
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(models) { model in
                        Button(action: {
                            selectedModel = model
                            isPresented = false
                        }) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(model.name)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(ElmeriOSTheme.textColor)
                                    
                                    if shouldShowSubtitle(for: model) {
                                        Text(modelSubtitle(for: model))
                                            .font(.system(size: 12, weight: .regular))
                                            .foregroundColor(ElmeriOSTheme.textSecondary)
                                    }
                                }
                                
                                Spacer()
                            }
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(ElmeriOSTheme.cardColor)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(selectedModel?.id == model.id ? ElmeriOSTheme.accentColor : ElmeriOSTheme.borderColor, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(20)
            }
            .background(ElmeriOSTheme.groupedBackground)
            .navigationTitle("Select Model")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        isPresented = false
                    }
                    .font(.system(size: 16, weight: .medium))
                }
            }
        }
    }
    
    private func shouldShowSubtitle(for model: AIModel) -> Bool {
        // Only show subtitle if we have meaningful info (not just repeating the name/id)
        if let description = model.description, !description.isEmpty {
            return description != model.name && description != model.id
        } else if model.contextLength != nil {
            return true // Context length is always meaningful
        } else {
            return false // Don't show model ID as subtitle if that's all we have
        }
    }
    
    private func modelSubtitle(for model: AIModel) -> String {
        // Priority order: description -> context length -> model ID
        if let description = model.description, !description.isEmpty {
            return description
        } else if let contextLength = model.contextLength {
            return formatContextLength(contextLength)
        } else {
            return model.id
        }
    }
    
    private func formatContextLength(_ length: Int) -> String {
        if length >= 1000 {
            let k = length / 1000
            return "\(k)K context"
        } else {
            return "\(length) context"
        }
    }
}