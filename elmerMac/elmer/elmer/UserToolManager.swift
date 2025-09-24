//
//  UserToolManager.swift
//  elmer (Mac)
//
//  Manages user-defined tools from ~/.elmer/tools/ directory and MCP servers
//

import Foundation

// MARK: - User Tool Definition Models

struct UserToolDefinition: Codable {
    let name: String
    let description: String
    let parameters: ToolParameters
    let execution: ToolExecution
}

struct ToolParameters: Codable {
    let type: String
    let properties: [String: ToolProperty]
    let required: [String]?
}

struct ToolProperty: Codable {
    let type: String
    let description: String
    let `default`: ToolAnyCodable?
    
    enum CodingKeys: String, CodingKey {
        case type, description
        case `default` = "default"
    }
}

struct ToolExecution: Codable {
    let type: String // "script", "http", etc.
    let command: String?
    let url: String?
    let method: String?
    let timeout: Int?
    let headers: [String: String]?
}

// Helper for dynamic coding keys
struct DynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?
    
    init?(stringValue: String) {
        self.stringValue = stringValue
    }
    
    init?(intValue: Int) {
        self.intValue = intValue
        self.stringValue = "\(intValue)"
    }
}

// Helper for encoding/decoding arbitrary JSON values
struct ToolAnyCodable: Codable {
    let value: Any
    
    init(_ value: Any) {
        self.value = value
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if container.decodeNil() {
            value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else {
            // For complex types, try to decode as a general container
            if let keyedContainer = try? decoder.container(keyedBy: DynamicCodingKey.self) {
                var dict: [String: Any] = [:]
                for key in keyedContainer.allKeys {
                    let nestedDecoder = try keyedContainer.superDecoder(forKey: key)
                    let nestedValue = try ToolAnyCodable(from: nestedDecoder)
                    dict[key.stringValue] = nestedValue.value
                }
                value = dict
            } else if var unkeyedContainer = try? decoder.unkeyedContainer() {
                var array: [Any] = []
                while !unkeyedContainer.isAtEnd {
                    let nestedDecoder = try unkeyedContainer.superDecoder()
                    let nestedValue = try ToolAnyCodable(from: nestedDecoder)
                    array.append(nestedValue.value)
                }
                value = array
            } else {
                value = NSNull()
            }
        }
    }
    
    func encode(to encoder: Encoder) throws {
        switch value {
        case is NSNull:
            var container = encoder.singleValueContainer()
            try container.encodeNil()
        case let bool as Bool:
            var container = encoder.singleValueContainer()
            try container.encode(bool)
        case let int as Int:
            var container = encoder.singleValueContainer()
            try container.encode(int)
        case let double as Double:
            var container = encoder.singleValueContainer()
            try container.encode(double)
        case let string as String:
            var container = encoder.singleValueContainer()
            try container.encode(string)
        case let array as [Any]:
            var unkeyedContainer = encoder.unkeyedContainer()
            for item in array {
                try ToolAnyCodable(item).encode(to: unkeyedContainer.superEncoder())
            }
        case let dict as [String: Any]:
            var keyedContainer = encoder.container(keyedBy: DynamicCodingKey.self)
            for (key, value) in dict {
                let codingKey = DynamicCodingKey(stringValue: key)!
                try ToolAnyCodable(value).encode(to: keyedContainer.superEncoder(forKey: codingKey))
            }
        default:
            var container = encoder.singleValueContainer()
            try container.encodeNil()
        }
    }
}

// MARK: - User Tool Manager

class UserToolManager {
    static let shared = UserToolManager()
    
    private let toolsDirectoryPath: String
    private var loadedTools: [UserToolDefinition] = []
    private let mcpManager = MCPServerManager.shared
    
    private init() {
        let homeDirectory = NSHomeDirectory()
        toolsDirectoryPath = NSString(string: homeDirectory).appendingPathComponent(".elmer/tools")
        
        // Create tools directory if it doesn't exist
        createToolsDirectoryIfNeeded()
        
        // Load tools on initialization
        loadTools()
    }
    
    // MARK: - Directory Management
    
    private func createToolsDirectoryIfNeeded() {
        let fileManager = FileManager.default
        
        if !fileManager.fileExists(atPath: toolsDirectoryPath) {
            do {
                try fileManager.createDirectory(atPath: toolsDirectoryPath, withIntermediateDirectories: true)
                print("✅ Created tools directory: \(toolsDirectoryPath)")
            } catch {
                print("❌ Failed to create tools directory: \(error)")
            }
        }
    }
    
    // MARK: - Tool Loading
    
