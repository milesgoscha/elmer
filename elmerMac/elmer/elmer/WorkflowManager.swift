//
//  WorkflowManager.swift
//  elmer (Mac)
//
//  Manages ComfyUI workflow storage, import, and validation
//

import Foundation
import SwiftUI

@MainActor
class WorkflowManager: ObservableObject {
    static let shared = WorkflowManager()
    
    @Published var workflows: [ImportedWorkflow] = []
    @Published var isLoading = false
    
    private let workflowsDirectory: URL
    private let fileManager = FileManager.default
    
    private init() {
        // Create workflows directory in ~/Library/Application Support/Elmer/Workflows/
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let elmerDirectory = appSupportURL.appendingPathComponent("Elmer")
        self.workflowsDirectory = elmerDirectory.appendingPathComponent("Workflows")
        
        // Ensure directory exists
        try? fileManager.createDirectory(at: workflowsDirectory, withIntermediateDirectories: true)
        
        // Load existing workflows
        loadWorkflows()
    }
    
    // MARK: - Loading Workflows
    
    func loadWorkflows() {
        isLoading = true
        
        do {
            let workflowFiles = try fileManager.contentsOfDirectory(at: workflowsDirectory, includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey])
            
            var loadedWorkflows: [ImportedWorkflow] = []
            
            for fileURL in workflowFiles where fileURL.pathExtension == "json" {
                if let workflow = loadWorkflow(from: fileURL) {
                    loadedWorkflows.append(workflow)
                }
            }
            
            // Sort by creation date (newest first)
            loadedWorkflows.sort { $0.importDate > $1.importDate }
            
            workflows = loadedWorkflows
            print("✅ Loaded \(workflows.count) workflows from \(workflowsDirectory.path)")
            
        } catch {
            print("❌ Failed to load workflows: \(error)")
        }
        
