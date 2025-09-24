//
//  MCPServerManager.swift
//  elmer
//
//  MCP (Model Context Protocol) server management
//

import Foundation
import Network

// MARK: - MCP Server Models

struct MCPServerDefinition: Codable, Identifiable {
    let id = UUID()
    let name: String
    let description: String
    let package: String?
    let type: MCPServerType
    let command: String
    let args: [String]
    let environment: [String: String]
    let configRequirements: [MCPConfigRequirement]
    let category: MCPServerCategory
    let isInstalled: Bool
    let isRunning: Bool
    let port: Int?
    let url: String?
    
    enum CodingKeys: String, CodingKey {
        case name, description, package, type, command, args, environment
        case configRequirements, category, isInstalled, isRunning, port, url
    }
}

enum MCPServerType: String, Codable {
    case stdio
    case streamableHttp = "streamableHttp"
}

enum MCPServerCategory: String, Codable {
    case filesystem = "File System"
    case database = "Database"
    case development = "Development"
    case connectivity = "Connectivity"
    case productivity = "Productivity" 
    case design = "Design"
    case analytics = "Analytics"
    case ecommerce = "E-commerce"
    case ai = "AI/ML"
    case deployment = "Deployment"
}

struct MCPConfigRequirement: Codable {
    let key: String
    let displayName: String
    let type: ConfigType
    let required: Bool
    let defaultValue: String?
    let description: String
    
    enum ConfigType: String, Codable {
        case text
        case password
        case path
        case url
        case boolean
    }
}

struct MCPTool: Codable {
    let name: String
    let description: String
    let parameters: [String: Any]
    let serverName: String
    
    enum CodingKeys: String, CodingKey {
        case name, description, parameters, serverName
    }
    
    init(name: String, description: String, parameters: [String: Any], serverName: String) {
        self.name = name
        self.description = description
        self.parameters = parameters
        self.serverName = serverName
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decode(String.self, forKey: .description)
        serverName = try container.decode(String.self, forKey: .serverName)
        
        // Handle Any parameters
        if let params = try? container.decode([String: String].self, forKey: .parameters) {
            parameters = params
        } else {
            parameters = [:]
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(description, forKey: .description)
        try container.encode(serverName, forKey: .serverName)
        // Skip parameters encoding for now
    }
}

// MARK: - MCP Server Manager

class MCPServerManager: ObservableObject {
    static let shared = MCPServerManager()
    
    @Published var installedServers: [MCPServerDefinition] = []
    @Published var runningServers: [String] = []
    @Published var availableTools: [MCPTool] = []
    
    private var serverProcesses: [String: Process] = [:]
    private let configDirectory: URL
    private let serversDirectory: URL
    
    init() {
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        configDirectory = homeDirectory.appendingPathComponent(".elmer/mcp-servers")
        serversDirectory = configDirectory.appendingPathComponent("servers")
        
        createDirectoriesIfNeeded()
        loadInstalledServers()
    }
    
    // MARK: - Directory Management
    
    private func createDirectoriesIfNeeded() {
        let fileManager = FileManager.default
        
        do {
            try fileManager.createDirectory(at: configDirectory, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: serversDirectory, withIntermediateDirectories: true)
        } catch {
            print("Failed to create MCP directories: \(error)")
        }
    }
    
    // MARK: - Server Catalog
    
    func getCuratedServers() -> [MCPServerDefinition] {
        return [
            // Filesystem Operations - Essential for computer use
            MCPServerDefinition(
                name: "Filesystem Operations",
                description: "Read, write, create, and manage files and directories",
                package: "@modelcontextprotocol/server-filesystem",
                type: .stdio,
                command: "npx",
                args: ["@modelcontextprotocol/server-filesystem", "{workspace_path}"],
                environment: [:],
                configRequirements: [
                    MCPConfigRequirement(
                        key: "workspace_path",
                        displayName: "Workspace Directory",
                        type: .path,
                        required: true,
                        defaultValue: NSHomeDirectory() + "/Documents",
                        description: "Directory that the AI can access for file operations"
                    )
                ],
                category: .filesystem,
                isInstalled: isServerInstalled("Filesystem Operations"),
                isRunning: isServerRunning("Filesystem Operations"),
                port: nil,
                url: nil
            ),
            
            // Browser MCP - Local browser control
            MCPServerDefinition(
                name: "Browser MCP",
                description: "Direct browser control and web page interaction",
                package: "@browsermcp/mcp",
                type: .stdio,
                command: "npx",
                args: ["@browsermcp/mcp@latest"],
                environment: [:],
                configRequirements: [],
                category: .connectivity,
                isInstalled: isServerInstalled("Browser MCP"),
                isRunning: isServerRunning("Browser MCP"),
                port: nil,
                url: nil
            ),
            
            // Fetch MCP - Web content retrieval  
            MCPServerDefinition(
                name: "Fetch MCP",
                description: "Fetch web content and convert HTML to markdown for easy processing",
                package: "@kazuph/mcp-fetch", 
                type: .stdio,
                command: "npx",
                args: ["-y", "@kazuph/mcp-fetch"],
                environment: [:],
                configRequirements: [],
                category: .connectivity,
                isInstalled: isServerInstalled("Fetch MCP"),
                isRunning: isServerRunning("Fetch MCP"),
                port: nil,
                url: nil
            )
        ]
    }
    
