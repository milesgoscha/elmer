//
//  ToolsView.swift
//  elmer
//
//  Tools management view
//

import SwiftUI
import AppKit

struct ToolsView: View {
    @Binding var currentView: ContentView.AppView
    @State private var isRefreshing = false
    @State private var loadedTools: [UserToolDefinition] = []
    @StateObject private var mcpManager = MCPServerManager.shared
    @State private var showingMCPServers = false
    @State private var selectedTab: Int = 0
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Padding from divider
                Spacer()
                    .frame(height: 20)
                    
                VStack(alignment: .leading, spacing: 0) {
                    // Tab Selector
                    HStack(spacing: 0) {
                        Button(action: { selectedTab = 0 }) {
                            HStack(spacing: 6) {
                                Image(systemName: "wrench.and.screwdriver")
                                    .font(.system(size: 12, weight: .medium))
                                Text("JSON Tools")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .foregroundColor(selectedTab == 0 ? Color(nsColor: GeistTheme.textPrimary) : Color(nsColor: GeistTheme.textSecondary))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(selectedTab == 0 ? Color(nsColor: GeistTheme.surface) : Color.clear)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(selectedTab == 0 ? Color(nsColor: GeistTheme.border) : Color.clear, lineWidth: 1)
                            )
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        
                        Button(action: { selectedTab = 1 }) {
                            HStack(spacing: 6) {
                                Image(systemName: "server.rack")
                                    .font(.system(size: 12, weight: .medium))
                                Text("MCP Servers")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .foregroundColor(selectedTab == 1 ? Color(nsColor: GeistTheme.textPrimary) : Color(nsColor: GeistTheme.textSecondary))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(selectedTab == 1 ? Color(nsColor: GeistTheme.surface) : Color.clear)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(selectedTab == 1 ? Color(nsColor: GeistTheme.border) : Color.clear, lineWidth: 1)
                            )
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        
                        Spacer()
                    }
                    .padding(.horizontal, 32)
                    .padding(.bottom, 24)
                    
                    // Tools Status Section
                    VStack(alignment: .leading, spacing: 0) {
                        ThemedSectionHeader(selectedTab == 0 ? "JSON Tool System" : "MCP Tool System")
                        ThemedSectionDivider()
                        
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(toolStatusColor)
                                    .frame(width: 6, height: 6)
                                Text(toolStatusText)
                                    .font(.system(size: 13, weight: .regular))
                                    .foregroundColor(Color(nsColor: GeistTheme.textPrimary))
                            }
                            
                            ThemedHelperText(text: toolHelperText)
                        }
                    }
                    .padding(.horizontal, 32)
                    .padding(.bottom, 32)
                    
                    // Content based on selected tab
                    if selectedTab == 0 {
                        // JSON Tools Management Section
                        VStack(alignment: .leading, spacing: 0) {
                            ThemedSectionHeader("Available JSON Tools",
                                actionTitle: "Reload Tools",
                                action: {
                                    refreshTools()
                                },
                                actionIcon: "arrow.clockwise",
                                secondaryActionTitle: "Open Folder",
                                secondaryAction: {
                                    openToolsFolder()
                                },
                                secondaryIcon: "folder"
                            )
                            ThemedSectionDivider()
                            
                            if !loadedTools.isEmpty {
                                VStack(spacing: 8) {
                                    ForEach(loadedTools, id: \.name) { tool in
                                        ToolCard(tool: tool)
                                    }
                                }
                            } else {
                                ThemedEmptyState(
                                    icon: "wrench.and.screwdriver",
                                    title: "No JSON tools configured",
                                    subtitle: "Add tool definitions to ~/.elmer/tools/ or copy examples"
                                )
                            }
                        }
                        .padding(.horizontal, 32)
                        .padding(.bottom, 32)
                    } else {
                        // MCP Servers Section
                        VStack(alignment: .leading, spacing: 0) {
                            ThemedSectionHeader("Available MCP Servers",
                                actionTitle: "Install Server",
                                action: {
                                    showingMCPServers = true
                                },
                                actionIcon: "plus"
                            )
                            ThemedSectionDivider()
                            
                            if !mcpManager.installedServers.isEmpty {
                                VStack(spacing: 8) {
                                    ForEach(mcpManager.installedServers) { server in
                                        MCPServerCard(server: server)
                                    }
                                }
                            } else {
                                ThemedEmptyState(
                                    icon: "server.rack",
                                    title: "No MCP servers installed",
                                    subtitle: "Install MCP servers to expand AI capabilities"
                                )
                            }
                        }
                        .padding(.horizontal, 32)
                        .padding(.bottom, 32)
                    }
                }
            }
        }
        .sheet(isPresented: $showingMCPServers) {
            MCPServerCatalogView()
                .frame(minWidth: 600, minHeight: 500)
        }
        .onAppear {
            loadTools()
        }
    }
    
    // MARK: - Computed Properties
    
    private var toolStatusColor: Color {
        if selectedTab == 0 {
            return loadedTools.isEmpty ? Color.orange : Color(nsColor: GeistTheme.success)
        } else {
            return mcpManager.installedServers.isEmpty ? Color.orange : Color(nsColor: GeistTheme.success)
        }
    }
    
    private var toolStatusText: String {
        if selectedTab == 0 {
            if loadedTools.isEmpty {
                return "No JSON tools loaded"
            } else {
                return "\(loadedTools.count) JSON tool\(loadedTools.count == 1 ? "" : "s") loaded"
            }
        } else {
            let runningCount = mcpManager.runningServers.count
            let installedCount = mcpManager.installedServers.count
            if installedCount == 0 {
                return "No MCP servers installed"
            } else if runningCount == 0 {
                return "\(installedCount) server\(installedCount == 1 ? "" : "s") installed, none running"
            } else {
                return "\(runningCount) of \(installedCount) server\(installedCount == 1 ? "" : "s") running"
            }
        }
    }
    
    private var toolHelperText: String {
        if selectedTab == 0 {
            if loadedTools.isEmpty {
                return "JSON tools enable AI models to perform custom actions like web searches, calculations, and system queries. Add tool definitions to get started."
            } else {
                return "JSON tools are loaded and ready. AI models can now use these capabilities when chatting through Elmer."
            }
        } else {
            if mcpManager.installedServers.isEmpty {
                return "MCP servers provide pre-built integrations with services like GitHub, Notion, and Figma. Install servers to expand AI capabilities."
            } else if mcpManager.runningServers.isEmpty {
                return "MCP servers are installed but not running. Start servers to make their tools available to AI models."
            } else {
                return "MCP servers are running and providing tools to AI models. Available tools: \(mcpManager.availableTools.count)"
            }
        }
    }
    
    // MARK: - Actions
    
    private func loadTools() {
        UserToolManager.shared.refreshTools()
        // Get tool definitions from UserToolManager
        loadedTools = getAllToolDefinitions()
    }
    
    private func refreshTools() {
        isRefreshing = true
        UserToolManager.shared.refreshTools()
        loadedTools = getAllToolDefinitions()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            isRefreshing = false
        }
    }
    
    private func getAllToolDefinitions() -> [UserToolDefinition] {
        // Access the loaded tools from UserToolManager
        let homeDirectory = NSHomeDirectory()
        let toolsDirectoryPath = NSString(string: homeDirectory).appendingPathComponent(".elmer/tools")
        let fileManager = FileManager.default
        
        var tools: [UserToolDefinition] = []
        
        do {
            let toolFiles = try fileManager.contentsOfDirectory(atPath: toolsDirectoryPath)
                .filter { $0.hasSuffix(".json") }
            
            for toolFile in toolFiles {
                let toolFilePath = NSString(string: toolsDirectoryPath).appendingPathComponent(toolFile)
                
                do {
                    let toolData = try Data(contentsOf: URL(fileURLWithPath: toolFilePath))
                    let toolDefinition = try JSONDecoder().decode(UserToolDefinition.self, from: toolData)
                    tools.append(toolDefinition)
                } catch {
                    print("Failed to load tool from \(toolFile): \(error)")
                }
            }
        } catch {
            print("Failed to read tools directory: \(error)")
        }
        
        return tools.sorted { $0.name < $1.name }
    }
    
    private func openToolsFolder() {
        let homeDirectory = NSHomeDirectory()
        let toolsDirectoryPath = NSString(string: homeDirectory).appendingPathComponent(".elmer/tools")
        
        // Create directory if it doesn't exist
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: toolsDirectoryPath) {
            do {
                try fileManager.createDirectory(atPath: toolsDirectoryPath, withIntermediateDirectories: true)
            } catch {
                print("Failed to create tools directory: \(error)")
                return
            }
        }
        
        let url = URL(fileURLWithPath: toolsDirectoryPath)
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Tool Card Component