        isLoading = false
    }
    
    private func loadWorkflow(from fileURL: URL) -> ImportedWorkflow? {
        do {
            let data = try Data(contentsOf: fileURL)
            
            // Try to load as ImportedWorkflow first (our saved format)
            if let savedWorkflow = try? JSONDecoder().decode(ImportedWorkflow.self, from: data) {
                return savedWorkflow
            }
            
            // Otherwise, try to load as raw ComfyUI workflow JSON
            if let _ = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return ImportedWorkflow.fromRawWorkflow(
                    workflowJSON: try JSONSerialization.jsonObject(with: data) as! [String: Any],
                    filename: fileURL.lastPathComponent
                )
            }
            
            return nil
            
        } catch {
            print("⚠️ Failed to load workflow from \(fileURL.path): \(error)")
            return nil
        }
    }
    
    // MARK: - Importing Workflows
    
    func importWorkflow(from sourceURL: URL) async throws -> ImportedWorkflow {
        // Start accessing the security-scoped resource for sandboxed apps
        let didStartAccessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }
        
        let data = try Data(contentsOf: sourceURL)
        
        // Parse the workflow JSON
        guard let _ = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw WorkflowError.invalidFormat
        }
        
        // Create ImportedWorkflow from raw JSON
        let workflowJSON = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let workflow = ImportedWorkflow.fromRawWorkflow(
            workflowJSON: workflowJSON,
            filename: sourceURL.lastPathComponent
        )
        
        // Validate workflow
        try await validateWorkflow(workflow)
        
        // Save to workflows directory
        let filename = sanitizeFilename(workflow.name) + ".json"
        let destinationURL = workflowsDirectory.appendingPathComponent(filename)
        
        // Avoid overwriting existing workflows
        var finalURL = destinationURL
        var counter = 1
        while fileManager.fileExists(atPath: finalURL.path) {
            let baseName = sanitizeFilename(workflow.name)
            let filename = "\(baseName) (\(counter)).json"
            finalURL = workflowsDirectory.appendingPathComponent(filename)
            counter += 1
        }
        
        // Save the workflow
        let encodedData = try JSONEncoder().encode(workflow)
        try encodedData.write(to: finalURL)
        
        // Add to workflows list
        workflows.insert(workflow, at: 0)
        
        print("✅ Imported workflow: \(workflow.name)")
        return workflow
    }
    
    func importWorkflowFromPasteboard() async throws -> ImportedWorkflow? {
        guard let string = NSPasteboard.general.string(forType: .string) else {
            throw WorkflowError.noDataInPasteboard
        }
        
        // Try to parse as JSON
        guard let data = string.data(using: .utf8),
              let _ = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw WorkflowError.invalidFormat
        }
        
        // Create temporary file for import
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("pasted_workflow.json")
        try data.write(to: tempURL)
        
        defer {
            try? fileManager.removeItem(at: tempURL)
        }
        
        return try await importWorkflow(from: tempURL)
    }
    
    // MARK: - Workflow Operations
    
    func deleteWorkflow(_ workflow: ImportedWorkflow) {
        // Remove file
        let filename = sanitizeFilename(workflow.name) + ".json"
        let fileURL = workflowsDirectory.appendingPathComponent(filename)
        
        do {
            try fileManager.removeItem(at: fileURL)
            workflows.removeAll { $0.id == workflow.id }
            print("🗑️ Deleted workflow: \(workflow.name)")
        } catch {
            print("❌ Failed to delete workflow: \(error)")
        }
    }
    
    func updateWorkflow(_ workflow: ImportedWorkflow) throws {
        let filename = sanitizeFilename(workflow.name) + ".json"
        let fileURL = workflowsDirectory.appendingPathComponent(filename)
        
        let encodedData = try JSONEncoder().encode(workflow)
        try encodedData.write(to: fileURL)
        
        // Update in memory
        if let index = workflows.firstIndex(where: { $0.id == workflow.id }) {
            workflows[index] = workflow
        }
        
        print("💾 Updated workflow: \(workflow.name)")
    }
    
    func exportWorkflow(_ workflow: ImportedWorkflow, to destinationURL: URL) throws {
        // Export as raw ComfyUI JSON format
        let workflowData = try JSONSerialization.data(withJSONObject: workflow.workflowJSON, options: .prettyPrinted)
        try workflowData.write(to: destinationURL)
        
        print("📤 Exported workflow: \(workflow.name)")
    }
    
    // MARK: - Workflow Validation
    
    private func validateWorkflow(_ workflow: ImportedWorkflow) async throws {
        // Basic validation - check if workflow has valid structure
        guard !workflow.workflowJSON.isEmpty else {
            throw WorkflowError.emptyWorkflow
        }
        
        // Check if workflow has nodes with class_type (ComfyUI format)
        var hasValidNodes = false
        for (_, value) in workflow.workflowJSON {
            if let node = value as? [String: Any],
               node["class_type"] != nil {
                hasValidNodes = true
                break
            }
        }
        
        guard hasValidNodes else {
            throw WorkflowError.invalidComfyUIFormat
        }
        
        // TODO: Add more validation like checking for required nodes, etc.
        
        print("✅ Workflow validation passed: \(workflow.name)")
    }
    
    // MARK: - Utilities
    
    private func sanitizeFilename(_ filename: String) -> String {
        let invalidChars = CharacterSet(charactersIn: ":/\\?%*|\"<>")
        return filename.components(separatedBy: invalidChars).joined(separator: "_")
    }
}

// MARK: - ImportedWorkflow Model

struct ImportedWorkflow: Identifiable, Codable, Hashable {
    let id: String
    var name: String
    let filename: String
    let workflowJSON: [String: Any]
    let importDate: Date
    var description: String?
    let type: WorkflowType
    let requiredModels: [String]
    let customNodes: [String]
    let parameters: [WorkflowParameter]
    
    // Regular initializer
    init(
        id: String,
        name: String,
        filename: String,
        workflowJSON: [String: Any],
        importDate: Date,
        description: String?,
        type: WorkflowType,
        requiredModels: [String],
        customNodes: [String],
        parameters: [WorkflowParameter]
    ) {
        self.id = id
        self.name = name
        self.filename = filename
        self.workflowJSON = workflowJSON
        self.importDate = importDate
        self.description = description
        self.type = type
        self.requiredModels = requiredModels
        self.customNodes = customNodes
        self.parameters = parameters
    }
    