    // MARK: - Server Installation
    
    func installServer(_ serverDef: MCPServerDefinition, config: [String: String]) async throws {
        print("🔧 Debug: Installing server \(serverDef.name) with config keys: \(Array(config.keys))")
        print("🔧 Debug: Config values: \(config)")
        
        // Validate configuration
        for requirement in serverDef.configRequirements {
            if requirement.required && (config[requirement.key]?.isEmpty ?? true) {
                throw MCPError.missingRequiredConfig(requirement.key)
            }
        }
        
        // Create server configuration
        let installedServer = serverDef
        var processedArgs = serverDef.args
        var processedEnv = serverDef.environment
        
        // Replace configuration placeholders
        for (key, value) in config {
            processedArgs = processedArgs.map { $0.replacingOccurrences(of: "{\(key)}", with: value) }
            processedEnv = processedEnv.mapValues { $0.replacingOccurrences(of: "{\(key)}", with: value) }
        }
        
        // Add config directly to environment for streamableHttp servers
        for (key, value) in config {
            processedEnv[key] = value
        }
        
        print("🔧 Debug: Final processed environment keys: \(Array(processedEnv.keys))")
        print("🔧 Debug: Final processed environment: \(processedEnv)")
        
        // Create final server definition
        let finalServer = MCPServerDefinition(
            name: installedServer.name,
            description: installedServer.description,
            package: installedServer.package,
            type: installedServer.type,
            command: installedServer.command,
            args: processedArgs,
            environment: processedEnv,
            configRequirements: installedServer.configRequirements,
            category: installedServer.category,
            isInstalled: true,
            isRunning: false,
            port: installedServer.port,
            url: installedServer.url
        )
        
        // Save server configuration
        let serverConfigPath = serversDirectory.appendingPathComponent("\(serverDef.name.lowercased().replacingOccurrences(of: " ", with: "-")).json")
        let configData = try JSONEncoder().encode(finalServer)
        try configData.write(to: serverConfigPath)
        
        // Update installed servers
        await MainActor.run {
            if let index = installedServers.firstIndex(where: { $0.name == serverDef.name }) {
                installedServers[index] = finalServer
            } else {
                installedServers.append(finalServer)
            }
        }
    }
    
    // MARK: - Server Management
    
    func startServer(_ serverName: String) async throws {
        guard let server = installedServers.first(where: { $0.name == serverName }) else {
            throw MCPError.serverNotFound(serverName)
        }
        
        // Check if process exists but might be dead
        if let existingProcess = serverProcesses[serverName] {
            if !existingProcess.isRunning {
                print("🔄 Cleaning up dead process for \(serverName)")
                serverProcesses.removeValue(forKey: serverName)
                await MainActor.run {
                    runningServers.removeAll { $0 == serverName }
                }
            } else {
                print("✅ Server \(serverName) is already running")
                return
            }
        }
        
        guard !isServerRunning(serverName) else {
            return // Already running
        }
        
        switch server.type {
        case .stdio:
            let process = Process()
            // Better path detection for npx/node
            if server.command == "npx" {
                // Use which command to find npx
                let whichProcess = Process()
                whichProcess.executableURL = URL(fileURLWithPath: "/usr/bin/which")
                whichProcess.arguments = ["npx"]
                let whichPipe = Pipe()
                whichProcess.standardOutput = whichPipe
                whichProcess.standardError = Pipe()
                
                var npxPath: String?
                do {
                    try whichProcess.run()
                    whichProcess.waitUntilExit()
                    let data = whichPipe.fileHandleForReading.readDataToEndOfFile()
                    npxPath = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                } catch {
                    print("⚠️ Could not find npx via which command")
                }
                
                if let npxPath = npxPath, !npxPath.isEmpty {
                    process.executableURL = URL(fileURLWithPath: npxPath)
                    process.arguments = server.args
                } else {
                    // Fallback to common locations
                    let npxPaths = ["/opt/homebrew/bin/npx", "/usr/local/bin/npx", "/usr/bin/npx"]
                    var foundPath = "/usr/bin/env"
                    var arguments = ["npx"] + server.args
                    
                    for path in npxPaths {
                        if FileManager.default.fileExists(atPath: path) {
                            foundPath = path
                            arguments = server.args
                            break
                        }
                    }
                    
                    process.executableURL = URL(fileURLWithPath: foundPath)
                    process.arguments = arguments
                }
            } else {
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = [server.command] + server.args
            }
            // Set up environment with proper PATH for npm/node
            var environment = ProcessInfo.processInfo.environment.merging(server.environment) { _, new in new }
            
            // Add common Node.js paths to PATH
            let nodePaths = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"]
            let currentPath = environment["PATH"] ?? ""
            let additionalPaths = nodePaths.joined(separator: ":")
            environment["PATH"] = "\(additionalPaths):\(currentPath)"
            
            process.environment = environment
            
            print("🚀 Starting server \(serverName) with command: \(server.command) \(server.args.joined(separator: " "))")
            
            // Setup pipes for communication
            let inputPipe = Pipe()
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            
            process.standardInput = inputPipe
            process.standardOutput = outputPipe
            process.standardError = errorPipe
            
            // Add error monitoring
            errorPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if let errorOutput = String(data: data, encoding: .utf8), !errorOutput.isEmpty {
                    // Filter out non-critical npm warnings
                    if !errorOutput.contains("npm WARN") && !errorOutput.contains("npm notice") {
                        print("❌ Server \(serverName) stderr: \(errorOutput)")
                    }
                }
            }
            
            // Monitor process termination
            process.terminationHandler = { [weak self] process in
                print("🛑 Server \(serverName) terminated with status \(process.terminationStatus)")
                Task { @MainActor in
                    self?.serverProcesses.removeValue(forKey: serverName)
                    self?.runningServers.removeAll { $0 == serverName }
                    self?.availableTools.removeAll { $0.serverName == serverName }
                    
                    // Update installed server status
                    if let index = self?.installedServers.firstIndex(where: { $0.name == serverName }),
                       let installedServers = self?.installedServers {
                        let server = installedServers[index]
                        self?.installedServers[index] = MCPServerDefinition(
                            name: server.name,
                            description: server.description,
                            package: server.package,
                            type: server.type,
                            command: server.command,
                            args: server.args,
                            environment: server.environment,
                            configRequirements: server.configRequirements,
                            category: server.category,
                            isInstalled: server.isInstalled,
                            isRunning: false,
                            port: server.port,
                            url: server.url
                        )
                    }
                }
            }
            
            try process.run()
            serverProcesses[serverName] = process
            
            print("✅ Server \(serverName) started with PID: \(process.processIdentifier)")
            
            // Give the server a moment to start up
            try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            
        case .streamableHttp:
            // For streamableHttp servers, we don't start a local process
            // Instead, we just mark them as running so tools can be discovered
            // The actual communication happens via HTTP requests to the configured URL
            break
        }
        