    func loadTools() {
        print("📂 Loading user tools from: \(toolsDirectoryPath)")
        
        let fileManager = FileManager.default
        loadedTools.removeAll()
        
        do {
            let toolFiles = try fileManager.contentsOfDirectory(atPath: toolsDirectoryPath)
                .filter { $0.hasSuffix(".json") }
            
            for toolFile in toolFiles {
                let toolFilePath = NSString(string: toolsDirectoryPath).appendingPathComponent(toolFile)
                
                do {
                    let toolData = try Data(contentsOf: URL(fileURLWithPath: toolFilePath))
                    let toolDefinition = try JSONDecoder().decode(UserToolDefinition.self, from: toolData)
                    
                    loadedTools.append(toolDefinition)
                    print("✅ Loaded tool: \(toolDefinition.name) from \(toolFile)")
                    
                } catch {
                    print("❌ Failed to load tool from \(toolFile): \(error)")
                }
            }
            
            print("🔧 Total tools loaded: \(loadedTools.count)")
            
        } catch {
            print("❌ Failed to read tools directory: \(error)")
        }
    }
    
    // MARK: - Tool Access
    
    var availableTools: [[String: Any]] {
        var tools: [[String: Any]] = []
        
        // Add JSON-based user tools
        tools.append(contentsOf: loadedTools.map { tool in
            return [
                "type": "function",
                "function": [
                    "name": tool.name,
                    "description": tool.description,
                    "parameters": convertParametersToDict(tool.parameters)
                ]
            ]
        })
        
        // Add MCP tools
        tools.append(contentsOf: mcpManager.availableTools.map { mcpTool in
            return [
                "type": "function",
                "function": [
                    "name": "mcp__\(mcpTool.serverName)__\(mcpTool.name)",
                    "description": mcpTool.description,
                    "parameters": mcpTool.parameters
                ]
            ]
        })
        
        return tools
    }
    
    private func convertParametersToDict(_ parameters: ToolParameters) -> [String: Any] {
        var result: [String: Any] = [
            "type": parameters.type,
            "properties": [:]
        ]
        
        var properties: [String: Any] = [:]
        for (key, property) in parameters.properties {
            var propertyDict: [String: Any] = [
                "type": property.type,
                "description": property.description
            ]
            
            if let defaultValue = property.default {
                propertyDict["default"] = defaultValue.value
            }
            
            properties[key] = propertyDict
        }
        
        result["properties"] = properties
        
        if let required = parameters.required {
            result["required"] = required
        }
        
        return result
    }
    
    func getToolDefinition(name: String) -> UserToolDefinition? {
        return loadedTools.first { $0.name == name }
    }
    
    // MARK: - Tool Execution
    
    func executeTool(name: String, arguments: [String: Any]) async throws -> String {
        // Check if this is an MCP tool (prefixed with mcp__)
        if name.hasPrefix("mcp__") {
            return try await mcpManager.executeMCPTool(toolName: name, arguments: arguments)
        }
        
        // Handle regular JSON-based tools
        guard let toolDefinition = getToolDefinition(name: name) else {
            throw UserToolError.toolNotFound(name)
        }
        
        print("🔧 Executing user tool: \(name)")
        
        switch toolDefinition.execution.type {
        case "script":
            return try await executeScript(toolDefinition: toolDefinition, arguments: arguments)
        case "http":
            return try await executeHTTPRequest(toolDefinition: toolDefinition, arguments: arguments)
        default:
            throw UserToolError.unsupportedExecutionType(toolDefinition.execution.type)
        }
    }
    
    private func executeScript(toolDefinition: UserToolDefinition, arguments: [String: Any]) async throws -> String {
        guard let command = toolDefinition.execution.command else {
            throw UserToolError.missingExecutionCommand
        }
        
        // Security: Basic command validation
        try validateScriptSafety(command: command)
        
        // Replace argument placeholders in command
        var processedCommand = command
        for (key, value) in arguments {
            let placeholder = "{\(key)}"
            let sanitizedValue = sanitizeArgument(String(describing: value))
            processedCommand = processedCommand.replacingOccurrences(of: placeholder, with: sanitizedValue)
        }
        
        print("🚀 Executing: \(processedCommand)")
        
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.launchPath = "/bin/sh"
            process.arguments = ["-c", processedCommand]
            
            // Security: Set up a restricted environment
            process.environment = getRestrictedEnvironment()
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            
            let timeout = min(toolDefinition.execution.timeout ?? 30, 300) // Max 5 minutes
            
            process.terminationHandler = { process in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                
                // Limit output size to prevent memory issues
                let maxOutputSize = 100000 // 100KB
                let truncatedOutput = output.count > maxOutputSize 
                    ? String(output.prefix(maxOutputSize)) + "\n... (output truncated)"
                    : output
                
                if process.terminationStatus == 0 {
                    continuation.resume(returning: truncatedOutput.trimmingCharacters(in: .whitespacesAndNewlines))
                } else {
                    continuation.resume(throwing: UserToolError.executionFailed("Process failed with exit code \(process.terminationStatus): \(truncatedOutput)"))
                }
            }
            
            do {
                try process.run()
                
                // Set up timeout
                DispatchQueue.global().asyncAfter(deadline: .now() + .seconds(timeout)) {
                    if process.isRunning {
                        process.terminate()
                        continuation.resume(throwing: UserToolError.executionTimeout(timeout))
                    }
                }
                
            } catch {
                continuation.resume(throwing: UserToolError.executionFailed("Failed to launch process: \(error)"))
            }
        }
    }
    
