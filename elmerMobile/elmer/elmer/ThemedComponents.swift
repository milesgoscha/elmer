//
//  ThemedComponents.swift
//  elmer iOS
//
//  Canon-inspired themed UI components for iOS
//

import SwiftUI

// MARK: - Geist iOS Theme (Dark)
struct GeistIOSTheme {
    // Backgrounds - Dark base matching Mac
    static let backgroundColor = Color(red: 0.08, green: 0.08, blue: 0.08) // Very dark gray
    static let surfaceColor = Color(red: 0.12, green: 0.12, blue: 0.12) // Card background
    static let cardColor = Color(red: 0.12, green: 0.12, blue: 0.12) // Same as surface
    static let groupedBackground = Color(red: 0.08, green: 0.08, blue: 0.08) // Same as background
    
    // Text hierarchy - Light on dark
    static let textColor = Color.white
    static let textSecondary = Color(red: 0.7, green: 0.7, blue: 0.7) // Light gray
    static let textTertiary = Color(red: 0.5, green: 0.5, blue: 0.5) // Medium gray
    
    // Interactive elements
    static let accentColor = Color.white // White for primary actions
    static let borderColor = Color(red: 0.2, green: 0.2, blue: 0.2) // Subtle dark border
    
    // Status colors - Adjusted for dark theme
    static let successColor = Color(red: 0.2, green: 0.8, blue: 0.2) // Brighter green
    static let errorColor = Color(red: 0.9, green: 0.3, blue: 0.3) // Lighter red
    static let warningColor = Color(red: 1.0, green: 0.6, blue: 0.0) // Orange
}

// Keep old name as alias during transition
typealias ElmeriOSTheme = GeistIOSTheme

// MARK: - Themed Card
struct ThemedCard<Content: View>: View {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        content
            .padding(16)
            .background(ElmeriOSTheme.cardColor)
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Themed Button
struct ThemedButton: View {
    let title: String
    let icon: String?
    let action: () -> Void
    let style: ButtonStyle
    
    enum ButtonStyle {
        case primary
        case secondary
        case destructive
        case large
    }
    
    init(title: String, icon: String? = nil, action: @escaping () -> Void, style: ButtonStyle = .primary) {
        self.title = title
        self.icon = icon
        self.action = action
        self.style = style
    }
    
    private var backgroundColor: Color {
        switch style {
        case .primary, .large:
            return ElmeriOSTheme.accentColor
        case .secondary:
            return ElmeriOSTheme.surfaceColor
        case .destructive:
            return ElmeriOSTheme.surfaceColor
        }
    }
    
    private var textColor: Color {
        switch style {
        case .primary, .large:
            return ElmeriOSTheme.backgroundColor // Dark text on white button
        case .secondary:
            return ElmeriOSTheme.textColor
        case .destructive:
            return ElmeriOSTheme.errorColor
        }
    }
    
    private var borderColor: Color? {
        switch style {
        case .primary:
            return nil // No border for primary
        case .secondary, .destructive:
            return ElmeriOSTheme.borderColor
        case .large:
            return nil
        }
    }
    
    private var fontSize: CGFloat {
        switch style {
        case .large:
            return 15 // Smaller, more refined
        default:
            return 13 // Smaller, matching Mac app
        }
    }
    
    private var padding: EdgeInsets {
        switch style {
        case .large:
            return EdgeInsets(top: 16, leading: 24, bottom: 16, trailing: 24)
        default:
            return EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16)
        }
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: fontSize - 1, weight: .medium))
                }
                
                Text(title)
                    .font(.system(size: fontSize, weight: .medium))
            }
            .foregroundColor(textColor)
            .padding(padding)
            .frame(maxWidth: style == .large ? .infinity : nil)
            .background(backgroundColor)
            .overlay(
                Group {
                    if let borderColor = borderColor {
                        RoundedRectangle(cornerRadius: style == .large ? 8 : 6)
                            .stroke(borderColor, lineWidth: 1)
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: style == .large ? 8 : 6))
        }
    }
}

// MARK: - Themed Section Header
struct ThemedSectionHeader: View {
    let title: String
    
    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(ElmeriOSTheme.textTertiary)
                .tracking(0.5)
            
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }
}

// MARK: - Themed Helper Text
struct ThemedHelperText: View {
    let text: String
    let alignment: TextAlignment
    
    init(_ text: String, alignment: TextAlignment = .leading) {
        self.text = text
        self.alignment = alignment
    }
    
    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .regular))
            .foregroundColor(ElmeriOSTheme.textTertiary)
            .multilineTextAlignment(alignment)
            .lineSpacing(2)
    }
}

// MARK: - Themed Service Card
struct ThemedServiceCard: View {
    let service: RemoteService
    let connectionStatus: ServiceConnectionStatus
    
    var body: some View {
        HStack(spacing: 12) {
            // Minimal status indicator
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
            
            // Service Info
            VStack(alignment: .leading, spacing: 2) {
                Text(service.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(ElmeriOSTheme.textColor)
                
                Text(statusText)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(ElmeriOSTheme.textSecondary)
            }
            
            Spacer()
            
            // Chevron
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(ElmeriOSTheme.textTertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(ElmeriOSTheme.cardColor)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(ElmeriOSTheme.borderColor, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
    
    private var statusColor: Color {
        switch connectionStatus {
        case .connected: return ElmeriOSTheme.successColor
        case .connecting: return ElmeriOSTheme.warningColor
        case .failed: return ElmeriOSTheme.borderColor
        }
    }
    
    private var statusText: String {
        switch connectionStatus {
        case .connected: return "Running"
        case .connecting: return "Connecting"
        case .failed: return "Not running"
        }
    }
}

// MARK: - Themed Empty State
struct ThemedEmptyState: View {
    let icon: String
    let title: String
    let subtitle: String
    let buttonTitle: String?
    let buttonAction: (() -> Void)?
    
    init(icon: String, title: String, subtitle: String, buttonTitle: String? = nil, buttonAction: (() -> Void)? = nil) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.buttonTitle = buttonTitle
        self.buttonAction = buttonAction
    }
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 48, weight: .regular))
                .foregroundColor(ElmeriOSTheme.textTertiary)
            
            VStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(ElmeriOSTheme.textColor)
                
                ThemedHelperText(subtitle, alignment: .center)
            }
            
            if let buttonTitle = buttonTitle, let buttonAction = buttonAction {
                ThemedButton(title: buttonTitle, action: buttonAction, style: .large)
                    .padding(.horizontal, 40)
            }
        }
        .padding(40)
    }
}

// MARK: - Themed Warning Banner
struct ThemedWarningBanner: View {
    let message: String
    let buttonTitle: String?
    let buttonAction: (() -> Void)?
    
    init(message: String, buttonTitle: String? = nil, buttonAction: (() -> Void)? = nil) {
        self.message = message
        self.buttonTitle = buttonTitle
        self.buttonAction = buttonAction
    }
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.orange)
            
            Text(message)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(ElmeriOSTheme.textColor)
            
            Spacer()
            
            if let buttonTitle = buttonTitle, let buttonAction = buttonAction {
                ThemedButton(title: buttonTitle, action: buttonAction, style: .secondary)
            }
        }
        .padding(16)
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Themed Navigation
struct ThemedNavigationTitle: View {
    let title: String
    
    var body: some View {
        Text(title)
            .font(.system(size: 28, weight: .semibold))
            .foregroundColor(ElmeriOSTheme.textColor)
    }
}