        await MainActor.run {
            runningServers.append(serverName)
            if let index = installedServers.firstIndex(where: { $0.name == serverName }) {
                let updatedServer = installedServers[index]
                // Note: Can't modify isRunning directly due to let property, would need to recreate
                installedServers[index] = MCPServerDefinition(
                    name: updatedServer.name,
                    description: updatedServer.description,
                    package: updatedServer.package,
                    type: updatedServer.type,
                    command: updatedServer.command,
                    args: updatedServer.args,
                    environment: updatedServer.environment,
                    configRequirements: updatedServer.configRequirements,
                    category: updatedServer.category,
                    isInstalled: updatedServer.isInstalled,
                    isRunning: true,
                    port: updatedServer.port,
                    url: updatedServer.url
                )
            }
        }
        
        // Discover tools after server starts
        await discoverServerTools(serverName)
    }
    
    func stopServer(_ serverName: String) async {
        guard let process = serverProcesses[serverName] else { return }
        
        process.terminate()
        process.waitUntilExit()
        serverProcesses.removeValue(forKey: serverName)
        
        await MainActor.run {
            runningServers.removeAll { $0 == serverName }
            availableTools.removeAll { $0.serverName == serverName }
            
            if let index = installedServers.firstIndex(where: { $0.name == serverName }) {
                let server = installedServers[index]
                installedServers[index] = MCPServerDefinition(
                    name: server.name,
                    description: server.description,
                    package: server.package,
                    type: server.type,
                    command: server.command,
                    args: server.args,
                    environment: server.environment,
                    configRequirements: server.configRequirements,
                    category: server.category,
                    isInstalled: server.isInstalled,
                    isRunning: false,
                    port: server.port,
                    url: server.url
                )
            }
        }
    }
    
    func uninstallServer(_ serverName: String) async throws {
        // Stop server if running
        if isServerRunning(serverName) {
            await stopServer(serverName)
        }
        
        // Remove server configuration file
        let serverConfigPath = serversDirectory.appendingPathComponent("\(serverName.lowercased().replacingOccurrences(of: " ", with: "-")).json")
        
        do {
            if FileManager.default.fileExists(atPath: serverConfigPath.path) {
                try FileManager.default.removeItem(at: serverConfigPath)
                print("🗑️ Removed server config: \(serverConfigPath.lastPathComponent)")
            }
        } catch {
            print("❌ Failed to remove server config: \(error)")
            throw MCPError.communicationError("Failed to remove server configuration: \(error.localizedDescription)")
        }
        
        await MainActor.run {
            // Remove from installed servers list
            installedServers.removeAll { $0.name == serverName }
            // Remove any remaining tools
            availableTools.removeAll { $0.serverName == serverName }
            print("✅ Uninstalled MCP server: \(serverName)")
        }
    }
    
    // MARK: - Tool Discovery and Execution
    
    private func discoverServerTools(_ serverName: String) async {
        guard let server = installedServers.first(where: { $0.name == serverName }) else { return }
        
        switch server.type {
        case .stdio:
            await discoverStdioTools(serverName: serverName)
        case .streamableHttp:
            await discoverHttpTools(server: server)
        }
    }
    
