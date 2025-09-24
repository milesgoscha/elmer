//
//  ThemedComponents.swift
//  elmer
//
//  Themed UI components based on Canon design patterns
//

import SwiftUI

// MARK: - Geist-inspired Dark Theme Colors
struct GeistTheme {
    // Backgrounds - Dark base
    static let background = NSColor(white: 0.08, alpha: 1.0) // Very dark gray
    static let backgroundSecondary = NSColor(white: 0.12, alpha: 1.0) // Slightly lighter
    
    // Surface colors for cards/components
    static let surface = NSColor(white: 0.12, alpha: 1.0) // Card background
    static let surfaceHover = NSColor(white: 0.16, alpha: 1.0) // Hover state
    
    // Text hierarchy - Light on dark
    static let textPrimary = NSColor.white
    static let textSecondary = NSColor(white: 0.7, alpha: 1.0) // Light gray
    static let textTertiary = NSColor(white: 0.5, alpha: 1.0) // Medium gray
    
    // Borders - Subtle dark borders
    static let border = NSColor(white: 0.2, alpha: 1.0) // Dark gray border
    static let borderHover = NSColor(white: 0.3, alpha: 1.0) // Slightly lighter on hover
    
    // Accent - White for contrast
    static let accent = NSColor.white
    static let accentSubtle = NSColor(white: 0.15, alpha: 1.0)
    
    // Status colors - Adjusted for dark theme
    static let success = NSColor(red: 0.2, green: 0.8, blue: 0.2, alpha: 1.0) // Brighter green
    static let successSubtle = NSColor(red: 0.1, green: 0.25, blue: 0.1, alpha: 1.0) // Dark green background
    static let error = NSColor(red: 0.9, green: 0.3, blue: 0.3, alpha: 1.0) // Lighter red for visibility
}

// Keep old name as alias during transition
typealias ElmerTheme = GeistTheme

// MARK: - Themed Toggle
struct ThemedToggle: View {
    let title: String
    @Binding var isOn: Bool
    
    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(Color(nsColor: GeistTheme.textPrimary))
            
            Spacer()
            
            Button(action: {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isOn.toggle()
                }
            }) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(isOn ? Color(nsColor: GeistTheme.accent) : Color(nsColor: GeistTheme.border))
                    .frame(width: 36, height: 20)
                    .overlay(
                        Circle()
                            .fill(isOn ? Color(nsColor: GeistTheme.background) : Color(nsColor: GeistTheme.textSecondary))
                            .frame(width: 16, height: 16)
                            .offset(x: isOn ? 8 : -8)
                            .animation(.easeInOut(duration: 0.15), value: isOn)
                    )
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Themed Button
struct ThemedButton: View {
    let title: String
    let action: () -> Void
    let style: ButtonStyle
    let icon: String?
    
    init(title: String, action: @escaping () -> Void, style: ButtonStyle, icon: String? = nil) {
        self.title = title
        self.action = action
        self.style = style
        self.icon = icon
    }
    
    enum ButtonStyle {
        case primary
        case secondary
        case destructive
    }
    
    var backgroundColor: Color {
        switch style {
        case .primary:
            return Color(nsColor: GeistTheme.accent)
        case .secondary:
            return Color(nsColor: GeistTheme.surface)
        case .destructive:
            return Color(nsColor: GeistTheme.surface)
        }
    }
    
    var textColor: Color {
        switch style {
        case .primary:
            return Color(nsColor: GeistTheme.background)
        case .secondary:
            return Color(nsColor: GeistTheme.textPrimary)
        case .destructive:
            return Color(nsColor: GeistTheme.error)
        }
    }
    
