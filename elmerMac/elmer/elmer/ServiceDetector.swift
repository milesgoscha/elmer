import Foundation
import Network
import AppKit

class ServiceDetector {
    // Known service definitions with their detection rules
    static let knownServices: [ServiceDefinition] = [
        ServiceDefinition(
            name: "Ollama",
            type: .languageModel,
            defaultPort: 11434,
            healthEndpoint: "/api/tags",
            apiFormat: .openai,
            appBundleIds: ["com.ollama.ollama"],
            processNames: ["ollama"],
            installPaths: ["/usr/local/bin/ollama", "/opt/homebrew/bin/ollama"]
        ),
        ServiceDefinition(
            name: "LM Studio",
            type: .languageModel,
            defaultPort: 1234,
            healthEndpoint: "/v1/models",
            apiFormat: .openai,
            appBundleIds: ["com.lmstudio.app"],
            processNames: ["LM Studio", "LM Stu", "lmstudio"],
            installPaths: ["/Applications/LM Studio.app"]
        ),
        ServiceDefinition(
            name: "ComfyUI",
            type: .imageGeneration,
            defaultPort: 8188,
            healthEndpoint: "/system_stats",
            apiFormat: .comfyui,
            appBundleIds: [],
            processNames: ["python", "comfyui"],
            installPaths: []
        ),
        ServiceDefinition(
            name: "Automatic1111",
            type: .imageGeneration,
            defaultPort: 7860,
            healthEndpoint: "/sdapi/v1/sd-models",
            apiFormat: .custom,
            appBundleIds: [],
            processNames: ["python", "webui"],
            installPaths: []
        )
    ]
    
    struct ServiceDefinition {
        let name: String
        let type: ServiceType
        let defaultPort: Int
        let healthEndpoint: String
        let apiFormat: APIFormat
        let appBundleIds: [String]
        let processNames: [String]
        let installPaths: [String]
    }
    
    struct DetectedService: Identifiable {
        let id = UUID()
        let definition: ServiceDefinition
        let status: DetectionStatus
        let actualPort: Int?
        let detectedVia: DetectionMethod
    }
    
    enum DetectionStatus {
        case running(port: Int)
        case installed
        case notFound
    }
    
    enum DetectionMethod {
        case portScan
        case appInstalled
        case processRunning
        case manual
    }
    
    // MARK: - Detection Methods
    
    static func detectAllServices() async -> [DetectedService] {
        var detectedServices: [DetectedService] = []
        
        for definition in knownServices {
            let detected = await detectService(definition)
            detectedServices.append(detected)
        }
        
        // Also scan for unknown services on common AI ports
        let additionalServices = await scanCommonPorts()
        detectedServices.append(contentsOf: additionalServices)
        
        return detectedServices
    }
    
    static func detectService(_ definition: ServiceDefinition) async -> DetectedService {
        // First check if it's running on its default port
        if await isPortResponding(port: definition.defaultPort, healthEndpoint: definition.healthEndpoint) {
            return DetectedService(
                definition: definition,
                status: .running(port: definition.defaultPort),
                actualPort: definition.defaultPort,
                detectedVia: .portScan
            )
        }
        
        // Check if process is running (might be on different port)
        if let port = await findProcessPort(definition) {
            return DetectedService(
                definition: definition,
                status: .running(port: port),
                actualPort: port,
                detectedVia: .processRunning
            )
        }
        
        // Only if not running anywhere, check if the app is installed
        if isAppInstalled(definition) {
            return DetectedService(
                definition: definition,
                status: .installed,
                actualPort: nil,
                detectedVia: .appInstalled
            )
        }
        
        return DetectedService(
            definition: definition,
            status: .notFound,
            actualPort: nil,
            detectedVia: .portScan
        )
    }
    
    static func isPortResponding(port: Int, healthEndpoint: String) async -> Bool {
        let url = URL(string: "http://localhost:\(port)\(healthEndpoint)")!
        var request = URLRequest(url: url)
        // Give ComfyUI more time to respond - it can be slow on startup
        request.timeoutInterval = port == 8188 ? 10.0 : 2.0
        
        print("🏥 Checking health for port \(port) at \(url)")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode < 500 {
                // For better accuracy, validate service-specific response signatures
                let responseString = String(data: data, encoding: .utf8) ?? ""
                let isValidService = validateServiceResponse(port: port, endpoint: healthEndpoint, responseData: data, responseString: responseString)
                
                print(isValidService ? "✅ Port \(port) is healthy and matches expected service (status: \(httpResponse.statusCode))" : "⚠️ Port \(port) responds but doesn't match expected service signature")
                return isValidService
            }
        } catch {
            print("❌ Port \(port) health check failed: \(error)")
        }
        