    private func discoverStdioTools(serverName: String) async {
        guard let process = serverProcesses[serverName] else { 
            print("❌ No process found for server: \(serverName)")
            return 
        }
        
        print("🔍 Attempting to discover tools for \(serverName)...")
        
        // Send MCP tools/list request
        let listRequest = [
            "jsonrpc": "2.0",
            "id": UUID().uuidString,
            "method": "tools/list",
            "params": [:]
        ] as [String: Any]
        
        do {
            let requestData = try JSONSerialization.data(withJSONObject: listRequest)
            let requestString = String(data: requestData, encoding: .utf8)! + "\n"
            
            if let stdin = process.standardInput as? Pipe,
               let stdout = process.standardOutput as? Pipe {
                
                // Use actor-safe pattern for reading response
                class ResponseReader {
                    var responseBuffer = Data()
                    var hasCompleted = false
                }
                
                let reader = ResponseReader()
                
                let responseData = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
                    stdout.fileHandleForReading.readabilityHandler = { handle in
                        let data = handle.availableData
                        if data.count > 0 {
                            reader.responseBuffer.append(data)
                            // Check if we have a complete JSON response
                            if let responseString = String(data: reader.responseBuffer, encoding: .utf8),
                               responseString.contains("}") && (responseString.contains("result") || responseString.contains("error")) {
                                if !reader.hasCompleted {
                                    reader.hasCompleted = true
                                    stdout.fileHandleForReading.readabilityHandler = nil
                                    continuation.resume(returning: reader.responseBuffer)
                                }
                            }
                        }
                    }
                    
                    // Send request
                    stdin.fileHandleForWriting.write(requestString.data(using: .utf8)!)
                    
                    // Set up timeout
                    Task {
                        try await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
                        if !reader.hasCompleted {
                            reader.hasCompleted = true
                            stdout.fileHandleForReading.readabilityHandler = nil
                            continuation.resume(throwing: MCPError.communicationError("Timeout waiting for tool discovery"))
                        }
                    }
                }
                
                // Process the response data
                if let responseString = String(data: responseData, encoding: .utf8),
                   let responseJson = try? JSONSerialization.jsonObject(with: responseString.data(using: .utf8)!) as? [String: Any],
                   let result = responseJson["result"] as? [String: Any],
                   let tools = result["tools"] as? [[String: Any]] {
                        
                        let mcpTools = tools.compactMap { toolDict -> MCPTool? in
                            guard let name = toolDict["name"] as? String,
                                  let description = toolDict["description"] as? String else {
                                print("🔍 Skipping tool due to missing name or description: \(toolDict)")
                                return nil
                            }
                            
                            let parameters = toolDict["inputSchema"] as? [String: Any] ?? [:]
                            print("🔍 Discovered tool '\(name)' from \(serverName):")
                            print("🔍   Description: \(description)")
                            print("🔍   Parameters: \(parameters)")
                            
                            return MCPTool(name: name, description: description, parameters: parameters, serverName: serverName)
                        }
                        
                        await MainActor.run {
                            // Remove existing tools for this server
                            availableTools.removeAll { $0.serverName == serverName }
                            // Add discovered tools
                            availableTools.append(contentsOf: mcpTools)
                        }
                        
                        print("🔍 Discovered \(mcpTools.count) tools from \(serverName): \(mcpTools.map { $0.name }.joined(separator: ", "))")
                        return
                } else {
                    print("⚠️ No valid tools in response from \(serverName)")
                }
            } else {
                print("⚠️ No stdin/stdout pipes available for \(serverName)")
            }
        } catch {
            print("❌ Failed to discover tools from \(serverName): \(error)")
        }
        