struct ToolCard: View {
    let tool: UserToolDefinition
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: iconForTool(tool))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color(nsColor: GeistTheme.textSecondary))
                        .frame(width: 16, height: 16)
                    
                    Text(tool.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color(nsColor: GeistTheme.textPrimary))
                }
                
                Spacer()
                
                Text(tool.execution.type.capitalized)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Color(nsColor: GeistTheme.textTertiary))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(nsColor: GeistTheme.surface))
                    .cornerRadius(4)
            }
            
            Text(tool.description)
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(Color(nsColor: GeistTheme.textSecondary))
                .lineLimit(2)
            
            if !(tool.parameters.required?.isEmpty ?? true) {
                HStack {
                    Text("Parameters:")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color(nsColor: GeistTheme.textTertiary))
                    
                    Text((tool.parameters.required ?? []).joined(separator: ", "))
                        .font(.system(size: 10, weight: .regular))
                        .foregroundColor(Color(nsColor: GeistTheme.textSecondary))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(nsColor: GeistTheme.surface))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: GeistTheme.border), lineWidth: 1)
        )
        .cornerRadius(8)
    }
    
    private func iconForTool(_ tool: UserToolDefinition) -> String {
        switch tool.name {
        case let name where name.contains("time"):
            return "clock"
        case let name where name.contains("weather"):
            return "cloud.sun"
        case let name where name.contains("calc"):
            return "x.squareroot"
        case let name where name.contains("system"):
            return "desktopcomputer"
        case let name where name.contains("file"):
            return "folder"
        case let name where name.contains("search"):
            return "magnifyingglass"
        default:
            return "wrench.and.screwdriver"
        }
    }
}