    var borderColor: Color {
        switch style {
        case .primary:
            return Color(nsColor: GeistTheme.accent)
        case .secondary:
            return Color(nsColor: GeistTheme.border)
        case .destructive:
            return Color(nsColor: GeistTheme.border)
        }
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(textColor)
                }
                Text(title)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(textColor)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(backgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(borderColor, lineWidth: style == .secondary || style == .destructive ? 1 : 0)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Themed Section Header
struct ThemedSectionHeader: View {
    let title: String
    let actionTitle: String?
    let action: (() -> Void)?
    let actionIcon: String?
    let secondaryActionTitle: String?
    let secondaryAction: (() -> Void)?
    let secondaryIcon: String?
    let tertiaryActionTitle: String?
    let tertiaryAction: (() -> Void)?
    let tertiaryIcon: String?
    
    init(_ title: String, actionTitle: String? = nil, action: (() -> Void)? = nil, actionIcon: String? = nil) {
        self.title = title
        self.actionTitle = actionTitle
        self.action = action
        self.actionIcon = actionIcon
        self.secondaryActionTitle = nil
        self.secondaryAction = nil
        self.secondaryIcon = nil
        self.tertiaryActionTitle = nil
        self.tertiaryAction = nil
        self.tertiaryIcon = nil
    }
    
    init(_ title: String, actionTitle: String? = nil, action: (() -> Void)? = nil, actionIcon: String? = nil, secondaryActionTitle: String? = nil, secondaryAction: (() -> Void)? = nil, secondaryIcon: String? = nil) {
        self.title = title
        self.actionTitle = actionTitle
        self.action = action
        self.actionIcon = actionIcon
        self.secondaryActionTitle = secondaryActionTitle
        self.secondaryAction = secondaryAction
        self.secondaryIcon = secondaryIcon
        self.tertiaryActionTitle = nil
        self.tertiaryAction = nil
        self.tertiaryIcon = nil
    }
    
    init(_ title: String, actionTitle: String? = nil, action: (() -> Void)? = nil, actionIcon: String? = nil, secondaryActionTitle: String? = nil, secondaryAction: (() -> Void)? = nil, secondaryIcon: String? = nil, tertiaryActionTitle: String? = nil, tertiaryAction: (() -> Void)? = nil, tertiaryIcon: String? = nil) {
        self.title = title
        self.actionTitle = actionTitle
        self.action = action
        self.actionIcon = actionIcon
        self.secondaryActionTitle = secondaryActionTitle
        self.secondaryAction = secondaryAction
        self.secondaryIcon = secondaryIcon
        self.tertiaryActionTitle = tertiaryActionTitle
        self.tertiaryAction = tertiaryAction
        self.tertiaryIcon = tertiaryIcon
    }
    
    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Color(nsColor: GeistTheme.textTertiary))
                .tracking(0.5)
            
            Spacer()
            
            HStack(spacing: 8) {
                if let tertiaryActionTitle = tertiaryActionTitle, let tertiaryAction = tertiaryAction {
                    ThemedButton(title: tertiaryActionTitle, action: tertiaryAction, style: .secondary, icon: tertiaryIcon)
                }
                
                if let secondaryActionTitle = secondaryActionTitle, let secondaryAction = secondaryAction {
                    ThemedButton(title: secondaryActionTitle, action: secondaryAction, style: .secondary, icon: secondaryIcon)
                }
                
                if let actionTitle = actionTitle, let action = action {
                    ThemedButton(title: actionTitle, action: action, style: .secondary, icon: actionIcon)
                }
            }
        }
        .padding(.bottom, 16)
    }
}

// MARK: - Themed Section Divider (Deprecated - use spacing instead)
struct ThemedSectionDivider: View {
    var body: some View {
        Spacer()
            .frame(height: 0)
    }
}

// MARK: - Themed Helper Text
struct ThemedHelperText: View {
    let text: String
    
    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .regular))
            .foregroundColor(Color(nsColor: GeistTheme.textTertiary))
            .lineSpacing(2)
    }
}

