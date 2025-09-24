//
//  WorkflowAnalyzer.swift
//  elmer (Mac)
//
//  Analyzes ComfyUI workflows to extract parameters, models, and metadata
//

import Foundation

class WorkflowAnalyzer {
    
    struct WorkflowAnalysis {
        let type: WorkflowType
        let requiredModels: [String]
        let customNodes: [String]
        let parameters: [WorkflowParameter]
        let inputNodes: [String]
        let outputNodes: [String]
    }
    
    func analyzeWorkflow(_ workflowJSON: [String: Any]) -> WorkflowAnalysis {
        var requiredModels: Set<String> = []
        var customNodes: Set<String> = []
        var parameters: [WorkflowParameter] = []
        var inputNodes: [String] = []
        var outputNodes: [String] = []
        
        // Analyze each node in the workflow
        for (nodeId, nodeValue) in workflowJSON {
            guard let node = nodeValue as? [String: Any],
                  let classType = node["class_type"] as? String else {
                continue
            }
            
            // Track custom nodes (non-built-in ComfyUI nodes)
            if isCustomNode(classType) {
                customNodes.insert(classType)
            }
            
            // Track input/output nodes
            if isInputNode(classType) {
                inputNodes.append(nodeId)
            }
            
            if isOutputNode(classType) {
                outputNodes.append(nodeId)
            }
            
            // Extract models and parameters from node inputs
            if let inputs = node["inputs"] as? [String: Any] {
                // Extract model requirements
                extractModels(from: inputs, classType: classType).forEach { requiredModels.insert($0) }
                
                // Extract parameters
                parameters.append(contentsOf: extractParameters(from: inputs, nodeId: nodeId, classType: classType))
            }
        }
        
        // Determine workflow type
        let workflowType = determineWorkflowType(from: workflowJSON, customNodes: Array(customNodes))
        
        return WorkflowAnalysis(
            type: workflowType,
            requiredModels: Array(requiredModels).sorted(),
            customNodes: Array(customNodes).sorted(),
            parameters: parameters,
            inputNodes: inputNodes,
            outputNodes: outputNodes
        )
    }
    
    // MARK: - Model Extraction
    
    private func extractModels(from inputs: [String: Any], classType: String) -> [String] {
        var models: [String] = []
        
        // Common model input field names
        let modelFields = [
            "ckpt_name", "checkpoint_name", "model_name", "unet_name",
            "clip_name", "vae_name", "lora_name", "embedding_name",
            "controlnet_name", "upscale_model_name"
        ]
        
        for field in modelFields {
            if let modelName = inputs[field] as? String, !modelName.isEmpty {
                models.append(modelName)
            }
        }
        
        // Special handling for specific node types
        switch classType {
        case "CheckpointLoaderSimple", "CheckpointLoader":
            if let ckptName = inputs["ckpt_name"] as? String {
                models.append(ckptName)
            }
            
        case "UnetLoaderGGUF":
            if let unetName = inputs["unet_name"] as? String {
                models.append(unetName)
            }
            
        case "CLIPLoader":
            if let clipName = inputs["clip_name"] as? String {
                models.append(clipName)
            }
            
        case "VAELoader":
            if let vaeName = inputs["vae_name"] as? String {
                models.append(vaeName)
            }
            
        case "LoraLoader", "LoRALoader":
            if let loraName = inputs["lora_name"] as? String {
                models.append(loraName)
            }
            
        case "ControlNetLoader":
            if let controlnetName = inputs["control_net_name"] as? String {
                models.append(controlnetName)
            }
            
        default:
            break
        }
        
        return models
    }
    
    // MARK: - Parameter Extraction
    
    private func extractParameters(from inputs: [String: Any], nodeId: String, classType: String) -> [WorkflowParameter] {
        var parameters: [WorkflowParameter] = []
        
        // Parameters that should be exposed to users (common modifiable fields)
        let exposableFields = [
            "text", "prompt", "negative_prompt", "seed", "steps", "cfg", "strength", "denoise",
            "width", "height", "batch_size", "sampler_name", "scheduler", "guidance_scale"
        ]
        
        for (fieldName, value) in inputs {
            // Only extract certain types of parameters that make sense to expose
            guard exposableFields.contains(fieldName.lowercased()) ||
                  fieldName.lowercased().contains("prompt") ||
                  fieldName.lowercased().contains("text") ||
                  fieldName.lowercased().contains("seed") ||
                  fieldName.lowercased().contains("step") ||
                  fieldName.lowercased().contains("cfg") else {
                continue
            }
            
            // Skip connection arrays (these are node connections, not parameters)
            if value is [Any] {
                continue
            }
            
            let parameterType = determineParameterType(value: value, fieldName: fieldName)
            let defaultValue = formatDefaultValue(value: value)
            
            let parameter = WorkflowParameter(
                id: UUID().uuidString,
                name: humanReadableName(for: fieldName),
                type: parameterType,
                defaultValue: defaultValue,
                nodeId: nodeId,
                fieldName: fieldName
            )
            
            parameters.append(parameter)
        }
        
        return parameters
    }
    