// MARK: - Action Button Component

struct ActionButton: View {
    let icon: String
    let title: String
    let subtitle: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Color(nsColor: GeistTheme.textSecondary))
                    .frame(width: 16, height: 16)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color(nsColor: GeistTheme.textPrimary))
                    
                    Text(subtitle)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(Color(nsColor: GeistTheme.textSecondary))
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Color(nsColor: GeistTheme.textTertiary))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(nsColor: GeistTheme.surface))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(nsColor: GeistTheme.border), lineWidth: 1)
            )
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - MCP Server Card Component

struct MCPServerCard: View {
    let server: MCPServerDefinition
    @StateObject private var mcpManager = MCPServerManager.shared
    @State private var showingUninstallAlert = false
    @State private var errorMessage: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: iconForServerCategory(server.category))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color(nsColor: GeistTheme.textSecondary))
                        .frame(width: 16, height: 16)
                    
                    Text(server.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color(nsColor: GeistTheme.textPrimary))
                }
                
                Spacer()
                
                HStack(spacing: 6) {
                    if server.isRunning {
                        Circle()
                            .fill(Color(nsColor: GeistTheme.success))
                            .frame(width: 6, height: 6)
                        Text("Running")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Color(nsColor: GeistTheme.success))
                    } else {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 6, height: 6)
                        Text("Stopped")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Color.orange)
                    }
                }
            }
            
            Text(server.description)
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(Color(nsColor: GeistTheme.textSecondary))
                .lineLimit(2)
            
            HStack {
                Text(server.category.rawValue)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Color(nsColor: GeistTheme.textTertiary))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(nsColor: GeistTheme.surface))
                    .cornerRadius(4)
                
                Text(server.type.rawValue)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Color(nsColor: GeistTheme.textTertiary))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(nsColor: GeistTheme.surface))
                    .cornerRadius(4)
                
                Spacer()
                
                HStack(spacing: 4) {
                    if server.isRunning {
                        Button("Stop") {
                            Task {
                                await mcpManager.stopServer(server.name)
                            }
                        }
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color.orange)
                    } else {
                        Button("Start") {
                            Task {
                                try? await mcpManager.startServer(server.name)
                            }
                        }
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color(nsColor: GeistTheme.success))
                    }
                    
                    Button("Uninstall") {
                        showingUninstallAlert = true
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Color.red)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(nsColor: GeistTheme.surface))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: GeistTheme.border), lineWidth: 1)
        )
        .cornerRadius(8)
        .alert("Uninstall Server", isPresented: $showingUninstallAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Uninstall", role: .destructive) {
                Task {
                    do {
                        try await mcpManager.uninstallServer(server.name)
                    } catch {
                        errorMessage = "Failed to uninstall server: \(error.localizedDescription)"
                    }
                }
            }
        } message: {
            Text("Are you sure you want to uninstall \(server.name)? This will stop the server and remove all its configuration.")
        }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") {
                errorMessage = nil
            }
        } message: {
            if let errorMessage = errorMessage {
                Text(errorMessage)
            }
        }
    }
    
    private func iconForServerCategory(_ category: MCPServerCategory) -> String {
        switch category {
        case .filesystem:
            return "folder"
        case .database:
            return "cylinder"
        case .development:
            return "hammer"
        case .connectivity:
            return "globe"
        case .productivity:
            return "checklist"
        case .design:
            return "paintbrush"
        case .analytics:
            return "chart.bar"
        case .ecommerce:
            return "creditcard"
        case .ai:
            return "brain"
        case .deployment:
            return "externaldrive.connected.to.line.below"
        }
    }
}