// MARK: - Themed Service Card
struct ThemedServiceCard: View {
    let service: AIService
    @EnvironmentObject var serviceManager: ServiceManager
    @State private var customName: String = ""
    @State private var isEditingName = false
    @State private var showingRenameAlert = false
    @State private var isTestingConnection = false
    @State private var connectionTestResult: Bool?
    
    var body: some View {
        HStack(spacing: 16) {
            // Status indicator - Larger for better visibility
            Circle()
                .fill(service.isRunning ? Color(nsColor: GeistTheme.success) : Color(nsColor: GeistTheme.border))
                .frame(width: 8, height: 8)
            
            // Service Info - Simplified hierarchy
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(service.displayName)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color(nsColor: GeistTheme.textPrimary))
                    
                    if service.isAutoDetected {
                        Text("AUTO")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Color(nsColor: GeistTheme.textTertiary))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(nsColor: GeistTheme.accentSubtle))
                            .cornerRadius(3)
                    }
                }
                
                Text(serviceStatusText)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(Color(nsColor: GeistTheme.textSecondary))
            }
            
            Spacer()
            
            // Port info and menu button
            HStack(spacing: 12) {
                Text("\(String(service.localPort))")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(Color(nsColor: GeistTheme.textTertiary))
                
                // Ellipsis menu button
                Menu {
                    Button("Rename") {
                        showingRenameAlert = true
                    }
                    
                    Button(isTestingConnection ? "Testing..." : "Test Connection") {
                        testConnection()
                    }
                    .disabled(isTestingConnection)
                    
                    if service.isRunning {
                        if service.type == .imageGeneration {
                            Button("Open WebUI") {
                                if let url = URL(string: "http://localhost:\(service.localPort)") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                        } else if service.type == .languageModel {
                            Button("View Models") {
                                if let url = URL(string: "http://localhost:\(service.localPort)/v1/models") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                        }
                    }
                    
                    Divider()
                    
                    Button("Hide Service") {
                        serviceManager.hideService(service)
                    }
                    
                    if !service.isAutoDetected {
                        Button("Remove Service", role: .destructive) {
                            showRemoveConfirmation()
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color(nsColor: GeistTheme.textTertiary))
                        .frame(width: 20, height: 20)
                        .padding(8) // Add padding to increase click area
                        .contentShape(Rectangle()) // Make entire padded area clickable
                }
                .buttonStyle(.plain)
                .menuStyle(.button)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color(nsColor: GeistTheme.surface))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: GeistTheme.border), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .alert("Rename Service", isPresented: $showingRenameAlert) {
            TextField("Service name", text: $customName)
            Button("Save") {
                saveCustomName()
            }
            Button("Cancel", role: .cancel) {
                customName = service.displayName
            }
        } message: {
            Text("Enter a custom name for \(service.name):")
        }
        .onAppear {
            customName = service.displayName
        }
    }
    
    private var serviceStatusText: String {
        if service.isRunning {
            return "Running"
        } else if service.detectionStatus == .installed {
            return "Installed but not running"
        } else {
            return "Not running"
        }
    }
    
    private func saveCustomName() {
        var updatedService = service
        updatedService.customName = customName.isEmpty ? nil : customName
        serviceManager.updateService(updatedService)
    }
    
    private func testConnection() {
        isTestingConnection = true
        connectionTestResult = nil
        
        Task {
            let result = await service.checkHealth()
            await MainActor.run {
                isTestingConnection = false
                connectionTestResult = result
                
                // Show alert with result
                let alert = NSAlert()
                alert.messageText = result ? "Connection Successful" : "Connection Failed"
                alert.informativeText = result ? 
                    "Successfully connected to \(service.displayName) on port \(service.localPort)" :
                    "Failed to connect to \(service.displayName) on port \(service.localPort). Make sure the service is running."
                alert.alertStyle = result ? .informational : .warning
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
    }
    
    private func showRemoveConfirmation() {
        let alert = NSAlert()
        alert.messageText = "Remove Service"
        alert.informativeText = "Are you sure you want to remove \"\(service.displayName)\"? This action cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        
        if alert.runModal() == .alertFirstButtonReturn {
            serviceManager.removeService(service)
        }
    }
}


// MARK: - ComfyUI Workflows Section
struct ComfyUIWorkflowsSection: View {
    @StateObject private var workflowManager = WorkflowManager.shared
    @State private var showingWorkflowImport = false
    
    var body: some View {
        VStack(spacing: 8) {
            // Workflows header
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Workflows")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color(nsColor: GeistTheme.textSecondary))
                    
                    Text("\(workflowManager.workflows.count) imported")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(Color(nsColor: GeistTheme.textTertiary))
                }
                
                Spacer()
                
                ThemedButton(title: "Import", action: {
                    showingWorkflowImport = true
                }, style: .secondary)
            }
            
            // Workflow list (show first 2-3 workflows)
            if !workflowManager.workflows.isEmpty {
                VStack(spacing: 4) {
                    ForEach(workflowManager.workflows.prefix(2), id: \.id) { workflow in
                        CompactWorkflowCard(workflow: workflow)
                    }
                    
                    if workflowManager.workflows.count > 2 {
                        HStack {
                            Text("+ \(workflowManager.workflows.count - 2) more workflows")
                                .font(.system(size: 10, weight: .regular))
                                .foregroundColor(Color(nsColor: GeistTheme.textTertiary))
                            Spacer()
                        }
                        .padding(.leading, 8)
                        .padding(.top, 2)
                    }
                }
            } else {
                HStack {
                    Text("No workflows imported")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(Color(nsColor: GeistTheme.textTertiary))
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color(nsColor: GeistTheme.background))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color(nsColor: GeistTheme.border), lineWidth: 1)
                )
            }
        }
        .sheet(isPresented: $showingWorkflowImport) {
            ThemedWorkflowImportSheet()
        }
    }
}