    private func determineParameterType(value: Any, fieldName: String) -> WorkflowParameter.ParameterType {
        switch value {
        case is String:
            if fieldName.lowercased().contains("text") || fieldName.lowercased().contains("prompt") {
                return .text
            } else if fieldName.lowercased().contains("sampler") || fieldName.lowercased().contains("scheduler") {
                return .selection
            } else if fieldName.lowercased().contains("model") || fieldName.lowercased().contains("ckpt") {
                return .model
            } else {
                return .text
            }
            
        case is Int, is Double, is Float:
            return .number
            
        case is Bool:
            return .boolean
            
        default:
            return .unknown
        }
    }
    
    private func formatDefaultValue(value: Any) -> String? {
        switch value {
        case let string as String:
            return string
        case let number as NSNumber:
            return number.stringValue
        case let bool as Bool:
            return bool ? "true" : "false"
        default:
            return nil
        }
    }
    
    private func humanReadableName(for fieldName: String) -> String {
        return fieldName
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }
    
    // MARK: - Node Classification
    
    private func isCustomNode(_ classType: String) -> Bool {
        // Built-in ComfyUI node types (partial list of most common ones)
        let builtInNodes: Set<String> = [
            "KSampler", "KSamplerAdvanced", "CheckpointLoaderSimple", "CheckpointLoader",
            "CLIPTextEncode", "CLIPTextEncodeSDXL", "VAEDecode", "VAEEncode",
            "SaveImage", "PreviewImage", "LoadImage", "ImageScale",
            "LatentUpscale", "LatentUpscaleBy", "EmptyLatentImage",
            "CLIPLoader", "VAELoader", "LoraLoader", "LoRALoader",
            "ConditioningCombine", "ConditioningConcat", "ConditioningAverage",
            "ControlNetLoader", "ControlNetApply", "ControlNetApplyAdvanced",
            "ImageToMask", "MaskToImage", "InvertMask", "CropMask",
            "ModelMergeSimple", "ModelMergeBlocks", "ModelMergeSubtract"
        ]
        
        return !builtInNodes.contains(classType)
    }
    
    private func isInputNode(_ classType: String) -> Bool {
        let inputNodes: Set<String> = [
            "LoadImage", "CLIPTextEncode", "CLIPTextEncodeSDXL",
            "EmptyLatentImage", "CheckpointLoaderSimple", "CheckpointLoader"
        ]
        
        return inputNodes.contains(classType) ||
               classType.lowercased().contains("input") ||
               classType.lowercased().contains("load")
    }
    
    private func isOutputNode(_ classType: String) -> Bool {
        let outputNodes: Set<String> = [
            "SaveImage", "PreviewImage", "VAEDecode"
        ]
        
        return outputNodes.contains(classType) ||
               classType.lowercased().contains("save") ||
               classType.lowercased().contains("preview") ||
               classType.lowercased().contains("output")
    }
    
    // MARK: - Workflow Type Detection
    
    private func determineWorkflowType(from workflowJSON: [String: Any], customNodes: [String]) -> WorkflowType {
        var hasImageInput = false
        var hasInpainting = false
        var hasUpscaling = false
        var hasControlNet = false
        
        // Analyze nodes to determine workflow type
        for (_, nodeValue) in workflowJSON {
            guard let node = nodeValue as? [String: Any],
                  let classType = node["class_type"] as? String else {
                continue
            }
            
            // Check for image input (img2img indicator)
            if classType == "LoadImage" {
                hasImageInput = true
            }
            
            // Check for inpainting nodes
            if classType.lowercased().contains("inpaint") ||
               classType.lowercased().contains("mask") {
                hasInpainting = true
            }
            
            // Check for upscaling nodes
            if classType.lowercased().contains("upscale") ||
               classType.lowercased().contains("esrgan") ||
               classType.lowercased().contains("realesrgan") {
                hasUpscaling = true
            }
            
            // Check for ControlNet
            if classType.lowercased().contains("controlnet") ||
               classType == "ControlNetLoader" ||
               classType == "ControlNetApply" {
                hasControlNet = true
            }
        }
        
        // Check custom nodes for workflow type hints
        for customNode in customNodes {
            if customNode.lowercased().contains("controlnet") {
                hasControlNet = true
            } else if customNode.lowercased().contains("upscale") {
                hasUpscaling = true
            } else if customNode.lowercased().contains("inpaint") {
                hasInpainting = true
            }
        }
        
        // Determine type based on analysis
        if hasInpainting {
            return .inpainting
        } else if hasUpscaling {
            return .upscaling
        } else if hasControlNet {
            return .controlNet
        } else if hasImageInput {
            return .imageToImage
        } else {
            return .textToImage // Default assumption
        }
    }
}