// MARK: - MCP Server Catalog View

struct MCPServerCatalogView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var mcpManager = MCPServerManager.shared
    @State private var selectedCategory: MCPServerCategory?
    @State private var searchText = ""
    @State private var showingInstallFlow = false
    @State private var selectedServer: MCPServerDefinition?
    
    private var availableServers: [MCPServerDefinition] {
        let servers = mcpManager.getCuratedServers()
        
        var filtered = servers
        
        if let category = selectedCategory {
            filtered = filtered.filter { $0.category == category }
        }
        
        if !searchText.isEmpty {
            filtered = filtered.filter { 
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.description.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        return filtered
    }
    
    private var categories: [MCPServerCategory] {
        return Array(Set(mcpManager.getCuratedServers().map(\.category))).sorted { $0.rawValue < $1.rawValue }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("MCP Server Catalog")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Color(nsColor: GeistTheme.textPrimary))
                
                Spacer()
                
                Button("Done") {
                    dismiss()
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color(nsColor: GeistTheme.surface))
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(Color(nsColor: GeistTheme.border)),
                alignment: .bottom
            )
            
            VStack(spacing: 0) {
                // Search Bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(Color(nsColor: GeistTheme.textSecondary))
                    
                    TextField("Search servers...", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(nsColor: GeistTheme.surface))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(nsColor: GeistTheme.border), lineWidth: 1)
                )
                .padding(.horizontal, 20)
                .padding(.top, 20)
                
                // Category Filter
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Button(action: { selectedCategory = nil }) {
                            Text("All")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(selectedCategory == nil ? Color(nsColor: GeistTheme.textPrimary) : Color(nsColor: GeistTheme.textSecondary))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(selectedCategory == nil ? Color(nsColor: GeistTheme.surface) : Color.clear)
                                .cornerRadius(16)
                        }
                        .buttonStyle(.plain)
                        
                        ForEach(categories, id: \.self) { category in
                            Button(action: { selectedCategory = category }) {
                                Text(category.rawValue)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(selectedCategory == category ? Color(nsColor: GeistTheme.textPrimary) : Color(nsColor: GeistTheme.textSecondary))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(selectedCategory == category ? Color(nsColor: GeistTheme.surface) : Color.clear)
                                    .cornerRadius(16)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.top, 16)
                
                // Server List
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(availableServers) { server in
                            Button(action: {
                                // Only show install flow if server is not already installed
                                if !mcpManager.installedServers.contains(where: { $0.name == server.name }) {
                                    selectedServer = server
                                    showingInstallFlow = true
                                }
                            }) {
                                CatalogServerCard(server: server)
                            }
                            .buttonStyle(.plain)
                            .disabled(mcpManager.installedServers.contains { $0.name == server.name })
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 20)
                }
            }
        }
        .sheet(isPresented: $showingInstallFlow) {
            if let server = selectedServer {
                MCPServerInstallView(server: server) {
                    showingInstallFlow = false
                    dismiss()
                }
                .frame(minWidth: 500, minHeight: 600)
            }
        }
    }
}

// MARK: - Catalog Server Card

struct CatalogServerCard: View {
    let server: MCPServerDefinition
    @StateObject private var mcpManager = MCPServerManager.shared
    
    private var isInstalled: Bool {
        mcpManager.installedServers.contains { $0.name == server.name }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: iconForServerCategory(server.category))
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(Color(nsColor: GeistTheme.textSecondary))
                        .frame(width: 20, height: 20)
                    