// MARK: - Compact Workflow Card
struct CompactWorkflowCard: View {
    let workflow: ImportedWorkflow
    @StateObject private var workflowManager = WorkflowManager.shared
    
    var body: some View {
        HStack(spacing: 8) {
            // Type indicator dot
            Circle()
                .fill(Color(nsColor: GeistTheme.accent))
                .frame(width: 4, height: 4)
            
            // Workflow info
            VStack(alignment: .leading, spacing: 1) {
                Text(workflow.name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color(nsColor: GeistTheme.textPrimary))
                    .lineLimit(1)
                
                if !workflow.requiredModels.isEmpty {
                    Text(workflow.requiredModels.first ?? "")
                        .font(.system(size: 9, weight: .regular))
                        .foregroundColor(Color(nsColor: GeistTheme.textTertiary))
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            // Type badge
            Text(workflow.type.displayName.prefix(4).uppercased())
                .font(.system(size: 8, weight: .regular))
                .foregroundColor(Color(nsColor: GeistTheme.textTertiary))
            
            // Delete button
            Button(action: {
                workflowManager.deleteWorkflow(workflow)
            }) {
                Image(systemName: "trash")
                    .font(.system(size: 9, weight: .regular))
                    .foregroundColor(Color(nsColor: GeistTheme.textTertiary))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(nsColor: GeistTheme.background))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color(nsColor: GeistTheme.border), lineWidth: 1)
        )
    }
}

// MARK: - Themed Empty State
struct ThemedEmptyState: View {
    let icon: String
    let title: String
    let subtitle: String
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .light))
                .foregroundColor(Color(nsColor: GeistTheme.textTertiary))
            
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Color(nsColor: GeistTheme.textPrimary))
            
            Text(subtitle)
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(Color(nsColor: GeistTheme.textSecondary))
                .multilineTextAlignment(.center)
                .lineSpacing(2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }
}

// MARK: - Themed Workflow Card
struct ThemedWorkflowCard: View {
    let workflow: ImportedWorkflow
    @StateObject private var workflowManager = WorkflowManager.shared
    