        return false
    }
    
    private static func validateServiceResponse(port: Int, endpoint: String, responseData: Data, responseString: String) -> Bool {
        // Reject HTML responses (common from background services)
        if responseString.contains("<html>") || responseString.contains("<!DOCTYPE") {
            print("🔍 Port \(port) returned HTML, not a valid API service")
            return false
        }
        
        // Service-specific validation based on endpoint
        switch endpoint {
        case "/api/tags": // Ollama
            do {
                if let json = try JSONSerialization.jsonObject(with: responseData) as? [String: Any],
                   let _ = json["models"] as? [[String: Any]] {
                    print("🔍 ✅ Confirmed Ollama API at port \(port)")
                    return true
                }
            } catch { }
            
        case "/v1/models": // LM Studio / OpenAI-compatible
            do {
                if let json = try JSONSerialization.jsonObject(with: responseData) as? [String: Any] {
                    // OpenAI-compatible format
                    if let _ = json["data"] as? [[String: Any]], let object = json["object"] as? String, object == "list" {
                        print("🔍 ✅ Confirmed OpenAI-compatible API (LM Studio) at port \(port)")
                        return true
                    }
                }
            } catch { }
            
        case "/system_stats": // ComfyUI
            do {
                if let json = try JSONSerialization.jsonObject(with: responseData) as? [String: Any],
                   let system = json["system"] as? [String: Any],
                   let _ = system["comfyui_version"] as? String {
                    print("🔍 ✅ Confirmed ComfyUI at port \(port)")
                    return true
                }
            } catch { }
            
        case "/sdapi/v1/sd-models": // Automatic1111
            // Auto1111 returns an array of model objects
            do {
                if let _ = try JSONSerialization.jsonObject(with: responseData) as? [[String: Any]] {
                    print("🔍 ✅ Confirmed Automatic1111 at port \(port)")
                    return true
                }
            } catch { }
            
        default:
            // For unknown endpoints, accept any valid JSON
            do {
                let _ = try JSONSerialization.jsonObject(with: responseData)
                return true
            } catch { }
        }
        
        print("🔍 ❌ Port \(port) response doesn't match expected service signature for \(endpoint)")
        return false
    }
    
    static func isAppInstalled(_ definition: ServiceDefinition) -> Bool {
        // Check bundle IDs
        for bundleId in definition.appBundleIds {
            if let _ = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
                return true
            }
        }
        
        // Check install paths
        for path in definition.installPaths {
            if FileManager.default.fileExists(atPath: path) {
                return true
            }
        }
        
        return false
    }
    
    static func findProcessPort(_ definition: ServiceDefinition) async -> Int? {
        print("🔍 findProcessPort: Looking for \(definition.name) with process names: \(definition.processNames)")
        
        // Use lsof to find what port a process is listening on
        for processName in definition.processNames {
            print("🔍 Checking process name: \(processName)")
            if let port = await findPortForProcess(processName, healthEndpoint: definition.healthEndpoint) {
                print("🔍 ✅ Found \(processName) running on port \(port)")
                return port
            }
        }
        
        // For LM Studio specifically, also check for the bundle identifier process
        if definition.name == "LM Studio" {
            print("🔍 Special LM Studio check...")
            if let port = await findPortForLMStudio(healthEndpoint: definition.healthEndpoint) {
                print("🔍 ✅ Found LM Studio running on port \(port)")
                return port
            }
        }
        
        print("🔍 ❌ No running process found for \(definition.name)")
        return nil
    }
    
    private static func findPortForProcess(_ processName: String, healthEndpoint: String) async -> Int? {
        // Get all listening processes with their ports
        let processPortMap = await getProcessPortMapping()
        
        print("🔍 Looking for process name: \(processName)")
        
        // Find ports for processes that match our process name
        let matchingPorts = processPortMap.compactMap { (process, port) -> Int? in
            // More flexible matching - check if process name contains our target
            let processLower = process.lowercased()
            let targetLower = processName.lowercased()
            
            if processLower.contains(targetLower) || targetLower.contains(processLower) {
                print("🔍 Process name match: '\(process)' matches '\(processName)'")
                return port
            }
            
            return nil
        }
        
        print("🔍 Found \(matchingPorts.count) matching ports: \(matchingPorts)")
        
        // Test each port to see if it responds to our health check
        for port in matchingPorts {
            print("🔍 Testing port \(port) for \(processName)")
            if await isPortResponding(port: port, healthEndpoint: healthEndpoint) {
                print("🔍 ✅ Verified \(processName) is running on port \(port)")
                return port
            } else {
                print("🔍 ❌ Port \(port) didn't respond to health check")
            }
        }
        
        return nil
    }
    
    private static func getProcessPortMapping() async -> [(String, Int)] {
        let task = Process()
        task.launchPath = "/usr/sbin/lsof"  // Standard location on macOS
        task.arguments = ["-i", "-P", "-n", "-sTCP:LISTEN"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe() // Suppress error output
        
        var processPortPairs: [(String, Int)] = []
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            
            // print("🔍 Raw lsof output:")
            // print(output)
            
            // Parse lsof output line by line
            for line in output.components(separatedBy: .newlines) {
                if line.contains("LISTEN") && line.contains("TCP") {
                    let components = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                    
                    if components.count >= 9 {
                        let rawProcessName = components[0] // First column is process name
                        let networkInfo = components[8] // Network info like "*:1234"
                        
                        // Clean up process name - handle escaped characters like LM\x20Stu
                        let processName = rawProcessName.replacingOccurrences(of: "\\x20", with: " ")
                        
                        // Extract port from network info (format like "*:1234" or "127.0.0.1:1234")
                        if let colonIndex = networkInfo.lastIndex(of: ":"),
                           let portString = networkInfo[networkInfo.index(after: colonIndex)...].components(separatedBy: " ").first,
                           let port = Int(portString), port > 1024 { // Only consider non-system ports
                            
                            processPortPairs.append((processName, port))
                            print("🔍 Found process: \(processName) listening on port \(port)")
                        }
                    }
                }
            }
        } catch {
            print("❌ Error running lsof: \(error)")
        }
        
        return processPortPairs
    }
    
    private static func findPortForLMStudio(healthEndpoint: String) async -> Int? {
        // Get all listening processes with their ports
        let processPortMap = await getProcessPortMapping()
        
        // LM Studio might show up under various process names
        let lmStudioProcessNames = ["LM Studio", "lmstudio", "LMStudio", "node", "electron"]
        
        for processName in lmStudioProcessNames {
            let matchingPorts = processPortMap.filter { (process, _) in
                process.lowercased().contains(processName.lowercased())
            }.map { $0.1 }
            
            // Test each port to see if it matches the expected service
            for port in matchingPorts {
                if await isPortResponding(port: port, healthEndpoint: healthEndpoint) {
                    print("🔍 ✅ Verified LM Studio is running on port \(port) (process: \(processName))")
                    return port
                }
            }
        }
        
        print("🔍 ❌ LM Studio not found via process detection")
        return nil
    }
    
    
    static func scanCommonPorts() async -> [DetectedService] {
        // Scan common AI service ports for unknown services (excluding 5000 - reserved by macOS Control Center)
        let commonPorts = [8000, 8080, 8888, 9000, 3000]
        var unknownServices: [DetectedService] = []
        
        for port in commonPorts {
            if await isPortResponding(port: port, healthEndpoint: "/") {
                // Create a generic service definition for unknown services
                let definition = ServiceDefinition(
                    name: "Unknown Service (Port \(port))",
                    type: .custom,
                    defaultPort: port,
                    healthEndpoint: "/",
                    apiFormat: .custom,
                    appBundleIds: [],
                    processNames: [],
                    installPaths: []
                )
                
                unknownServices.append(DetectedService(
                    definition: definition,
                    status: .running(port: port),
                    actualPort: port,
                    detectedVia: .portScan
                ))
            }
        }
        
        return unknownServices
    }
    
    // MARK: - ComfyUI Workflow Discovery
    
    static func findComfyUIWorkflows() -> [ComfyUIWorkflow] {
        var workflows: [ComfyUIWorkflow] = []
        
        // Common ComfyUI installation paths
        let possibleBasePaths = [
            NSHomeDirectory() + "/ComfyUI",
            "/opt/ComfyUI",
            "/usr/local/ComfyUI",
            NSHomeDirectory() + "/Desktop/ComfyUI",
            NSHomeDirectory() + "/Documents/ComfyUI",
            NSHomeDirectory() + "/Downloads/ComfyUI",
            NSHomeDirectory() + "/Applications/ComfyUI",
            "/Applications/ComfyUI"
        ]
        
        // Common workflow subdirectories within ComfyUI installations
        let workflowSubpaths = [
            "/workflows",
            "/user/default/workflows",
            "/output/workflows",
            "/web/workflows"
        ]
        
        print("🔍 Searching for ComfyUI workflows...")
        
        for basePath in possibleBasePaths {
            print("📂 Checking ComfyUI base path: \(basePath)")
            
            // Check if the base path exists
            if FileManager.default.fileExists(atPath: basePath) {
                print("✅ Found ComfyUI directory: \(basePath)")
                
                for subpath in workflowSubpaths {
                    let fullPath = basePath + subpath
                    print("📁 Checking workflow path: \(fullPath)")
                    let foundWorkflows = loadWorkflowsFromPath(fullPath)
                    if !foundWorkflows.isEmpty {
                        print("✅ Found \(foundWorkflows.count) workflows in \(fullPath)")
                    }
                    workflows.append(contentsOf: foundWorkflows)
                }
            } else {
                print("❌ ComfyUI directory not found: \(basePath)")
            }
        }
        
        // Also check current directory
        let currentDir = FileManager.default.currentDirectoryPath + "/workflows"
        print("📁 Checking current directory workflows: \(currentDir)")
        workflows.append(contentsOf: loadWorkflowsFromPath(currentDir))
        
        print("🔍 Found \(workflows.count) ComfyUI workflows total")
        return workflows
    }
    
    private static func loadWorkflowsFromPath(_ path: String) -> [ComfyUIWorkflow] {
        var workflows: [ComfyUIWorkflow] = []
        
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: path) else {
            return workflows
        }
        
        for filename in files {
            guard filename.hasSuffix(".json") else { continue }
            
            let fullPath = path + "/" + filename
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: fullPath)),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }
            
            // Verify it looks like a ComfyUI workflow (has nodes with class_type)
            var hasValidNodes = false
            for (_, value) in json {
                if let node = value as? [String: Any],
                   node["class_type"] != nil {
                    hasValidNodes = true
                    break
                }
            }
            
            if hasValidNodes {
                let name = filename.replacingOccurrences(of: ".json", with: "")
                let workflow = ComfyUIWorkflow(
                    id: UUID().uuidString,
                    name: name,
                    filename: filename,
                    workflowJSON: json
                )
                workflows.append(workflow)
                print("📄 Loaded workflow: \(name)")
            }
        }
        
        return workflows
    }
    
    // MARK: - Service Creation
    
    static func createAIService(from detected: DetectedService) -> AIService {
        let port = detected.actualPort ?? detected.definition.defaultPort
        let detectionStatus: ServiceDetectionStatus = {
            switch detected.status {
            case .running: return .running
            case .installed: return .installed
            case .notFound: return .unknown
            }
        }()
        
        return AIService.createAutoDetected(
            name: detected.definition.name,
            type: detected.definition.type,
            localPort: port,
            healthCheckEndpoint: detected.definition.healthEndpoint,
            apiFormat: detected.definition.apiFormat,
            detectionStatus: detectionStatus
        )
    }
}

// Extension to AIService to support auto-detection
extension AIService {
    static func createAutoDetected(
        name: String,
        type: ServiceType,
        localPort: Int,
        healthCheckEndpoint: String,
        apiFormat: APIFormat,
        detectionStatus: ServiceDetectionStatus
    ) -> AIService {
        return AIService(
            name: name,
            type: type,
            localPort: localPort,
            healthCheckEndpoint: healthCheckEndpoint,
            apiFormat: apiFormat,
            isRunning: detectionStatus == .running,
            isAutoDetected: true,
            detectionStatus: detectionStatus
        )
    }
}