                    Text(server.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color(nsColor: GeistTheme.textPrimary))
                }
                
                Spacer()
                
                HStack(spacing: 6) {
                    if isInstalled {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(Color(nsColor: GeistTheme.success))
                            Text("Installed")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(Color(nsColor: GeistTheme.success))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(nsColor: GeistTheme.success).opacity(0.1))
                        .cornerRadius(4)
                    }
                    
                    Text(server.category.rawValue)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color(nsColor: GeistTheme.textTertiary))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(nsColor: GeistTheme.surface))
                        .cornerRadius(4)
                    
                    if !isInstalled {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Color(nsColor: GeistTheme.textTertiary))
                    }
                }
            }
            
            Text(server.description)
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(Color(nsColor: GeistTheme.textSecondary))
                .multilineTextAlignment(.leading)
                .lineLimit(2)
            
            if !server.configRequirements.isEmpty {
                HStack {
                    Image(systemName: "gear")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color(nsColor: GeistTheme.textTertiary))
                    
                    Text("Requires configuration")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color(nsColor: GeistTheme.textTertiary))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(nsColor: GeistTheme.surface))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: GeistTheme.border), lineWidth: 1)
        )
        .cornerRadius(8)
    }
    
    private func iconForServerCategory(_ category: MCPServerCategory) -> String {
        switch category {
        case .filesystem:
            return "folder"
        case .database:
            return "cylinder"
        case .development:
            return "hammer"
        case .connectivity:
            return "globe"
        case .productivity:
            return "checklist"
        case .design:
            return "paintbrush"
        case .analytics:
            return "chart.bar"
        case .ecommerce:
            return "creditcard"
        case .ai:
            return "brain"
        case .deployment:
            return "externaldrive.connected.to.line.below"
        }
    }
}

// MARK: - MCP Server Install View

struct MCPServerInstallView: View {
    let server: MCPServerDefinition
    let onInstall: () -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var mcpManager = MCPServerManager.shared
    
    @State private var configValues: [String: String] = [:]
    @State private var isInstalling = false
    @State private var installError: String?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Install \(server.name)")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Color(nsColor: GeistTheme.textPrimary))
                
                Spacer()
                