    var body: some View {
        HStack(spacing: 12) {
            // Workflow type indicator
            Circle()
                .fill(Color(nsColor: GeistTheme.accent))
                .frame(width: 6, height: 6)
            
            // Workflow Info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(workflow.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color(nsColor: GeistTheme.textPrimary))
                    
                    Text(workflow.type.displayName.uppercased())
                        .font(.system(size: 9, weight: .regular))
                        .foregroundColor(Color(nsColor: GeistTheme.textTertiary))
                }
                
                if !workflow.requiredModels.isEmpty {
                    Text("Models: \(workflow.requiredModels.prefix(2).joined(separator: ", "))\(workflow.requiredModels.count > 2 ? "..." : "")")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(Color(nsColor: GeistTheme.textSecondary))
                }
            }
            
            Spacer()
            
            // Delete button
            Button(action: {
                workflowManager.deleteWorkflow(workflow)
            }) {
                Image(systemName: "trash")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(Color(nsColor: GeistTheme.textTertiary))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color(nsColor: GeistTheme.surface))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(nsColor: GeistTheme.border), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Themed Workflow Import Sheet
struct ThemedWorkflowImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var workflowManager = WorkflowManager.shared
    @State private var importType: ImportType = .file
    @State private var isImporting = false
    @State private var importError: String?
    @State private var showingFilePicker = false
    
    enum ImportType: String, CaseIterable {
        case file = "File"
        case pasteboard = "Clipboard"
        
        var icon: String {
            switch self {
            case .file: return "doc.badge.plus"
            case .pasteboard: return "doc.on.clipboard"
            }
        }
    }
    
    var body: some View {
        ZStack {
            // Background
            Color(nsColor: GeistTheme.background)
                .ignoresSafeArea()
            
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Text("Import ComfyUI Workflow")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(Color(nsColor: GeistTheme.textPrimary))
                    
                    Text("Import workflow JSON files to use them from your iPhone")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(Color(nsColor: GeistTheme.textSecondary))
                        .multilineTextAlignment(.center)
                }
                
                // Import method selector
                HStack(spacing: 8) {
                    ForEach(ImportType.allCases, id: \.self) { type in
                        Button(action: {
                            importType = type
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: type.icon)
                                    .font(.system(size: 11, weight: .regular))
                                Text(type.rawValue)
                                    .font(.system(size: 12, weight: .regular))
                            }
                            .foregroundColor(importType == type ? Color(nsColor: GeistTheme.background) : Color(nsColor: GeistTheme.textPrimary))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(importType == type ? Color(nsColor: GeistTheme.accent) : Color(nsColor: GeistTheme.surface))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color(nsColor: GeistTheme.border), lineWidth: importType == type ? 0 : 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                // Content based on import type
                Group {
                    switch importType {
                    case .file:
                        ThemedFileImportView(
                            isImporting: $isImporting,
                            importError: $importError,
                            showingFilePicker: $showingFilePicker,
                            onImportComplete: {
                                dismiss()
                            }
                        )
                        
                    case .pasteboard:
                        ThemedPasteboardImportView(
                            isImporting: $isImporting,
                            importError: $importError,
                            onImportComplete: {
                                dismiss()
                            }
                        )
                    }
                }
                .frame(minHeight: 120)
                
                // Error message
                if let importError = importError {
                    Text(importError)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(Color(nsColor: GeistTheme.error))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(nsColor: GeistTheme.surface))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color(nsColor: GeistTheme.error).opacity(0.3), lineWidth: 1)
                        )
                }
                
                // Buttons
                HStack(spacing: 12) {
                    ThemedButton(title: "Cancel", action: {
                        dismiss()
                    }, style: .secondary)
                    
                    Spacer()
                    
                    if isImporting {
                        HStack(spacing: 8) {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: Color(nsColor: GeistTheme.textSecondary)))
                                .scaleEffect(0.6)
                            Text("Importing...")
                                .font(.system(size: 11, weight: .regular))
                                .foregroundColor(Color(nsColor: GeistTheme.textSecondary))
                        }
                    }
                }
            }
            .padding(32)
        }
        .frame(width: 480, height: 360)
    }
}

