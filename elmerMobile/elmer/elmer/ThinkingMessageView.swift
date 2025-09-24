//
//  ThinkingMessageView.swift
//  elmer
//
//  Enhanced message view that separates thinking/reasoning from final response
//

import SwiftUI

struct ThinkingMessageView: View {
    let message: ChatMessage
    @State private var isThinkingExpanded = false
    @State private var loadedImage: UIImage?
    @State private var isLoadingImage = false
    
    // Parse message content to separate thinking from response
    private var parsedContent: (thinking: String?, response: String) {
        let content = message.content
        
        // Debug: Print the message content to see what we're working with
        print("🤔 DEBUG: Analyzing message content (first 200 chars): \(content.prefix(200))...")
        
        // Define all the thinking tag patterns we want to detect
        let thinkingPatterns = [
            ("<think>", "</think>"),           // Qwen format
            ("<thinking>", "</thinking>"),     // DeepSeek, Claude format
            ("<reflection>", "</reflection>"), // Reflection format
            ("<reasoning>", "</reasoning>"),   // Reasoning format
            ("<analysis>", "</analysis>"),     // Analysis format
            ("<plan>", "</plan>")              // Planning format
        ]
        
        // Try each pattern
        for (startTag, endTag) in thinkingPatterns {
            if let startRange = content.range(of: startTag, options: .caseInsensitive),
               let endRange = content.range(of: endTag, options: .caseInsensitive) {
                
                print("🤔 DEBUG: Found thinking pattern: \(startTag) ... \(endTag)")
                
                let thinkingContent = String(content[startRange.upperBound..<endRange.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let afterThinking = String(content[endRange.upperBound...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                
                let response = afterThinking.isEmpty ? "Processing complete." : afterThinking
                print("🤔 DEBUG: Extracted thinking (\(thinkingContent.count) chars) and response (\(response.count) chars)")
                
                return (thinking: thinkingContent, response: response)
            }
        }
        
        // Check for prefix-based thinking patterns (fallback)
        let thinkingPrefixes = ["Thinking:", "Reasoning:", "Analysis:", "Planning:", "Let me think"]
        for prefix in thinkingPrefixes {
            if content.lowercased().hasPrefix(prefix.lowercased()) {
                print("🤔 DEBUG: Found prefix pattern: \(prefix)")
                
                // Find where thinking ends (usually at double newline or specific markers)
                let separators = ["\n\nResponse:", "\n\nAnswer:", "\n\nBased on", "\n\nSo ", "\n\nTherefore", "\n\n---", "\n\nTo answer"]
                for separator in separators {
                    if let range = content.range(of: separator, options: .caseInsensitive) {
                        let thinkingContent = String(content[..<range.lowerBound])
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        let response = String(content[range.upperBound...])
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        print("🤔 DEBUG: Split at separator '\(separator)' - thinking: \(thinkingContent.count) chars, response: \(response.count) chars")
                        return (thinking: thinkingContent, response: response)
                    }
                }
                
                // If no clear separator, check for substantial paragraph break
                let paragraphs = content.components(separatedBy: "\n\n")
                if paragraphs.count >= 2 {
                    let firstPart = paragraphs[0].trimmingCharacters(in: .whitespacesAndNewlines)
                    let restParts = paragraphs.dropFirst().joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    // Heuristic: if first part starts with thinking prefix and rest is substantial
                    if firstPart.lowercased().hasPrefix(prefix.lowercased()) && restParts.count > 50 {
                        print("🤔 DEBUG: Split at paragraph break - thinking: \(firstPart.count) chars, response: \(restParts.count) chars")
                        return (thinking: firstPart, response: restParts)
                    }
                }
            }
        }
        
        // No thinking detected, return content as response
        print("🤔 DEBUG: No thinking pattern detected, returning full content as response")
        return (thinking: nil, response: content)
    }
    
    var body: some View {
        VStack(alignment: message.isUser ? .trailing : .leading, spacing: 8) {
            HStack {
                VStack(alignment: message.isUser ? .trailing : .leading, spacing: 8) {
                    // Show thinking section if present (only for assistant messages)
                    if !message.isUser, let thinking = parsedContent.thinking {
                        ThinkingSection(
                            thinking: thinking,
                            isExpanded: $isThinkingExpanded
                        )
                    }
                    
                    // Display main response content (selective markdown formatting)
                    if !parsedContent.response.isEmpty {
                        Text(formatSelectiveMarkdown(parsedContent.response))
                            .font(.system(size: 15))
                            .foregroundColor(message.isUser ? .white : ElmeriOSTheme.textColor)
                            .padding(.horizontal, message.isUser ? 16 : 0)
                            .padding(.vertical, message.isUser ? 12 : 0)
                            .background(
                                Group {
                                    if message.isUser {
                                        RoundedRectangle(cornerRadius: 18)
                                            .fill(Color(red: 0.2, green: 0.2, blue: 0.2))
                                    }
                                }
                            )
                            .frame(maxWidth: .infinity, alignment: message.isUser ? .trailing : .leading)
                    }
                    
                    // Display image if present
                    if message.hasImage {
                        ImageDisplayView(message: message, loadedImage: $loadedImage, isLoadingImage: $isLoadingImage)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }
    
    // MARK: - Simple text formatting (preserves model's original formatting)
    private func formatSelectiveMarkdown(_ text: String) -> AttributedString {
        var result = AttributedString(text)
        result.font = UIFont.systemFont(ofSize: 15)
        result.foregroundColor = message.isUser ? UIColor.white : UIColor(ElmeriOSTheme.textColor)
        return result
    }
    
    
    // MARK: - Original Markdown formatting (kept for reference)
    private func formatMarkdown(_ text: String) -> AttributedString {
        do {
            var options = AttributedString.MarkdownParsingOptions()
            options.allowsExtendedAttributes = true
            options.interpretedSyntax = .full
            
            var attributedString = try AttributedString(markdown: text, options: options)
            
            let range = attributedString.startIndex..<attributedString.endIndex
            attributedString[range].font = .system(size: 15)
            attributedString[range].foregroundColor = message.isUser ? .white : ElmeriOSTheme.textColor
            
            return attributedString
        } catch {
            var result = AttributedString(text)
            result.font = .system(size: 15)
            result.foregroundColor = message.isUser ? .white : ElmeriOSTheme.textColor
            return result
        }
    }
}

// MARK: - Thinking Section Component
struct ThinkingSection: View {
    let thinking: String
    @Binding var isExpanded: Bool
    
    private var thinkingSummary: String {
        // Create a brief summary of the thinking for the collapsed state
        let lines = thinking.components(separatedBy: .newlines)
        if let firstLine = lines.first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
            let cleaned = firstLine
                .replacingOccurrences(of: "Thinking:", with: "")
                .replacingOccurrences(of: "Reasoning:", with: "")
                .replacingOccurrences(of: "Analysis:", with: "")
                .replacingOccurrences(of: "Planning:", with: "")
                .replacingOccurrences(of: "Let me think", with: "")
                .trimmingCharacters(in: .whitespaces)
            
            if cleaned.count > 50 {
                return String(cleaned.prefix(47)) + "..."
            }
            return cleaned.isEmpty ? "Model reasoning detected" : cleaned
        }
        return "Model reasoning process"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Collapsible header
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            }) {
                HStack(spacing: 10) {
                    // Animated chevron
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(ElmeriOSTheme.accentColor.opacity(0.7))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    
                    // Brain icon with subtle animation
                    Image(systemName: "brain")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(ElmeriOSTheme.accentColor.opacity(0.7))
                        .scaleEffect(isExpanded ? 1.1 : 1.0)
                    
                    Text(isExpanded ? "Thinking Process" : thinkingSummary)
                        .font(.system(size: 13, weight: isExpanded ? .medium : .regular))
                        .foregroundColor(ElmeriOSTheme.textSecondary)
                        .lineLimit(isExpanded ? nil : 1)
                    
                    Spacer()
                    
                    if !isExpanded {
                        // Simple badge showing character count
                        Text("\(thinking.count) chars")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(ElmeriOSTheme.textTertiary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(ElmeriOSTheme.textTertiary.opacity(0.15))
                            )
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(
                            LinearGradient(
                                colors: [
                                    ElmeriOSTheme.accentColor.opacity(0.03),
                                    ElmeriOSTheme.accentColor.opacity(0.06)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(
                                    ElmeriOSTheme.accentColor.opacity(isExpanded ? 0.2 : 0.1),
                                    lineWidth: 1
                                )
                        )
                )
            }
            .buttonStyle(PlainButtonStyle())
            
            // Expanded thinking content - animate from the card position
            ScrollView {
                if isExpanded {
                    Text(thinking)
                        .font(.system(size: 13, weight: .regular, design: .monospaced))
                        .foregroundColor(ElmeriOSTheme.textSecondary)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.black.opacity(0.3))
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }
            }
            .frame(maxHeight: isExpanded ? 300 : 0)
            .clipped()
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isExpanded)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Preview
#Preview {
    VStack(spacing: 20) {
        // Message with thinking
        ThinkingMessageView(
            message: ChatMessage(
                role: .assistant,
                content: """
                <thinking>
                I need to analyze this request carefully. The user wants to know about Swift concurrency.
                Let me think about the key concepts:
                - async/await
                - Task and TaskGroup
                - Actors and actor isolation
                - Sendable protocol
                </thinking>
                
                Swift's modern concurrency model, introduced in Swift 5.5, provides several powerful features:
                
                1. **Async/Await**: Allows you to write asynchronous code that looks synchronous
                2. **Structured Concurrency**: Task and TaskGroup help manage concurrent operations
                3. **Actors**: Provide thread-safe access to mutable state
                
                These features make concurrent programming safer and more intuitive.
                """
            )
        )
        
        // Regular message without thinking
        ThinkingMessageView(
            message: ChatMessage(
                role: .assistant,
                content: "This is a regular response without any thinking process shown."
            )
        )
    }
    .background(ElmeriOSTheme.backgroundColor)
    .preferredColorScheme(.dark)
}