                HStack(spacing: 12) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isInstalling)
                    
                    Button(isInstalling ? "Installing..." : "Install") {
                        installServer()
                    }
                    .disabled(isInstalling || !isConfigurationValid)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color(nsColor: GeistTheme.surface))
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(Color(nsColor: GeistTheme.border)),
                alignment: .bottom
            )
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Server Info
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: iconForServerCategory(server.category))
                                .font(.system(size: 24, weight: .medium))
                                .foregroundColor(Color(nsColor: GeistTheme.textSecondary))
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(server.name)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(Color(nsColor: GeistTheme.textPrimary))
                                
                                Text(server.category.rawValue)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(Color(nsColor: GeistTheme.textTertiary))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Color(nsColor: GeistTheme.surface))
                                    .cornerRadius(4)
                            }
                            
                            Spacer()
                        }
                        
                        Text(server.description)
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(Color(nsColor: GeistTheme.textSecondary))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    
                    Divider()
                        .background(Color(nsColor: GeistTheme.border))
                    
                    // Configuration Section
                    if !server.configRequirements.isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Configuration")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(Color(nsColor: GeistTheme.textPrimary))
                            
                            Text("This server requires configuration before it can be used:")
                                .font(.system(size: 13, weight: .regular))
                                .foregroundColor(Color(nsColor: GeistTheme.textSecondary))
                            
                            VStack(spacing: 12) {
                                ForEach(server.configRequirements, id: \.key) { requirement in
                                    ConfigField(
                                        requirement: requirement,
                                        value: Binding(
                                            get: { configValues[requirement.key] ?? requirement.defaultValue ?? "" },
                                            set: { configValues[requirement.key] = $0 }
                                        )
                                    )
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Ready to Install")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(Color(nsColor: GeistTheme.textPrimary))
                            
                            Text("This server doesn't require any configuration and is ready to install.")
                                .font(.system(size: 13, weight: .regular))
                                .foregroundColor(Color(nsColor: GeistTheme.textSecondary))
                        }
                        .padding(.horizontal, 20)
                    }
                    
                    // Technical Details
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Technical Details")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Color(nsColor: GeistTheme.textPrimary))
                        
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Type:")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(Color(nsColor: GeistTheme.textSecondary))
                                
                                Spacer()
                                
                                Text(server.type.rawValue)
                                    .font(.system(size: 12, weight: .regular))
                                    .foregroundColor(Color(nsColor: GeistTheme.textPrimary))
                            }
                            
                            if let package = server.package {
                                HStack {
                                    Text("Package:")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(Color(nsColor: GeistTheme.textSecondary))
                                    
                                    Spacer()
                                    
                                    Text(package)
                                        .font(.system(size: 12, weight: .regular))
                                        .foregroundColor(Color(nsColor: GeistTheme.textPrimary))
                                }
                            }
                            
                            HStack {
                                Text("Command:")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(Color(nsColor: GeistTheme.textSecondary))
                                
                                Spacer()
                                
                                Text("\(server.command) \(server.args.joined(separator: " "))")
                                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                                    .foregroundColor(Color(nsColor: GeistTheme.textPrimary))
                                    .lineLimit(2)
                                    .truncationMode(.middle)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color(nsColor: GeistTheme.surface))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color(nsColor: GeistTheme.border), lineWidth: 1)
                        )
                    }
                    .padding(.horizontal, 20)
                    
                    // Error Display
                    if let error = installError {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text("Installation Error")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.orange)
                            }
                            
                            Text(error)
                                .font(.system(size: 12, weight: .regular))
                                .foregroundColor(Color(nsColor: GeistTheme.textSecondary))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                        )
                        .padding(.horizontal, 20)
                    }
                    
                    Spacer(minLength: 50)
                }
            }
        }
        .onAppear {
            // Initialize config values with defaults
            for requirement in server.configRequirements {
                if configValues[requirement.key] == nil {
                    configValues[requirement.key] = requirement.defaultValue ?? ""
                }
            }
        }
    }
    
    private var isConfigurationValid: Bool {
        for requirement in server.configRequirements {
            if requirement.required && (configValues[requirement.key]?.isEmpty ?? true) {
                return false
            }
        }
        return true
    }
    
    private func installServer() {
        isInstalling = true
        installError = nil
        
        Task {
            do {
                try await mcpManager.installServer(server, config: configValues)
                
                await MainActor.run {
                    onInstall()
                }
            } catch {
                await MainActor.run {
                    installError = error.localizedDescription
                    isInstalling = false
                }
            }
        }
    }
    
    private func iconForServerCategory(_ category: MCPServerCategory) -> String {
        switch category {
        case .filesystem:
            return "folder"
        case .database:
            return "cylinder"
        case .development:
            return "hammer"
        case .connectivity:
            return "globe"
        case .productivity:
            return "checklist"
        case .design:
            return "paintbrush"
        case .analytics:
            return "chart.bar"
        case .ecommerce:
            return "creditcard"
        case .ai:
            return "brain"
        case .deployment:
            return "externaldrive.connected.to.line.below"
        }
    }
}

// MARK: - Config Field Component

struct ConfigField: View {
    let requirement: MCPConfigRequirement
    @Binding var value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(requirement.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color(nsColor: GeistTheme.textPrimary))
                
                if requirement.required {
                    Text("*")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.red)
                }
                
                Spacer()
            }
            
            Group {
                switch requirement.type {
                case .password:
                    SecureField("Enter \(requirement.displayName.lowercased())", text: $value)
                        .textFieldStyle(.plain)
                case .path:
                    HStack {
                        TextField("Enter file path", text: $value)
                            .textFieldStyle(.plain)
                        
                        Button("Browse") {
                            selectFile()
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color(nsColor: GeistTheme.textSecondary))
                    }
                case .url:
                    TextField("https://example.com", text: $value)
                        .textFieldStyle(.plain)
                case .boolean:
                    Toggle("Enable", isOn: Binding(
                        get: { value.lowercased() == "true" },
                        set: { value = $0 ? "true" : "false" }
                    ))
                case .text:
                    TextField("Enter \(requirement.displayName.lowercased())", text: $value)
                        .textFieldStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: GeistTheme.surface))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: GeistTheme.border), lineWidth: 1)
            )
            
            if !requirement.description.isEmpty {
                Text(requirement.description)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(Color(nsColor: GeistTheme.textSecondary))
            }
        }
    }
    
    private func selectFile() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = requirement.type == .path && requirement.key != "workspace_path"
        panel.allowsMultipleSelection = false
        
        if panel.runModal() == .OK {
            if let url = panel.url {
                value = url.path
            }
        }
    }
}