        // Only use fallback for known problematic servers during initial setup
        // This should be removed once proper MCP communication is established
        if serverName.contains("Filesystem") && availableTools.filter({ $0.serverName == serverName }).isEmpty {
            print("⚠️ Using fallback tools for \(serverName) - MCP discovery may have failed")
            let filesystemTools = [
                MCPTool(
                    name: "read_file",
                    description: "Read the contents of a file",
                    parameters: [
                        "type": "object",
                        "properties": [
                            "path": [
                                "type": "string",
                                "description": "The file path to read"
                            ]
                        ],
                        "required": ["path"]
                    ],
                    serverName: serverName
                ),
                MCPTool(
                    name: "write_file", 
                    description: "Write content to a file",
                    parameters: [
                        "type": "object",
                        "properties": [
                            "path": [
                                "type": "string",
                                "description": "The file path to write to"
                            ],
                            "content": [
                                "type": "string", 
                                "description": "The content to write"
                            ]
                        ],
                        "required": ["path", "content"]
                    ],
                    serverName: serverName
                ),
                MCPTool(
                    name: "list_directory",
                    description: "List contents of a directory", 
                    parameters: [
                        "type": "object",
                        "properties": [
                            "path": [
                                "type": "string",
                                "description": "The directory path to list"
                            ]
                        ],
                        "required": ["path"]
                    ],
                    serverName: serverName
                )
            ]
            
            await MainActor.run {
                // Remove existing tools for this server
                availableTools.removeAll { $0.serverName == serverName }
                // Add filesystem tools
                availableTools.append(contentsOf: filesystemTools)
            }
            
            print("🗂️ Added fallback filesystem tools: \(filesystemTools.map { $0.name }.joined(separator: ", "))")
        }
    }
    
    private func discoverHttpTools(server: MCPServerDefinition) async {
        guard let url = server.url else {
            print("❌ No URL configured for streamableHttp server: \(server.name)")
            return
        }
        
        guard let serverURL = URL(string: url) else {
            print("❌ Invalid URL for server \(server.name): \(url)")
            return
        }
        
        // Send MCP tools/list request via HTTP
        let listRequest = [
            "jsonrpc": "2.0",
            "id": UUID().uuidString,
            "method": "tools/list",
            "params": [:]
        ] as [String: Any]
        
        var request = URLRequest(url: serverURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Add authentication if API key is configured
        if !server.environment.isEmpty {
            print("🔑 Debug: Server environment keys: \(Array(server.environment.keys))")
            if let apiKey = server.environment.first?.value {
                print("🔑 Debug: Using API key (first 10 chars): \(String(apiKey.prefix(10)))...")
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            }
        } else {
            print("🔑 Debug: No API key found in server environment")
        }
        
        do {
            let requestData = try JSONSerialization.data(withJSONObject: listRequest)
            request.httpBody = requestData
            
            let (responseData, httpResponse) = try await URLSession.shared.data(for: request)
            
            // Check HTTP status
            if let httpResponse = httpResponse as? HTTPURLResponse {
                guard httpResponse.statusCode == 200 else {
                    let errorMessage = String(data: responseData, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
                    print("❌ HTTP error discovering tools from \(server.name): \(errorMessage)")
                    return
                }
            }
            
            // Parse MCP response
            if let responseJson = try JSONSerialization.jsonObject(with: responseData) as? [String: Any] {
                if let result = responseJson["result"] as? [String: Any],
                   let tools = result["tools"] as? [[String: Any]] {
                    
                    let mcpTools = tools.compactMap { toolDict -> MCPTool? in
                        guard let name = toolDict["name"] as? String,
                              let description = toolDict["description"] as? String else {
                            print("🔍 Skipping HTTP tool due to missing name or description: \(toolDict)")
                            return nil
                        }
                        
                        let parameters = toolDict["inputSchema"] as? [String: Any] ?? [:]
                        print("🔍 Discovered HTTP tool '\(name)' from \(server.name):")
                        print("🔍   Description: \(description)")
                        print("🔍   Parameters: \(parameters)")
                        
                        return MCPTool(name: name, description: description, parameters: parameters, serverName: server.name)
                    }
                    
                    await MainActor.run {
                        // Remove existing tools for this server
                        availableTools.removeAll { $0.serverName == server.name }
                        // Add discovered tools
                        availableTools.append(contentsOf: mcpTools)
                    }
                    
                    print("🔍 Discovered \(mcpTools.count) HTTP tools from \(server.name): \(mcpTools.map { $0.name }.joined(separator: ", "))")
                    return
                }
                
                if let error = responseJson["error"] as? [String: Any],
                   let message = error["message"] as? String {
                    print("❌ MCP error discovering tools from \(server.name): \(message)")
                    return
                }
            }
            
        } catch {
            print("❌ Failed to discover HTTP tools from \(server.name): \(error)")
        }
    }
    
    func executeMCPTool(toolName: String, arguments: [String: Any]) async throws -> String {
        print("🔧 Debug: Executing MCP tool '\(toolName)' with arguments: \(arguments)")
        
        // Extract the actual tool name from the prefixed format
        let actualToolName = toolName.hasPrefix("mcp__") ? 
            String(toolName.split(separator: "_").dropFirst(2).joined(separator: "_")) : toolName
        
        print("🔧 Debug: Extracted actual tool name: '\(actualToolName)'")
        
        guard let tool = availableTools.first(where: { 
            $0.name == actualToolName || "mcp__\($0.serverName)__\($0.name)" == toolName 
        }) else {
            print("❌ Tool '\(toolName)' not found. Available tools: \(availableTools.map { "mcp__\($0.serverName)__\($0.name)" })")
            throw MCPError.toolNotFound(toolName)
        }
        
        print("🔧 Debug: Found tool '\(tool.name)' for server: '\(tool.serverName)'")
        
        // Try to restart server if it's not running
        if !isServerRunning(tool.serverName) {
            print("⚠️ Server '\(tool.serverName)' is not running. Attempting to restart...")
            do {
                try await startServer(tool.serverName)
                // Wait a moment for server to initialize
                try await Task.sleep(nanoseconds: 2_000_000_000)
            } catch {
                print("❌ Failed to restart server '\(tool.serverName)': \(error)")
                throw MCPError.serverNotRunning(tool.serverName)
            }
        }
        
        guard isServerRunning(tool.serverName) else {
            print("❌ Server '\(tool.serverName)' is still not running after restart attempt")
            throw MCPError.serverNotRunning(tool.serverName)
        }
        
        guard let server = installedServers.first(where: { $0.name == tool.serverName }) else {
            print("❌ Server '\(tool.serverName)' not found in installed servers")
            throw MCPError.serverNotFound(tool.serverName)
        }
        
        print("🔧 Debug: Using server type: \(server.type)")
        
        // Handle different server types
        switch server.type {
        case .stdio:
            return try await executeStdioTool(server: server, toolName: actualToolName, arguments: arguments)
        case .streamableHttp:
            return try await executeHttpTool(server: server, toolName: actualToolName, arguments: arguments)
        }
    }
    
    private func executeStdioTool(server: MCPServerDefinition, toolName: String, arguments: [String: Any]) async throws -> String {
        print("🔧 Debug: Executing stdio tool '\(toolName)' on server '\(server.name)' with arguments: \(arguments)")
        
        // For streamableHttp servers like Notion, redirect to HTTP execution
        if server.type == .streamableHttp {
            print("🔄 Redirecting \(server.name) to HTTP execution")
            return try await executeHttpTool(server: server, toolName: toolName, arguments: arguments)
        }
        
        guard let process = serverProcesses[server.name] else {
            print("❌ No process found for server '\(server.name)'")
            throw MCPError.serverNotRunning(server.name)
        }
        
        print("🔧 Debug: Found process with PID: \(process.processIdentifier)")
        
        // Check if process is still running
        guard process.isRunning else {
            print("❌ Process for \(server.name) is not running")
            throw MCPError.serverNotRunning(server.name)
        }
        
        // Send MCP tools/call request
        let callRequest = [
            "jsonrpc": "2.0",
            "id": UUID().uuidString,
            "method": "tools/call",
            "params": [
                "name": toolName,
                "arguments": arguments
            ]
        ] as [String: Any]
        
        do {
            let requestData = try JSONSerialization.data(withJSONObject: callRequest)
            let requestString = String(data: requestData, encoding: .utf8)! + "\n"
            
            // Enhanced debugging for quotation mark issues
            print("🔧 Debug: Raw arguments before serialization: \(arguments)")
            for (key, value) in arguments {
                if let stringValue = value as? String, stringValue.contains("\"") {
                    print("🔍 QUOTE DEBUG: Argument '\(key)' contains quotes: '\(stringValue)'")
                }
            }
            
            if let stdin = process.standardInput as? Pipe,
               let stdout = process.standardOutput as? Pipe {
                
                // Use actor-safe pattern for reading response
                let timeout: UInt64 = toolName.contains("browser") || toolName.contains("navigate") ? 10_000_000_000 : 5_000_000_000
                
                class ResponseReader {
                    var responseBuffer = Data()
                    var hasCompleted = false
                }
                
                let reader = ResponseReader()
                
                let responseData = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
                    stdout.fileHandleForReading.readabilityHandler = { handle in
                        let data = handle.availableData
                        if data.count > 0 {
                            reader.responseBuffer.append(data)
                            // Check if we have a complete JSON-RPC response
                            if let responseString = String(data: reader.responseBuffer, encoding: .utf8) {
                                // Look for complete JSON-RPC response
                                if (responseString.contains("\"result\"") || responseString.contains("\"error\"")) && 
                                   responseString.contains("\"jsonrpc\"") {
                                    if !reader.hasCompleted {
                                        reader.hasCompleted = true
                                        stdout.fileHandleForReading.readabilityHandler = nil
                                        continuation.resume(returning: reader.responseBuffer)
                                    }
                                }
                            }
                        }
                    }
                    
                    // Send request
                    print("🔧 Sending MCP request to \(server.name)")
                    stdin.fileHandleForWriting.write(requestString.data(using: .utf8)!)
                    
                    // Set up timeout
                    Task {
                        try await Task.sleep(nanoseconds: timeout)
                        if !reader.hasCompleted {
                            reader.hasCompleted = true
                            stdout.fileHandleForReading.readabilityHandler = nil
                            continuation.resume(throwing: MCPError.communicationError("Timeout waiting for MCP response (\(timeout/1_000_000_000)s)"))
                        }
                    }
                }
                
                print("🔧 Received response data, size: \(responseData.count) bytes")
                    
                    if let responseString = String(data: responseData, encoding: .utf8),
                       !responseString.isEmpty {
                        print("🔧 MCP Response: \(responseString)")
                        
                        // Try to parse as MCP response
                        if let responseJson = try? JSONSerialization.jsonObject(with: responseString.data(using: String.Encoding.utf8)!) as? [String: Any] {
                            if let result = responseJson["result"] as? [String: Any],
                               let content = result["content"] as? [[String: Any]] {
                                // Extract text content from MCP response
                                let textResults = content.compactMap { item -> String? in
                                    if let type = item["type"] as? String, type == "text",
                                       let text = item["text"] as? String {
                                        return text
                                    }
                                    return nil
                                }
                                
                                if !textResults.isEmpty {
                                    let joinedResults = textResults.joined(separator: "\n")
                                    return formatMCPResponse(joinedResults, toolName: toolName)
                                }
                            }
                            
                            if let error = responseJson["error"] as? [String: Any],
                               let message = error["message"] as? String {
                                throw MCPError.communicationError("MCP Error: \(message)")
                            }
                        }
                        
                        // Return formatted response if not parseable as JSON
                        let trimmedResponse = responseString.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                        print("🔧 MCP Tool '\(toolName)' completed successfully, response length: \(trimmedResponse.count) characters")
                        
                        return formatMCPResponse(trimmedResponse, toolName: toolName)
                    } else {
                        print("⚠️ Empty response from MCP server")
                    }
            } else {
                throw MCPError.communicationError("Invalid process pipes for MCP server")
            }
        } catch {
            print("❌ Failed to execute MCP tool \(toolName): \(error)")
            throw MCPError.communicationError("Tool execution failed: \(error.localizedDescription)")
        }
        
        // Fallback for filesystem operations using direct file operations
        if server.name.contains("Filesystem") {
            return try await executeFilesystemOperation(toolName: toolName, arguments: arguments)
        }
        
        throw MCPError.communicationError("No response from MCP server")
    }
    
    private func executeHttpTool(server: MCPServerDefinition, toolName: String, arguments: [String: Any]) async throws -> String {
        guard let url = server.url else {
            throw MCPError.communicationError("No URL configured for streamableHttp server")
        }
        
        guard let serverURL = URL(string: url) else {
            throw MCPError.communicationError("Invalid URL for server: \(url)")
        }
        
        // Prepare MCP JSON-RPC request
        let callRequest = [
            "jsonrpc": "2.0",
            "id": UUID().uuidString,
            "method": "tools/call",
            "params": [
                "name": toolName,
                "arguments": arguments
            ]
        ] as [String: Any]
        
        var request = URLRequest(url: serverURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Add authentication if API key is configured
        if !server.environment.isEmpty {
            print("🔑 Debug: Server environment keys: \(Array(server.environment.keys))")
            if let apiKey = server.environment.first?.value {
                print("🔑 Debug: Using API key (first 10 chars): \(String(apiKey.prefix(10)))...")
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            }
        } else {
            print("🔑 Debug: No API key found in server environment")
        }
        
        do {
            let requestData = try JSONSerialization.data(withJSONObject: callRequest)
            request.httpBody = requestData
            
            let (responseData, httpResponse) = try await URLSession.shared.data(for: request)
            
            // Check HTTP status
            if let httpResponse = httpResponse as? HTTPURLResponse {
                guard httpResponse.statusCode == 200 else {
                    let errorMessage = String(data: responseData, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
                    throw MCPError.communicationError("Server error: \(errorMessage)")
                }
            }
            
            // Parse MCP response
            if let responseJson = try JSONSerialization.jsonObject(with: responseData) as? [String: Any] {
                if let result = responseJson["result"] as? [String: Any],
                   let content = result["content"] as? [[String: Any]] {
                    // Extract text content from MCP response
                    let textResults = content.compactMap { item -> String? in
                        if let type = item["type"] as? String, type == "text",
                           let text = item["text"] as? String {
                            return text
                        }
                        return nil
                    }
                    
                    if !textResults.isEmpty {
                        let joinedResults = textResults.joined(separator: "\n")
                        return formatMCPResponse(joinedResults, toolName: toolName)
                    }
                }
                
                if let error = responseJson["error"] as? [String: Any],
                   let message = error["message"] as? String {
                    throw MCPError.communicationError("MCP Error: \(message)")
                }
                
                // Return formatted JSON if no structured content
                if let resultString = String(data: responseData, encoding: .utf8) {
                    return formatMCPResponse(resultString, toolName: toolName)
                }
            }
            
        } catch {
            print("❌ Failed to execute HTTP MCP tool \(toolName): \(error)")
            throw MCPError.communicationError("HTTP tool execution failed: \(error.localizedDescription)")
        }
        
        throw MCPError.communicationError("No valid response from HTTP MCP server")
    }
    
    private func executeFilesystemOperation(toolName: String, arguments: [String: Any]) async throws -> String {
        switch toolName {
        case "read_file":
            guard let path = arguments["path"] as? String else {
                throw MCPError.communicationError("Missing path parameter")
            }
            
            do {
                let content = try String(contentsOfFile: path, encoding: .utf8)
                return formatMCPResponse(content, toolName: toolName)
            } catch {
                throw MCPError.communicationError("Failed to read file: \(error.localizedDescription)")
            }
            
        case "write_file":
            guard let path = arguments["path"] as? String,
                  let content = arguments["content"] as? String else {
                throw MCPError.communicationError("Missing path or content parameter")
            }
            
            do {
                try content.write(toFile: path, atomically: true, encoding: .utf8)
                return "File written successfully to \(path)"
            } catch {
                throw MCPError.communicationError("Failed to write file: \(error.localizedDescription)")
            }
            
        case "list_directory":
            guard let path = arguments["path"] as? String else {
                throw MCPError.communicationError("Missing path parameter")
            }
            
            do {
                let contents = try FileManager.default.contentsOfDirectory(atPath: path)
                let joinedContents = contents.joined(separator: "\n")
                return formatMCPResponse(joinedContents, toolName: toolName)
            } catch {
                throw MCPError.communicationError("Failed to list directory: \(error.localizedDescription)")
            }
            
        default:
            throw MCPError.toolNotFound(toolName)
        }
    }
    
    // MARK: - Utility Methods
    
    private func isServerInstalled(_ serverName: String) -> Bool {
        let configFile = serversDirectory.appendingPathComponent("\(serverName).json")
        return FileManager.default.fileExists(atPath: configFile.path)
    }
    
    private func isServerRunning(_ serverName: String) -> Bool {
        // Check both the running servers list and actual process state
        if let process = serverProcesses[serverName] {
            return process.isRunning && runningServers.contains(serverName)
        }
        return false
    }
    
    private func loadInstalledServers() {
        let fileManager = FileManager.default
        
        do {
            let serverFiles = try fileManager.contentsOfDirectory(at: serversDirectory, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "json" }
            
            for serverFile in serverFiles {
                do {
                    let serverData = try Data(contentsOf: serverFile)
                    let server = try JSONDecoder().decode(MCPServerDefinition.self, from: serverData)
                    installedServers.append(server)
                } catch {
                    print("Failed to load MCP server from \(serverFile.lastPathComponent): \(error)")
                }
            }
        } catch {
            print("Failed to load MCP servers: \(error)")
        }
    }
    
    // MARK: - Response Formatting
    
    private func formatMCPResponse(_ response: String, toolName: String) -> String {
        var formatted = response
        
        // Handle escaped characters first
        formatted = unescapeString(formatted)
        
        // For JSON responses, try to pretty print
        if formatted.hasPrefix("{") && formatted.hasSuffix("}") {
            if let data = formatted.data(using: .utf8),
               let jsonObject = try? JSONSerialization.jsonObject(with: data),
               let prettyData = try? JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted, .sortedKeys]),
               let prettyString = String(data: prettyData, encoding: .utf8) {
                formatted = prettyString
            }
        }
        
        // Apply tool-specific formatting
        if toolName.contains("read_file") || toolName.contains("list_directory") {
            formatted = formatFileOperationResponse(formatted, toolName: toolName)
        } else if toolName.contains("browser") || toolName.contains("fetch") || toolName.contains("navigate") {
            formatted = formatBrowserResponse(formatted)
        } else if toolName.contains("write_file") {
            // Keep write responses short and clean
            formatted = formatted.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // Apply general cleanup
        formatted = cleanupWhitespace(formatted)
        
        // Final validation and safety
        if formatted.isEmpty {
            return "[No content returned]"
        }
        
        return formatted
    }
    
    private func unescapeString(_ input: String) -> String {
        var result = input
        
        // Handle common escape sequences
        let escapeSequences = [
            ("\\n", "\n"),
            ("\\t", "\t"),
            ("\\r", "\r"),
            ("\\\"", "\""),
            ("\\\\", "\\"),
            ("\\u00a0", " "), // Non-breaking space
        ]
        
        for (escaped, unescaped) in escapeSequences {
            result = result.replacingOccurrences(of: escaped, with: unescaped)
        }
        
        // Handle simple Unicode escapes manually
        // (Complex regex replacement with closures requires more setup)
        if result.contains("\\u") {
            // For now, just remove common problematic unicode escapes
            result = result.replacingOccurrences(of: "\\u0020", with: " ") // space
            result = result.replacingOccurrences(of: "\\u000a", with: "\n") // newline
            result = result.replacingOccurrences(of: "\\u0009", with: "\t") // tab
        }
        
        return result
    }
    
    private func formatFileOperationResponse(_ response: String, toolName: String) -> String {
        if toolName.contains("list_directory") {
            // Format directory listings with bullet points
            let lines = response.components(separatedBy: .newlines)
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            
            if lines.count > 1 {
                return lines.map { "• \($0.trimmingCharacters(in: .whitespaces))" }.joined(separator: "\n")
            }
        }
        
        return response
    }
    
    private func formatBrowserResponse(_ response: String) -> String {
        var formatted = response
        
        // Remove excessive HTML artifacts
        formatted = formatted.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        
        // Fix common markdown formatting issues
        formatted = formatted.replacingOccurrences(of: "\\*\\*([^*]+)\\*\\*", with: "**$1**", options: .regularExpression)
        formatted = formatted.replacingOccurrences(of: "\\*([^*]+)\\*", with: "*$1*", options: .regularExpression)
        
        // Clean up excessive newlines but preserve paragraph breaks
        formatted = formatted.replacingOccurrences(of: "\n\n\n+", with: "\n\n", options: .regularExpression)
        
        return formatted
    }
    
    private func cleanupWhitespace(_ response: String) -> String {
        var formatted = response
        
        // Remove trailing whitespace from lines
        let lines = formatted.components(separatedBy: .newlines)
        formatted = lines.map { $0.trimmingCharacters(in: CharacterSet.whitespaces) }.joined(separator: "\n")
        
        // Remove excessive consecutive newlines (more than 2)
        formatted = formatted.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        
        // Fix spacing around punctuation
        formatted = formatted.replacingOccurrences(of: " +([,.;:!?])", with: "$1", options: .regularExpression)
        formatted = formatted.replacingOccurrences(of: "([,.;:!?])(?! )", with: "$1 ", options: .regularExpression)
        
        // Fix spacing around parentheses and brackets (using simple string replacement for safety)
        formatted = formatted.replacingOccurrences(of: " )", with: ")")
        formatted = formatted.replacingOccurrences(of: " ]", with: "]")
        formatted = formatted.replacingOccurrences(of: " }", with: "}")
        formatted = formatted.replacingOccurrences(of: "( ", with: "(")
        formatted = formatted.replacingOccurrences(of: "[ ", with: "[")
        formatted = formatted.replacingOccurrences(of: "{ ", with: "{")
        
        // Fix multiple spaces with simple replacement
        while formatted.contains("  ") {
            formatted = formatted.replacingOccurrences(of: "  ", with: " ")
        }
        
        return formatted.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Error Types

enum MCPError: LocalizedError {
    case serverNotFound(String)
    case serverNotRunning(String)
    case toolNotFound(String)
    case missingRequiredConfig(String)
    case communicationError(String)
    
    var errorDescription: String? {
        switch self {
        case .serverNotFound(let name):
            return "MCP server '\(name)' not found"
        case .serverNotRunning(let name):
            return "MCP server '\(name)' is not running"
        case .toolNotFound(let name):
            return "MCP tool '\(name)' not found"
        case .missingRequiredConfig(let key):
            return "Missing required configuration: \(key)"
        case .communicationError(let message):
            return "MCP communication error: \(message)"
        }
    }
}