    // Hashable conformance
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: ImportedWorkflow, rhs: ImportedWorkflow) -> Bool {
        return lhs.id == rhs.id
    }
    
    enum CodingKeys: String, CodingKey {
        case id, name, filename, importDate, description, type, requiredModels, customNodes, parameters
        case workflowJSON = "workflow"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        filename = try container.decode(String.self, forKey: .filename)
        importDate = try container.decode(Date.self, forKey: .importDate)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        type = try container.decode(WorkflowType.self, forKey: .type)
        requiredModels = try container.decode([String].self, forKey: .requiredModels)
        customNodes = try container.decode([String].self, forKey: .customNodes)
        parameters = try container.decode([WorkflowParameter].self, forKey: .parameters)
        
        // Decode workflow JSON
        workflowJSON = try container.decode([String: AnyCodable].self, forKey: .workflowJSON).mapValues { $0.value }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(filename, forKey: .filename)
        try container.encode(importDate, forKey: .importDate)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encode(type, forKey: .type)
        try container.encode(requiredModels, forKey: .requiredModels)
        try container.encode(customNodes, forKey: .customNodes)
        try container.encode(parameters, forKey: .parameters)
        
        // Encode workflow JSON
        let codableWorkflow = workflowJSON.mapValues { AnyCodable($0) }
        try container.encode(codableWorkflow, forKey: .workflowJSON)
    }
    
    static func fromRawWorkflow(workflowJSON: [String: Any], filename: String) -> ImportedWorkflow {
        let analyzer = WorkflowAnalyzer()
        let analysis = analyzer.analyzeWorkflow(workflowJSON)
        
        let name = filename.replacingOccurrences(of: ".json", with: "")
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
        
        return ImportedWorkflow(
            id: UUID().uuidString,
            name: name,
            filename: filename,
            workflowJSON: workflowJSON,
            importDate: Date(),
            description: nil,
            type: analysis.type,
            requiredModels: analysis.requiredModels,
            customNodes: analysis.customNodes,
            parameters: analysis.parameters
        )
    }
}

// MARK: - Supporting Types

enum WorkflowType: String, Codable, CaseIterable {
    case textToImage = "text2img"
    case imageToImage = "img2img"
    case inpainting = "inpainting"
    case upscaling = "upscaling"
    case controlNet = "controlnet"
    case unknown = "unknown"
    
    var displayName: String {
        switch self {
        case .textToImage: return "Text to Image"
        case .imageToImage: return "Image to Image"
        case .inpainting: return "Inpainting"
        case .upscaling: return "Upscaling"
        case .controlNet: return "ControlNet"
        case .unknown: return "Unknown"
        }
    }
}

struct WorkflowParameter: Identifiable, Codable {
    let id: String
    let name: String
    let type: ParameterType
    let defaultValue: String?
    let nodeId: String
    let fieldName: String
    
    enum ParameterType: String, Codable {
        case text = "text"
        case number = "number"
        case boolean = "boolean"
        case selection = "selection"
        case model = "model"
        case unknown = "unknown"
    }
}

enum WorkflowError: LocalizedError {
    case invalidFormat
    case emptyWorkflow
    case invalidComfyUIFormat
    case noDataInPasteboard
    case validationFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidFormat:
            return "Invalid workflow format. Please select a valid ComfyUI JSON workflow file."
        case .emptyWorkflow:
            return "Workflow appears to be empty."
        case .invalidComfyUIFormat:
            return "This doesn't appear to be a valid ComfyUI workflow."
        case .noDataInPasteboard:
            return "No workflow data found in pasteboard."
        case .validationFailed(let message):
            return "Workflow validation failed: \(message)"
        }
    }
}

// MARK: - AnyCodable Helper

struct AnyCodable: Codable {
    let value: Any
    
    init(_ value: Any) {
        self.value = value
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dictionary = try? container.decode([String: AnyCodable].self) {
            value = dictionary.mapValues { $0.value }
        } else {
            value = NSNull()
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch value {
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            try container.encodeNil()
        }
    }
}