    // MARK: - Security Helpers
    
    private func validateScriptSafety(command: String) throws {
        let command = command.lowercased()
        
        // Block potentially dangerous commands - be more specific to avoid false positives
        let dangerousCommands = [
            "\\brm\\s+-rf", "\\brmdir\\s+", "\\bdel\\s+", "\\bformat\\s+c:", "\\bfdisk\\s+", 
            "\\bsudo\\s+", "\\bsu\\s+", "chmod\\s+\\+x", "\\bchown\\s+",
            "curl.*-o.*\\.(sh|exe|bin)", "wget.*-o.*\\.(sh|exe|bin)",
            "echo.*>>?.*sudoers", "cat.*>>?.*passwd",
            "\\bnc\\s+-l", "\\bnetcat\\s+-l", // Reverse shells
            "python.*-c.*import.*os", "python.*-c.*exec",
            "\\beval\\s+", "\\bexec\\s+", "\\$\\(" // Command injection
        ]
        
        for dangerous in dangerousCommands {
            if command.range(of: dangerous, options: .regularExpression) != nil {
                throw UserToolError.unsafeCommand(dangerous)
            }
        }
        
        // Warn about potentially risky patterns but don't block
        let riskyPatterns = ["\\brm\\s+", "\\bmv\\s+", "\\bcp\\s+", "\\bmkdir\\s+", "\\btouch\\s+"]
        for risky in riskyPatterns {
            if command.range(of: risky, options: .regularExpression) != nil {
                print("⚠️ Tool uses potentially risky command: \(risky)")
            }
        }
    }
    
    private func sanitizeArgument(_ argument: String) -> String {
        // Basic argument sanitization
        return argument
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: "|", with: "\\|")
            .replacingOccurrences(of: "&", with: "\\&")
            .replacingOccurrences(of: "$", with: "\\$")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$(", with: "\\$(")
    }
    
    private func getRestrictedEnvironment() -> [String: String] {
        // Provide a minimal, safe environment
        let safeEnvVars = [
            "PATH": "/usr/bin:/bin:/usr/local/bin",
            "HOME": NSHomeDirectory(),
            "USER": NSUserName(),
            "SHELL": "/bin/sh",
            "TMPDIR": NSTemporaryDirectory()
        ]
        
        return safeEnvVars
    }
    
    private func executeHTTPRequest(toolDefinition: UserToolDefinition, arguments: [String: Any]) async throws -> String {
        guard let urlString = toolDefinition.execution.url else {
            throw UserToolError.missingExecutionURL
        }
        
        guard let url = URL(string: urlString) else {
            throw UserToolError.invalidURL(urlString)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = toolDefinition.execution.method ?? "POST"
        
        // Add headers if specified
        if let headers = toolDefinition.execution.headers {
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }
        
        // Add arguments as JSON body for POST requests
        if request.httpMethod?.uppercased() == "POST" {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let jsonData = try JSONSerialization.data(withJSONObject: arguments)
            request.httpBody = jsonData
        }
        
        let timeout = TimeInterval(toolDefinition.execution.timeout ?? 30)
        request.timeoutInterval = timeout
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        let httpResponse = response as? HTTPURLResponse
        let statusCode = httpResponse?.statusCode ?? 0
        
        if statusCode >= 400 {
            throw UserToolError.httpError(statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        
        return String(data: data, encoding: .utf8) ?? ""
    }
    
    // MARK: - Refresh Tools
    
    func refreshTools() {
        print("🔄 Refreshing user tools...")
        loadTools()
    }
    
    // MARK: - MCP Integration
    
    func getMCPServerManager() -> MCPServerManager {
        return mcpManager
    }
    
    var hasMCPTools: Bool {
        return !mcpManager.availableTools.isEmpty
    }
    
    var mcpToolCount: Int {
        return mcpManager.availableTools.count
    }
}

// MARK: - User Tool Errors

enum UserToolError: LocalizedError {
    case toolNotFound(String)
    case unsupportedExecutionType(String)
    case missingExecutionCommand
    case missingExecutionURL
    case invalidURL(String)
    case executionFailed(String)
    case executionTimeout(Int)
    case httpError(Int, String)
    case unsafeCommand(String)
    
    var errorDescription: String? {
        switch self {
        case .toolNotFound(let name):
            return "Tool not found: \(name)"
        case .unsupportedExecutionType(let type):
            return "Unsupported execution type: \(type)"
        case .missingExecutionCommand:
            return "Missing execution command in tool definition"
        case .missingExecutionURL:
            return "Missing execution URL in tool definition"
        case .invalidURL(let url):
            return "Invalid URL: \(url)"
        case .executionFailed(let message):
            return "Tool execution failed: \(message)"
        case .executionTimeout(let seconds):
            return "Tool execution timed out after \(seconds) seconds"
        case .httpError(let code, let message):
            return "HTTP error \(code): \(message)"
        case .unsafeCommand(let pattern):
            return "Unsafe command blocked for security: \(pattern)"
        }
    }
}