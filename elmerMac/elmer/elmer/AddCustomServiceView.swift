//
//  AddCustomServiceView.swift
//  elmer
//
//  Full-screen Add Custom Service view with clean two-column layout
//

import SwiftUI

struct AddCustomServiceView: View {
    @EnvironmentObject var serviceManager: ServiceManager
    @Binding var currentView: ContentView.AppView
    
    @State private var serviceName = ""
    @State private var serviceType: ServiceType = .languageModel
    @State private var connectionType: ConnectionType = .localPort
    @State private var localPort = ""
    @State private var remoteURL = ""
    @State private var apiFormat: APIFormat = .openai
    @State private var healthEndpoint = "/health"
    
    @State private var isTestingConnection = false
    @State private var connectionTestResult: ConnectionTestResult?
    
    enum ConnectionType: String, CaseIterable {
        case localPort = "Local Port"
        case remoteURL = "Remote URL"
    }
    
    enum ConnectionTestResult {
        case success
        case failure(String)
        
        var isSuccess: Bool {
            switch self {
            case .success: return true
            case .failure: return false
            }
        }
    }
    
    var isValid: Bool {
        !serviceName.isEmpty && 
        ((connectionType == .localPort && !localPort.isEmpty && Int(localPort) != nil) ||
         (connectionType == .remoteURL && !remoteURL.isEmpty))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            
            ScrollView {
                VStack(spacing: 40) {
                    // Padding from divider
                    Spacer()
                        .frame(height: 20)
                    // Two-column form
                    VStack(spacing: 24) {
                        // Service Name Row
                        HStack(alignment: .center) {
                            Text("Service Name")
                                .font(.system(size: 15, weight: .regular))
                                        .foregroundColor(Color(nsColor: GeistTheme.textSecondary))
                                        .frame(width: 160, alignment: .leading)
                                    
                                    TextField("Enter service name", text: $serviceName)
                                .textFieldStyle(.plain)
                                .font(.system(size: 14, weight: .regular))
                                .foregroundColor(Color(nsColor: GeistTheme.textPrimary))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color(nsColor: GeistTheme.surface))
                                        .stroke(Color(nsColor: GeistTheme.border), lineWidth: 1)
                                )
                                .frame(maxWidth: 350)
                        }
                        
                        // Service Type Row
                        HStack(alignment: .center) {
                            Text("Type")
                                .font(.system(size: 15, weight: .regular))
                                .foregroundColor(Color(nsColor: GeistTheme.textSecondary))
                                .frame(width: 160, alignment: .leading)
                            
                            Picker("", selection: $serviceType) {
                                Text("Language Model").tag(ServiceType.languageModel)
                                Text("Image Generation").tag(ServiceType.imageGeneration)
                                Text("Custom").tag(ServiceType.custom)
                            }
                            .pickerStyle(MenuPickerStyle())
                            .frame(maxWidth: 350, alignment: .leading)
                        }
                        
                        // API Format Row
                        HStack(alignment: .center) {
                            Text("API Format")
                                .font(.system(size: 15, weight: .regular))
                                .foregroundColor(Color(nsColor: GeistTheme.textSecondary))
                                .frame(width: 160, alignment: .leading)
                            
                            Picker("", selection: $apiFormat) {
                                Text("OpenAI Compatible").tag(APIFormat.openai)
                                Text("ComfyUI").tag(APIFormat.comfyui)
                                Text("Custom").tag(APIFormat.custom)
                            }
                            .pickerStyle(MenuPickerStyle())
                            .frame(maxWidth: 350, alignment: .leading)
                        }
                        
                        // Connection Type Row
                        HStack(alignment: .center) {
                            Text("Connection Type")
                                .font(.system(size: 15, weight: .regular))
                                .foregroundColor(Color(nsColor: GeistTheme.textSecondary))
                                .frame(width: 160, alignment: .leading)
                            
                            Picker("", selection: $connectionType) {
                                ForEach(ConnectionType.allCases, id: \.self) { type in
                                    Text(type.rawValue).tag(type)
                                }
                            }
                            .pickerStyle(SegmentedPickerStyle())
                            .frame(maxWidth: 350)
                        }
                        
                        // Port Row (Local Port only)
                        if connectionType == .localPort {
                            HStack(alignment: .center) {
                                Text("Port")
                                    .font(.system(size: 15, weight: .regular))
                                    .foregroundColor(Color(nsColor: GeistTheme.textSecondary))
                                    .frame(width: 160, alignment: .leading)
                                
                                TextField("11434", text: $localPort)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 14, weight: .regular))
                                    .foregroundColor(Color(nsColor: GeistTheme.textPrimary))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color(nsColor: GeistTheme.surface))
                                            .stroke(Color(nsColor: GeistTheme.border), lineWidth: 1)
                                    )
                                    .frame(maxWidth: 350, alignment: .leading)
                            }
                        }
                        
                        // Health Endpoint Row (Local Port only)
                        if connectionType == .localPort {
                            HStack(alignment: .center) {
                                Text("Health Endpoint")
                                    .font(.system(size: 15, weight: .regular))
                                    .foregroundColor(Color(nsColor: GeistTheme.textSecondary))
                                    .frame(width: 160, alignment: .leading)
                                
                                TextField("/health", text: $healthEndpoint)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 14, weight: .regular))
                                    .foregroundColor(Color(nsColor: GeistTheme.textPrimary))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color(nsColor: GeistTheme.surface))
                                            .stroke(Color(nsColor: GeistTheme.border), lineWidth: 1)
                                    )
                                    .frame(maxWidth: 350, alignment: .leading)
                            }
                        }
                        
                        // Remote URL Row (Remote URL only)
                        if connectionType == .remoteURL {
                            HStack(alignment: .center) {
                                Text("Remote URL")
                                    .font(.system(size: 15, weight: .regular))
                                    .foregroundColor(Color(nsColor: GeistTheme.textSecondary))
                                    .frame(width: 160, alignment: .leading)
                                
                                VStack(alignment: .leading, spacing: 6) {
                                    TextField("http://192.168.1.100:11434", text: $remoteURL)
                                        .textFieldStyle(.plain)
                                        .font(.system(size: 14, weight: .regular))
                                        .foregroundColor(Color(nsColor: GeistTheme.textPrimary))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 10)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(Color(nsColor: GeistTheme.surface))
                                                .stroke(Color(nsColor: GeistTheme.border), lineWidth: 1)
                                        )
                                        .frame(maxWidth: 350)
                                    
                                    Text("Include protocol and port")
                                        .font(.system(size: 12, weight: .regular))
                                        .foregroundColor(Color(nsColor: GeistTheme.textTertiary))
                                }
                                .frame(maxWidth: 350, alignment: .leading)
                            }
                        }
                        
                        // Quick Presets Row
                        HStack(alignment: .center) {
                            Text("Quick Presets")
                                .font(.system(size: 15, weight: .regular))
                                .foregroundColor(Color(nsColor: GeistTheme.textSecondary))
                                .frame(width: 160, alignment: .leading)
                            
                            HStack(spacing: 10) {
                                ThemedButton(title: "Ollama", action: applyOllamaPreset, style: .secondary)
                                ThemedButton(title: "LM Studio", action: applyLMStudioPreset, style: .secondary)
                                ThemedButton(title: "ComfyUI", action: applyComfyUIPreset, style: .secondary)
                                ThemedButton(title: "Text Gen", action: applyTextGenPreset, style: .secondary)
                            }
                        }
                        
                        // Test Connection Result
                        if let result = connectionTestResult {
                            HStack(alignment: .center) {
                                Text("")
                                    .frame(width: 160, alignment: .leading)
                                
                                HStack(spacing: 8) {
                                    switch result {
                                    case .success:
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundColor(Color(nsColor: GeistTheme.success))
                                        Text("Connection successful!")
                                            .font(.system(size: 13, weight: .regular))
                                            .foregroundColor(Color(nsColor: GeistTheme.success))
                                    case .failure(let error):
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundColor(Color(nsColor: GeistTheme.error))
                                        Text("Connection failed: \(error)")
                                            .font(.system(size: 13, weight: .regular))
                                            .foregroundColor(Color(nsColor: GeistTheme.error))
                                            .lineLimit(2)
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(
                                    Color(nsColor: result.isSuccess ? GeistTheme.successSubtle : GeistTheme.surface)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(
                                            Color(nsColor: result.isSuccess ? GeistTheme.success : GeistTheme.error).opacity(0.3),
                                            lineWidth: 1
                                        )
                                )
                                .cornerRadius(6)
                                .frame(maxWidth: 350)
                            }
                        }
                        
                        // Actions - aligned to the right edge of the form column
                        HStack(alignment: .center) {
                            Text("")
                                .frame(width: 160, alignment: .leading)
                            
                            HStack {
                                Spacer()
                                
                                HStack(spacing: 16) {
                                    if isTestingConnection {
                                        HStack(spacing: 12) {
                                            ProgressView()
                                                .progressViewStyle(CircularProgressViewStyle())
                                                .scaleEffect(0.8)
                                                .controlSize(.small)
                                            
                                            Text("Testing connection...")
                                                .font(.system(size: 14, weight: .regular))
                                                .foregroundColor(Color(nsColor: GeistTheme.textSecondary))
                                        }
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                    } else {
                                        ThemedButton(
                                            title: "Test Connection",
                                            action: testConnection,
                                            style: .secondary
                                        )
                                        .disabled(!isValid)
                                    }
                                    
                                    ThemedButton(
                                        title: "Add Service",
                                        action: addService,
                                        style: .primary
                                    )
                                    .disabled(!isValid)
                                }
                            }
                            .frame(maxWidth: 350)
                        }
                        .padding(.top, 16)
                    }
                }
                .padding(.horizontal, 60)
                .padding(.vertical, 40)
            }
            
            Spacer()
        }
    }
    
    private func applyOllamaPreset() {
        serviceName = "Ollama (Custom)"
        serviceType = .languageModel
        apiFormat = .openai
        healthEndpoint = "/api/tags"
        if connectionType == .localPort {
            localPort = "11434"
        }
    }
    
    private func applyLMStudioPreset() {
        serviceName = "LM Studio (Custom)"
        serviceType = .languageModel
        apiFormat = .openai
        healthEndpoint = "/v1/models"
        if connectionType == .localPort {
            localPort = "1234"
        }
    }
    
    private func applyComfyUIPreset() {
        serviceName = "ComfyUI (Custom)"
        serviceType = .imageGeneration
        apiFormat = .comfyui
        healthEndpoint = "/system_stats"
        if connectionType == .localPort {
            localPort = "8188"
        }
    }
    
    private func applyTextGenPreset() {
        serviceName = "Text Generation WebUI"
        serviceType = .languageModel
        apiFormat = .openai
        healthEndpoint = "/v1/models"
        if connectionType == .localPort {
            localPort = "5000"
        }
    }
    
    private func testConnection() {
        isTestingConnection = true
        connectionTestResult = nil
        
        Task {
            let port: Int
            if connectionType == .localPort {
                port = Int(localPort) ?? 0
            } else {
                port = 0
            }
            
            let testService = AIService(
                name: serviceName.isEmpty ? "Test" : serviceName,
                type: serviceType,
                localPort: port,
                healthCheckEndpoint: healthEndpoint,
                apiFormat: apiFormat
            )
            
            let isHealthy: Bool
            if connectionType == .remoteURL {
                if let url = URL(string: remoteURL + healthEndpoint) {
                    isHealthy = await testRemoteConnection(url: url)
                } else {
                    isHealthy = false
                }
            } else {
                isHealthy = await testService.checkHealth()
            }
            
            await MainActor.run {
                isTestingConnection = false
                connectionTestResult = isHealthy ? .success : .failure("Could not connect to service")
            }
        }
    }
    
    private func testRemoteConnection(url: URL) async -> Bool {
        var request = URLRequest(url: url)
        request.timeoutInterval = 5.0
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                return httpResponse.statusCode < 500
            }
        } catch {
            print("Remote connection test failed: \(error)")
        }
        
        return false
    }
    
    private func addService() {
        let port: Int
        if connectionType == .localPort {
            port = Int(localPort) ?? 0
        } else {
            port = 0
        }
        
        let newService = AIService(
            name: serviceName,
            type: serviceType,
            localPort: port,
            healthCheckEndpoint: healthEndpoint,
            apiFormat: apiFormat,
            customName: connectionType == .remoteURL ? remoteURL : nil
        )
        
        serviceManager.addService(newService)
        currentView = .services
    }
}