// MARK: - Themed File Import View
struct ThemedFileImportView: View {
    @Binding var isImporting: Bool
    @Binding var importError: String?
    @Binding var showingFilePicker: Bool
    let onImportComplete: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.badge.plus")
                .font(.system(size: 32, weight: .light))
                .foregroundColor(Color(nsColor: GeistTheme.textTertiary))
            
            VStack(spacing: 8) {
                Text("Select ComfyUI Workflow File")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color(nsColor: GeistTheme.textPrimary))
                
                Text("Choose a .json workflow file exported from ComfyUI")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(Color(nsColor: GeistTheme.textSecondary))
                    .multilineTextAlignment(.center)
            }
            
            ThemedButton(title: "Choose File...", action: {
                showingFilePicker = true
            }, style: .primary)
            .disabled(isImporting)
        }
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            handleFileSelection(result)
        }
    }
    
    private func handleFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            importWorkflowFromFile(url)
            
        case .failure(let error):
            importError = "Failed to select file: \(error.localizedDescription)"
        }
    }
    
    private func importWorkflowFromFile(_ url: URL) {
        isImporting = true
        importError = nil
        
        Task {
            do {
                _ = try await WorkflowManager.shared.importWorkflow(from: url)
                
                await MainActor.run {
                    isImporting = false
                    onImportComplete()
                }
            } catch {
                await MainActor.run {
                    isImporting = false
                    importError = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - Themed Pasteboard Import View
struct ThemedPasteboardImportView: View {
    @Binding var isImporting: Bool
    @Binding var importError: String?
    let onImportComplete: () -> Void
    
    @State private var hasWorkflowInPasteboard = false
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 32, weight: .light))
                .foregroundColor(Color(nsColor: GeistTheme.textTertiary))
            
            VStack(spacing: 8) {
                Text("Import from Clipboard")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color(nsColor: GeistTheme.textPrimary))
                
                if hasWorkflowInPasteboard {
                    Text("ComfyUI workflow JSON detected in clipboard")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(Color(nsColor: GeistTheme.textSecondary))
                        .multilineTextAlignment(.center)
                } else {
                    Text("Copy a ComfyUI workflow JSON to your clipboard, then click refresh")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(Color(nsColor: GeistTheme.textSecondary))
                        .multilineTextAlignment(.center)
                }
            }
            
            if hasWorkflowInPasteboard {
                ThemedButton(title: "Import from Clipboard", action: {
                    importFromPasteboard()
                }, style: .primary)
                .disabled(isImporting)
            } else {
                ThemedButton(title: "Refresh", action: {
                    checkPasteboard()
                }, style: .secondary)
            }
        }
        .onAppear {
            checkPasteboard()
        }
    }
    
    private func checkPasteboard() {
        if let string = NSPasteboard.general.string(forType: .string),
           let data = string.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            
            // Check if it looks like a ComfyUI workflow
            var hasValidNodes = false
            for (_, value) in json {
                if let node = value as? [String: Any],
                   node["class_type"] != nil {
                    hasValidNodes = true
                    break
                }
            }
            
            hasWorkflowInPasteboard = hasValidNodes
        } else {
            hasWorkflowInPasteboard = false
        }
    }
    
    private func importFromPasteboard() {
        isImporting = true
        importError = nil
        
        Task {
            do {
                _ = try await WorkflowManager.shared.importWorkflowFromPasteboard()
                
                await MainActor.run {
                    isImporting = false
                    onImportComplete()
                }
            } catch {
                await MainActor.run {
                    isImporting = false
                    importError = error.localizedDescription
                }
            }
        }
    }
}

