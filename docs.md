# Elmer - Local AI Hub Complete Project Documentation

## Project Overview

Create a Mac companion app and iOS app that allows users to access all their local AI services (LLM, image generation, etc.) from their iPhone via secure tunnels.

## Architecture

```
Mac (Server) → Cloudflared Tunnels → Internet → iOS App (Client)
     ↓
- LM Studio (port 1234)
- ComfyUI (port 8188)
- Ollama (port 11434)
- Other AI services
```

## Part 1: Mac Companion App

### Project Setup

1. **Create new macOS app in Xcode**
   - Product Name: `LocalAIHub`
   - Interface: SwiftUI
   - Language: Swift
   - Minimum deployment: macOS 12.0

2. **Download cloudflared binaries**
   ```bash
   # In project root
   mkdir Resources
   cd Resources
   
   # Intel Mac
   curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-darwin-amd64 -o cloudflared-intel
   
   # Apple Silicon
   curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-darwin-arm64 -o cloudflared-arm
   
   # Make executable
   chmod +x cloudflared-*
   ```

3. **Add binaries to Xcode project**
   - Drag both cloudflared files to Xcode project
   - Target Membership: ✓ LocalAIHub
   - Copy items if needed: ✓

### Core Implementation Files

#### `LocalAIHubApp.swift`
```swift
import SwiftUI

@main
struct LocalAIHubApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var serviceManager = ServiceManager()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(serviceManager)
                .frame(minWidth: 600, minHeight: 500)
        }
        .windowResizability(.contentSize)
        
        MenuBarExtra("AI Hub", systemImage: "brain") {
            MenuBarView()
                .environmentObject(serviceManager)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Setup code here
    }
}
```

#### `Models.swift`
```swift
import Foundation

enum ServiceType: String, CaseIterable, Codable {
    case llm = "Language Model"
    case imageGen = "Image Generation"
    case voiceGen = "Voice Generation"
    case musicGen = "Music Generation"
    
    var icon: String {
        switch self {
        case .llm: return "brain"
        case .imageGen: return "photo"
        case .voiceGen: return "waveform"
        case .musicGen: return "music.note"
        }
    }
}

enum APIFormat: String, Codable {
    case openai = "OpenAI"
    case comfyui = "ComfyUI"
    case gradio = "Gradio"
    case custom = "Custom"
}

struct AIService: Identifiable, Codable {
    let id = UUID()
    let name: String
    let type: ServiceType
    let localPort: Int
    let healthCheckEndpoint: String
    let apiFormat: APIFormat
    var isRunning: Bool = false
    var tunnelURL: String?
    
    // Default services
    static let defaults = [
        AIService(
            name: "LM Studio",
            type: .llm,
            localPort: 1234,
            healthCheckEndpoint: "/v1/models",
            apiFormat: .openai
        ),
        AIService(
            name: "ComfyUI",
            type: .imageGen,
            localPort: 8188,
            healthCheckEndpoint: "/",
            apiFormat: .comfyui
        ),
        AIService(
            name: "Ollama",
            type: .llm,
            localPort: 11434,
            healthCheckEndpoint: "/api/tags",
            apiFormat: .openai
        ),
        AIService(
            name: "Stable Diffusion WebUI",
            type: .imageGen,
            localPort: 7860,
            healthCheckEndpoint: "/",
            apiFormat: .gradio
        )
    ]
}

struct ServiceConfig: Codable {
    let version = "1.0"
    let services: [ExportedService]
    let timestamp = Date()
}

struct ExportedService: Codable {
    let name: String
    let type: String
    let url: String
    let apiFormat: String
}
```

#### `ServiceManager.swift`
```swift
import Foundation
import Combine

class ServiceManager: ObservableObject {
    @Published var services: [AIService] = AIService.defaults
    @Published var isMonitoring = false
    
    private var tunnelProcesses: [UUID: Process] = [:]
    private var timer: Timer?
    
    init() {
        loadServices()
        startMonitoring()
    }
    
    func startMonitoring() {
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            self.checkAllServices()
        }
        isMonitoring = true
    }
    
    func checkAllServices() {
        for index in services.indices {
            checkService(at: index)
        }
    }
    
    func checkService(at index: Int) {
        Task {
            let service = services[index]
            let urlString = "http://localhost:\(service.localPort)\(service.healthCheckEndpoint)"
            guard let url = URL(string: urlString) else { return }
            
            do {
                let (_, response) = try await URLSession.shared.data(from: url)
                await MainActor.run {
                    self.services[index].isRunning = (response as? HTTPURLResponse)?.statusCode == 200
                }
            } catch {
                await MainActor.run {
                    self.services[index].isRunning = false
                }
            }
        }
    }
    
    func startTunnel(for service: AIService) {
        guard service.isRunning else { return }
        
        let process = Process()
        let arch = getArchitecture()
        
        guard let cloudflaredPath = Bundle.main.path(forResource: "cloudflared-\(arch)", ofType: nil) else {
            print("Cloudflared binary not found")
            return
        }
        
        process.executableURL = URL(fileURLWithPath: cloudflaredPath)
        process.arguments = ["tunnel", "--url", "http://localhost:\(service.localPort)"]
        
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        
        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let output = String(data: data, encoding: .utf8) else { return }
            
            if let url = self?.extractURL(from: output) {
                DispatchQueue.main.async {
                    if let index = self?.services.firstIndex(where: { $0.id == service.id }) {
                        self?.services[index].tunnelURL = url
                        self?.saveServices()
                    }
                }
            }
        }
        
        do {
            try process.run()
            tunnelProcesses[service.id] = process
        } catch {
            print("Failed to start tunnel: \(error)")
        }
    }
    
    func stopTunnel(for service: AIService) {
        if let process = tunnelProcesses[service.id] {
            process.terminate()
            tunnelProcesses.removeValue(forKey: service.id)
            
            if let index = services.firstIndex(where: { $0.id == service.id }) {
                services[index].tunnelURL = nil
                saveServices()
            }
        }
    }
    
    func exportConfig() -> Data? {
        let exportedServices = services.compactMap { service -> ExportedService? in
            guard let url = service.tunnelURL else { return nil }
            return ExportedService(
                name: service.name,
                type: service.type.rawValue,
                url: url,
                apiFormat: service.apiFormat.rawValue
            )
        }
        
        let config = ServiceConfig(services: exportedServices)
        return try? JSONEncoder().encode(config)
    }
    
    // Helper methods
    private func extractURL(from output: String) -> String? {
        let pattern = "https://[a-zA-Z0-9-]+\\.trycloudflare\\.com"
        if let range = output.range(of: pattern, options: .regularExpression) {
            return String(output[range])
        }
        return nil
    }
    
    private func getArchitecture() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machine = withUnsafeBytes(of: &systemInfo.machine) { bytes in
            bytes.compactMap { $0 == 0 ? nil : Character(UnicodeScalar($0)) }
        }
        return String(machine).contains("arm64") ? "arm" : "intel"
    }
    
    private func saveServices() {
        if let encoded = try? JSONEncoder().encode(services) {
            UserDefaults.standard.set(encoded, forKey: "services")
        }
    }
    
    private func loadServices() {
        if let data = UserDefaults.standard.data(forKey: "services"),
           let decoded = try? JSONDecoder().decode([AIService].self, from: data) {
            services = decoded
        }
    }
}
```

#### `ContentView.swift`
```swift
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var serviceManager: ServiceManager
    @State private var showingAddService = false
    @State private var showingExport = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HeaderView()
            
            // Services List
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(serviceManager.services) { service in
                        ServiceCardView(service: service)
                    }
                }
                .padding()
            }
            
            // Bottom Bar
            HStack {
                Button("Add Service") {
                    showingAddService = true
                }
                
                Spacer()
                
                Button("Export Config") {
                    showingExport = true
                }
                .disabled(serviceManager.services.allSatisfy { $0.tunnelURL == nil })
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
        }
        .sheet(isPresented: $showingAddService) {
            AddServiceView()
        }
        .sheet(isPresented: $showingExport) {
            ExportView()
        }
    }
}

struct HeaderView: View {
    var body: some View {
        HStack {
            Image(systemName: "brain")
                .font(.system(size: 40))
                .foregroundColor(.blue)
            
            VStack(alignment: .leading) {
                Text("Local AI Hub")
                    .font(.title)
                    .bold()
                Text("Connect your iPhone to local AI services")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }
}

struct ServiceCardView: View {
    let service: AIService
    @EnvironmentObject var serviceManager: ServiceManager
    
    var body: some View {
        GroupBox {
            HStack {
                // Icon and Info
                Image(systemName: service.type.icon)
                    .font(.title2)
                    .foregroundColor(service.isRunning ? .green : .gray)
                
                VStack(alignment: .leading) {
                    Text(service.name)
                        .font(.headline)
                    Text("Port: \(service.localPort)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Status and Actions
                VStack(alignment: .trailing) {
                    if service.isRunning {
                        if let url = service.tunnelURL {
                            Text("Connected")
                                .font(.caption)
                                .foregroundColor(.green)
                            
                            HStack {
                                Button("Copy URL") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(url, forType: .string)
                                }
                                .buttonStyle(.link)
                                
                                Button("Stop") {
                                    serviceManager.stopTunnel(for: service)
                                }
                                .buttonStyle(.link)
                            }
                        } else {
                            Button("Enable Remote Access") {
                                serviceManager.startTunnel(for: service)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    } else {
                        Text("Service Not Running")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
}

struct ExportView: View {
    @EnvironmentObject var serviceManager: ServiceManager
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Export Configuration")
                .font(.title2)
                .bold()
            
            if let configData = serviceManager.exportConfig(),
               let qrImage = generateQRCode(from: configData) {
                
                Image(nsImage: qrImage)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 300, height: 300)
                
                Text("Scan this QR code with the iOS app")
                    .font(.caption)
                
                Button("Save Config File") {
                    saveConfigFile(data: configData)
                }
            }
            
            Button("Done") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(width: 400)
    }
    
    func generateQRCode(from data: Data) -> NSImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        
        let transform = CGAffineTransform(scaleX: 10, y: 10)
        guard let output = filter.outputImage?.transformed(by: transform) else { return nil }
        
        let rep = NSCIImageRep(ciImage: output)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }
    
    func saveConfigFile(data: Data) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "ai-hub-config.json"
        panel.begin { response in
            if response == .OK, let url = panel.url {
                try? data.write(to: url)
            }
        }
    }
}
```

## Part 2: iOS App

### Project Setup

1. **Create new iOS app in Xcode**
   - Product Name: `LocalAIHub`
   - Interface: SwiftUI
   - Language: Swift
   - Minimum deployment: iOS 16.0

### Core Implementation Files

#### `LocalAIHubApp.swift`
```swift
import SwiftUI

@main
struct LocalAIHubApp: App {
    @StateObject private var serviceStore = ServiceStore()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(serviceStore)
        }
    }
}
```

#### `Models.swift`
```swift
import Foundation

struct RemoteService: Identifiable, Codable {
    let id = UUID()
    let name: String
    let type: String
    let url: String
    let apiFormat: String
    
    var icon: String {
        switch type {
        case "Language Model": return "brain"
        case "Image Generation": return "photo"
        case "Voice Generation": return "waveform"
        case "Music Generation": return "music.note"
        default: return "questionmark"
        }
    }
}

struct ServiceConfig: Codable {
    let version: String
    let services: [RemoteService]
    let timestamp: Date
}

class ServiceStore: ObservableObject {
    @Published var services: [RemoteService] = []
    
    init() {
        loadServices()
    }
    
    func addServices(from config: ServiceConfig) {
        services = config.services
        saveServices()
    }
    
    func saveServices() {
        if let encoded = try? JSONEncoder().encode(services) {
            UserDefaults.standard.set(encoded, forKey: "services")
        }
    }
    
    func loadServices() {
        if let data = UserDefaults.standard.data(forKey: "services"),
           let decoded = try? JSONDecoder().decode([RemoteService].self, from: data) {
            services = decoded
        }
    }
}
```

#### `ContentView.swift`
```swift
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var serviceStore: ServiceStore
    @State private var showingScanner = false
    @State private var showingAddManual = false
    
    var body: some View {
        NavigationView {
            if serviceStore.services.isEmpty {
                OnboardingView()
            } else {
                ServiceListView()
            }
        }
    }
}

struct OnboardingView: View {
    @State private var showingScanner = false
    @State private var showingManual = false
    
    var body: some View {
        VStack(spacing: 30) {
            Image(systemName: "brain")
                .font(.system(size: 80))
                .foregroundColor(.blue)
            
            Text("Local AI Hub")
                .font(.largeTitle)
                .bold()
            
            Text("Connect to AI services running on your Mac")
                .font(.title3)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            VStack(spacing: 20) {
                Button(action: { showingScanner = true }) {
                    Label("Scan QR Code", systemImage: "qrcode.viewfinder")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                
                Button(action: { showingManual = true }) {
                    Label("Enter Manually", systemImage: "keyboard")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(10)
                }
            }
            .padding(.horizontal, 40)
        }
        .sheet(isPresented: $showingScanner) {
            QRScannerView()
        }
        .sheet(isPresented: $showingManual) {
            ManualEntryView()
        }
    }
}

struct ServiceListView: View {
    @EnvironmentObject var serviceStore: ServiceStore
    
    var body: some View {
        List(serviceStore.services) { service in
            NavigationLink(destination: ServiceDetailView(service: service)) {
                HStack {
                    Image(systemName: service.icon)
                        .font(.title2)
                        .foregroundColor(.blue)
                        .frame(width: 40)
                    
                    VStack(alignment: .leading) {
                        Text(service.name)
                            .font(.headline)
                        Text(service.type)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("AI Services")
        .toolbar {
            Button(action: { /* Add service */ }) {
                Image(systemName: "plus")
            }
        }
    }
}

struct ServiceDetailView: View {
    let service: RemoteService
    
    var body: some View {
        Group {
            switch service.apiFormat {
            case "OpenAI":
                ChatView(service: service)
            case "ComfyUI":
                ComfyUIView(service: service)
            case "Gradio":
                WebContainerView(url: service.url)
            default:
                WebContainerView(url: service.url)
            }
        }
        .navigationTitle(service.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
```

#### `ChatView.swift` (for LLM services)
```swift
import SwiftUI

struct ChatView: View {
    let service: RemoteService
    @State private var messages: [ChatMessage] = []
    @State private var inputText = ""
    @State private var isLoading = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(messages) { message in
                            MessageBubble(message: message)
                        }
                        
                        if isLoading {
                            HStack {
                                ProgressView()
                                    .padding()
                                Spacer()
                            }
                        }
                    }
                    .padding()
                    .onChange(of: messages.count) { _ in
                        withAnimation {
                            proxy.scrollTo(messages.last?.id, anchor: .bottom)
                        }
                    }
                }
            }
            
            // Input
            HStack {
                TextField("Type a message...", text: $inputText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .onSubmit {
                        sendMessage()
                    }
                
                Button(action: sendMessage) {
                    Image(systemName: "paperplane.fill")
                }
                .disabled(inputText.isEmpty || isLoading)
            }
            .padding()
            .background(Color(UIColor.systemBackground))
        }
    }
    
    func sendMessage() {
        let userMessage = ChatMessage(content: inputText, isUser: true)
        messages.append(userMessage)
        let currentInput = inputText
        inputText = ""
        
        Task {
            isLoading = true
            await callLLM(message: currentInput)
            isLoading = false
        }
    }
    
    func callLLM(message: String) async {
        guard let url = URL(string: "\(service.url)/v1/chat/completions") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "model": "default",
            "messages": messages.map { msg in
                ["role": msg.isUser ? "user" : "assistant", "content": msg.content]
            } + [["role": "user", "content": message]],
            "temperature": 0.7
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, _) = try await URLSession.shared.data(for: request)
            
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let choices = json["choices"] as? [[String: Any]],
               let firstChoice = choices.first,
               let message = firstChoice["message"] as? [String: Any],
               let content = message["content"] as? String {
                
                await MainActor.run {
                    messages.append(ChatMessage(content: content, isUser: false))
                }
            }
        } catch {
            await MainActor.run {
                messages.append(ChatMessage(content: "Error: \(error.localizedDescription)", isUser: false))
            }
        }
    }
}

struct ChatMessage: Identifiable {
    let id = UUID()
    let content: String
    let isUser: Bool
}

struct MessageBubble: View {
    let message: ChatMessage
    
    var body: some View {
        HStack {
            if message.isUser { Spacer() }
            
            Text(message.content)
                .padding(12)
                .background(message.isUser ? Color.blue : Color.gray.opacity(0.2))
                .foregroundColor(message.isUser ? .white : .primary)
                .cornerRadius(16)
                .frame(maxWidth: UIScreen.main.bounds.width * 0.75, alignment: message.isUser ? .trailing : .leading)
            
            if !message.isUser { Spacer() }
        }
    }
}
```

#### `ComfyUIView.swift` (for image generation)
```swift
import SwiftUI

struct ComfyUIView: View {
    let service: RemoteService
    @State private var prompt = ""
    @State private var negativePrompt = ""
    @State private var generatedImage: UIImage?
    @State private var isGenerating = false
    @State private var progress: Double = 0
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Input fields
                VStack(alignment: .leading) {
                    Text("Prompt")
                        .font(.headline)
                    TextEditor(text: $prompt)
                        .frame(height: 80)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.3)))
                    
                    Text("Negative Prompt")
                        .font(.headline)
                    TextEditor(text: $negativePrompt)
                        .frame(height: 60)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.3)))
                }
                .padding()
                
                // Generate button
                Button(action: generateImage) {
                    if isGenerating {
                        HStack {
                            ProgressView()
                            Text("Generating...")
                        }
                    } else {
                        Text("Generate Image")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(prompt.isEmpty || isGenerating)
                
                // Progress
                if isGenerating {
                    ProgressView(value: progress)
                        .padding()
                }
                
                // Generated image
                if let image = generatedImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .cornerRadius(12)
                        .padding()
                    
                    Button("Save to Photos") {
                        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                    }
                }
            }
        }
    }
    
    func generateImage() {
        // Implementation for ComfyUI API
        // This would include creating workflow, submitting job, polling for results
    }
}
```

### Additional Files Needed

#### `Info.plist` additions for both apps:
```xml
<!-- Mac App -->
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <true/>
</dict>

<!-- iOS App -->
<key>NSCameraUsageDescription</key>
<string>Scan QR codes to connect to services</string>
<key>NSPhotoLibraryAddUsageDescription</key>
<string>Save generated images to your photo library</string>
```

## Build & Distribution Instructions

### Mac App:
1. Add cloudflared binaries to Copy Files build phase
2. Set "Signing & Capabilities" to Developer ID
3. Archive and notarize for distribution outside App Store

### iOS App:
1. Standard iOS app distribution
2. Can be distributed via TestFlight or App Store

## Testing Instructions

1. Run Mac app and verify services are detected
2. Start a tunnel for at least one service
3. Export configuration via QR code
4. Scan with iOS app
5. Test each service type (chat, image generation, etc.)

## Key Features to Implement

1. **Auto-discovery** of running services on common ports
2. **Service health monitoring** with status indicators
3. **One-click tunnel creation** with cloudflared
4. **QR code config sharing** between Mac and iOS
5. **Native UI for each service type** (chat for LLMs, image gallery for generation)
6. **Persistent tunnel URLs** across app restarts (save to UserDefaults)
7. **Error handling** for network issues and service failures

## Architecture Notes

- Mac app runs continuously, managing tunnels
- iOS app connects to tunnel URLs, not local network
- Config is JSON-based for easy parsing
- Each service type has specialized UI in iOS app
- Web view fallback for unsupported service types


# Simple E2E Encryption Implementation Plan

## Overview
Add end-to-end encryption between iOS app and Mac services using a shared key from QR code setup. All traffic through Cloudflare will be encrypted.

## Architecture
```
iOS App ←[Encrypted Data]→ Cloudflare ←[Encrypted Data]→ Mac Proxy → Local AI Service
```
## Implementation Steps

### Step 1: Update Mac App Models

Add encryption key to the service configuration:

```swift
// In Models.swift, update ServiceConfig
struct ServiceConfig: Codable {
    let version = "2.0"  // Bump version
    let services: [ExportedService]
    let timestamp = Date()
    let encryptionKey: String  // NEW: Base64 encoded 256-bit key
}
```

### Step 2: Create Crypto Manager

Create a new file `CryptoManager.swift` in both Mac and iOS apps with identical implementation:

```swift
import CryptoKit
import Foundation

class CryptoManager {
    private let symmetricKey: SymmetricKey
    
    init(keyString: String) throws {
        guard let keyData = Data(base64Encoded: keyString) else {
            throw CryptoError.invalidKey
        }
        self.symmetricKey = SymmetricKey(data: keyData)
    }
    
    // Generate new key (Mac app only)
    static func generateKey() -> String {
        let key = SymmetricKey(size: .bits256)
        return key.withUnsafeBytes { bytes in
            Data(bytes).base64EncodedString()
        }
    }
    
    func encrypt(_ plaintext: String) throws -> String {
        guard let data = plaintext.data(using: .utf8) else {
            throw CryptoError.invalidInput
        }
        
        let sealedBox = try AES.GCM.seal(data, using: symmetricKey)
        
        // Combine nonce + ciphertext + tag
        var combined = Data()
        combined.append(sealedBox.nonce.withUnsafeBytes { Data($0) })
        combined.append(sealedBox.ciphertext)
        combined.append(sealedBox.tag)
        
        return combined.base64EncodedString()
    }
    
    func decrypt(_ encryptedString: String) throws -> String {
        guard let combined = Data(base64Encoded: encryptedString) else {
            throw CryptoError.invalidInput
        }
        
        let nonceSize = 12
        let tagSize = 16
        
        guard combined.count >= nonceSize + tagSize else {
            throw CryptoError.invalidInput
        }
        
        let nonce = try AES.GCM.Nonce(data: combined.prefix(nonceSize))
        let ciphertext = combined.dropFirst(nonceSize).dropLast(tagSize)
        let tag = combined.suffix(tagSize)
        
        let sealedBox = try AES.GCM.SealedBox(
            nonce: nonce,
            ciphertext: ciphertext,
            tag: tag
        )
        
        let decryptedData = try AES.GCM.open(sealedBox, using: symmetricKey)
        
        guard let plaintext = String(data: decryptedData, encoding: .utf8) else {
            throw CryptoError.invalidOutput
        }
        
        return plaintext
    }
}

enum CryptoError: Error {
    case invalidKey
    case invalidInput
    case invalidOutput
}
```

### Step 3: Update Mac App Service Manager

Modify `ServiceManager.swift` to include encryption:

```swift
class ServiceManager: ObservableObject {
    @Published var services: [AIService] = AIService.defaults
    @Published var isMonitoring = false
    @Published var encryptionKey: String = ""  // NEW
    
    private var proxyServers: [UUID: ProxyServer] = [:]  // NEW
    
    init() {
        loadServices()
        loadOrGenerateKey()  // NEW
        startMonitoring()
    }
    
    // NEW: Key management
    private func loadOrGenerateKey() {
        if let savedKey = UserDefaults.standard.string(forKey: "encryptionKey") {
            encryptionKey = savedKey
        } else {
            encryptionKey = CryptoManager.generateKey()
            UserDefaults.standard.set(encryptionKey, forKey: "encryptionKey")
        }
    }
    
    // MODIFIED: Start encrypted tunnel
    func startTunnel(for service: AIService) {
        guard service.isRunning else { return }
        
        // Start proxy server first
        let proxyPort = service.localPort + 10000
        startProxyServer(for: service, proxyPort: proxyPort)
        
        // Then create tunnel to proxy
        startCloudflaredTunnel(port: proxyPort) { tunnelURL in
            if let index = self.services.firstIndex(where: { $0.id == service.id }) {
                self.services[index].tunnelURL = tunnelURL
                self.saveServices()
            }
        }
    }
    
    // NEW: Start proxy server
    private func startProxyServer(for service: AIService, proxyPort: Int) {
        let proxy = ProxyServer(
            encryptionKey: encryptionKey,
            proxyPort: proxyPort,
            targetPort: service.localPort
        )
        
        proxy.start()
        proxyServers[service.id] = proxy
    }
    
    // MODIFIED: Export config with encryption key
    func exportConfig() -> Data? {
        let exportedServices = services.compactMap { service -> ExportedService? in
            guard let url = service.tunnelURL else { return nil }
            return ExportedService(
                name: service.name,
                type: service.type.rawValue,
                url: url,
                apiFormat: service.apiFormat.rawValue
            )
        }
        
        let config = ServiceConfig(
            services: exportedServices,
            encryptionKey: encryptionKey  // Include key
        )
        
        return try? JSONEncoder().encode(config)
    }
}
```

### Step 4: Create Proxy Server for Mac

Create new file `ProxyServer.swift` in Mac app:

```swift
import Foundation
import Network

class ProxyServer {
    private let crypto: CryptoManager
    private let proxyPort: Int
    private let targetPort: Int
    private var listener: NWListener?
    
    init(encryptionKey: String, proxyPort: Int, targetPort: Int) {
        self.crypto = try! CryptoManager(keyString: encryptionKey)
        self.proxyPort = proxyPort
        self.targetPort = targetPort
    }
    
    func start() {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        
        listener = try? NWListener(using: parameters, on: NWEndpoint.Port(integerLiteral: UInt16(proxyPort)))
        
        listener?.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }
        
        listener?.start(queue: .global())
    }
    
    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .global())
        
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self,
                  let data = data,
                  error == nil else { return }
            
            Task {
                await self.processRequest(data: data, connection: connection)
            }
        }
    }
    
    private func processRequest(data: Data, connection: NWConnection) async {
        do {
            // Parse HTTP request to get encrypted body
            let request = String(data: data, encoding: .utf8) ?? ""
            
            // Extract encrypted JSON from request body
            guard let bodyStart = request.range(of: "\r\n\r\n")?.upperBound else { return }
            let encryptedBody = String(request[bodyStart...])
            
            // Decrypt
            let decryptedBody = try crypto.decrypt(encryptedBody)
            
            // Forward to real service
            let url = URL(string: "http://localhost:\(targetPort)/v1/chat/completions")!
            var forwardRequest = URLRequest(url: url)
            forwardRequest.httpMethod = "POST"
            forwardRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            forwardRequest.httpBody = decryptedBody.data(using: .utf8)
            
            let (responseData, response) = try await URLSession.shared.data(for: forwardRequest)
            
            // Encrypt response
            let responseString = String(data: responseData, encoding: .utf8) ?? "{}"
            let encryptedResponse = try crypto.encrypt(responseString)
            
            // Send back
            let httpResponse = """
            HTTP/1.1 200 OK\r
            Content-Type: text/plain\r
            Content-Length: \(encryptedResponse.count)\r
            \r
            \(encryptedResponse)
            """
            
            connection.send(content: httpResponse.data(using: .utf8), completion: .contentProcessed { _ in
                connection.cancel()
            })
            
        } catch {
            // Send error response
            let errorResponse = "HTTP/1.1 500 Internal Server Error\r\n\r\n"
            connection.send(content: errorResponse.data(using: .utf8), completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }
    
    func stop() {
        listener?.cancel()
        listener = nil
    }
}
```

### Step 5: Update iOS App Models

Add encryption key to service config:

```swift
// Update ServiceConfig in iOS Models.swift
struct ServiceConfig: Codable {
    let version: String
    let services: [RemoteService]
    let timestamp: Date
    let encryptionKey: String  // NEW
}

// Update ServiceStore
class ServiceStore: ObservableObject {
    @Published var services: [RemoteService] = []
    @Published var encryptionKey: String = ""  // NEW
    
    func addServices(from config: ServiceConfig) {
        services = config.services
        encryptionKey = config.encryptionKey  // Save key
        saveServices()
    }
    
    private func saveServices() {
        // Save both services and key
        UserDefaults.standard.set(encryptionKey, forKey: "encryptionKey")
        if let encoded = try? JSONEncoder().encode(services) {
            UserDefaults.standard.set(encoded, forKey: "services")
        }
    }
    
    private func loadServices() {
        encryptionKey = UserDefaults.standard.string(forKey: "encryptionKey") ?? ""
        // ... rest of loading
    }
}
```

### Step 6: Create Secure API Client for iOS

Create new file `SecureAPIClient.swift` in iOS app:

```swift
import Foundation

class SecureAPIClient {
    private let crypto: CryptoManager
    private let serviceURL: String
    
    init(serviceURL: String, encryptionKey: String) throws {
        self.serviceURL = serviceURL
        self.crypto = try CryptoManager(keyString: encryptionKey)
    }
    
    func sendChatMessage(messages: [[String: String]]) async throws -> String {
        // Prepare request body
        let requestBody = [
            "model": "default",
            "messages": messages,
            "temperature": 0.7
        ]
        
        // Convert to JSON string
        let jsonData = try JSONSerialization.data(withJSONObject: requestBody)
        let jsonString = String(data: jsonData, encoding: .utf8)!
        
        // Encrypt
        let encryptedData = try crypto.encrypt(jsonString)
        
        // Send as plain text (proxy expects encrypted string)
        var request = URLRequest(url: URL(string: serviceURL)!)
        request.httpMethod = "POST"
        request.setValue("text/plain", forHTTPHeaderField: "Content-Type")
        request.httpBody = encryptedData.data(using: .utf8)
        
        // Get response
        let (data, _) = try await URLSession.shared.data(for: request)
        let encryptedResponse = String(data: data, encoding: .utf8) ?? ""
        
        // Decrypt
        let decryptedJSON = try crypto.decrypt(encryptedResponse)
        
        // Parse response
        let responseData = decryptedJSON.data(using: .utf8)!
        if let json = try JSONSerialization.jsonObject(with: responseData) as? [String: Any],
           let choices = json["choices"] as? [[String: Any]],
           let firstChoice = choices.first,
           let message = firstChoice["message"] as? [String: Any],
           let content = message["content"] as? String {
            return content
        }
        
        throw APIError.invalidResponse
    }
}

enum APIError: Error {
    case invalidResponse
}
```

### Step 7: Update iOS ChatView

Modify `ChatView.swift` to use secure client:

```swiftok 
struct ChatView: View {
    let service: RemoteService
    @EnvironmentObject var serviceStore: ServiceStore
    @State private var secureClient: SecureAPIClient?
    ok
    // ... existing properties ...
    
    var body: some View {
        // ... existing UI ...
    }
    .onAppear {
        // Initialize secure client
        do {
            secureClient = try SecureAPIClient(
                serviceURL: service.url,
                encryptionKey: serviceStore.encryptionKey
            )
        } catch {
            print("Failed to initialize secure client: \(error)")
        }
    }
    
    func callLLM(message: String) async {
        guard let client = secureClient else { return }
        
        do {
            let response = try await client.sendChatMessage(
                messages: messages.map { msg in
                    ["role": msg.isUser ? "user" : "assistant", "content": msg.content]
                } + [["role": "user", "content": message]]
            )
            
            await MainActor.run {
                messages.append(ChatMessage(content: response, isUser: false))
            }
        } catch {
            await MainActor.run {
                messages.append(ChatMessage(
                    content: "Error: \(error.localizedDescription)",
                    isUser: false
                ))
            }
        }
    }
}
```

## Testing Steps

1. **Generate encryption key** - Mac app creates key on first launch
2. **Export config with key** - QR code includes encryption key
3. **iOS scans QR** - Saves both services and encryption key
4. **Test chat** - Messages should work through encrypted proxy
5. **Verify encryption** - Check Cloudflare logs show only base64 gibberish

## Notes for Coding Agent

- Use Apple's CryptoKit (requires iOS 13+, macOS 10.15+)
- The proxy server is minimal - just decrypt request, forward, encrypt response
- No authentication beyond encryption - attacker needs the key
- All services share the same encryption key for simplicity
- Key is included in QR code, so keep QR code private
- Error handling is basic - can be improved later

This provides solid E2E encryption with minimal complexity!

# CloudKit URL Rotation Implementation Plan

## Overview
Automatic tunnel URL rotation system using CloudKit public database as the coordination point between Mac and iPhone.

## Phase 1: CloudKit Setup

### 1.1 Configure CloudKit Container
```swift
// Both apps use same container ID
let containerID = "iCloud.com.yourcompany.llmtunnel"
```

**In Xcode:**
- Add CloudKit capability to both Mac and iOS targets
- Create new CloudKit container with above ID
- Enable "CloudKit Dashboard" for debugging

### 1.2 Define CloudKit Schema
**Record Type:** `TunnelEndpoint`

**Fields:**
- `url` (String) - Current tunnel URL
- `encryptionKey` (String) - Current session encryption key
- `lastUpdated` (Date) - Timestamp of last update
- `deviceName` (String) - Human-readable device identifier
- `status` (String) - "active", "reconnecting", "offline"
- `version` (Int) - Protocol version for future compatibility

## Phase 2: Mac Implementation

### 2.1 Device ID Management
```swift
class DeviceIdentityManager {
    static func getOrCreateDeviceID() -> String {
        let key = "com.yourapp.deviceID"
        if let existing = UserDefaults.standard.string(forKey: key) {
            return existing
        }
        let newID = "device-" + UUID().uuidString.lowercased()
        UserDefaults.standard.set(newID, forKey: key)
        return newID
    }
}
```

### 2.2 Tunnel Manager
```swift
class TunnelManager {
    private let publicDB = CKContainer(identifier: containerID).publicCloudDatabase
    private let deviceID = DeviceIdentityManager.getOrCreateDeviceID()
    private var currentProcess: Process?
    private var retryCount = 0
    
    func startTunnel() {
        updateCloudKit(status: "reconnecting")
        
        // Launch cloudflared
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/local/bin/cloudflared")
        process.arguments = ["tunnel", "--url", "http://localhost:8080"]
        
        // Capture output to get URL
        let pipe = Pipe()
        process.standardOutput = pipe
        
        process.terminationHandler = { [weak self] _ in
            self?.handleTunnelDeath()
        }
        
        process.launch()
        self.currentProcess = process
        
        // Parse URL from output
        parseURLFromOutput(pipe) { url in
            self.updateCloudKit(url: url, status: "active")
        }
    }
    
    private func handleTunnelDeath() {
        retryCount += 1
        let delay = min(pow(2.0, Double(retryCount)), 60) // Exponential backoff, max 60s
        
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            self.startTunnel()
        }
    }
    
    private func updateCloudKit(url: String? = nil, status: String) {
        let recordID = CKRecord.ID(recordName: deviceID)
        
        // Fetch existing record or create new
        publicDB.fetch(withRecordID: recordID) { record, error in
            let record = record ?? CKRecord(recordType: "TunnelEndpoint", recordID: recordID)
            
            if let url = url {
                record["url"] = url
                // Generate new session key for this tunnel
                record["encryptionKey"] = self.generateSessionKey()
            }
            record["status"] = status
            record["lastUpdated"] = Date()
            record["deviceName"] = Host.current().localizedName ?? "Mac"
            record["version"] = 1
            
            self.publicDB.save(record) { saved, error in
                if let error = error as? CKError,
                   error.code == .serverRecordChanged {
                    // Handle conflict - retry with server's version
                    self.retryWithServerRecord(error, url: url, status: status)
                }
            }
        }
    }
}
```

### 2.3 QR Code Generation
```swift
struct QRPayload: Codable {
    let deviceID: String
    let masterKey: String  // Used to derive session keys
    let timestamp: Date
    let version: Int
}

func generateQRCode() -> NSImage {
    let payload = QRPayload(
        deviceID: deviceID,
        masterKey: generateMasterKey(),
        timestamp: Date(),
        version: 1
    )
    
    let data = try! JSONEncoder().encode(payload)
    // Generate QR from data...
}
```

## Phase 3: iPhone Implementation

### 3.1 Connection Manager
```swift
class ConnectionManager {
    private var deviceID: String?
    private var masterKey: String?
    private var currentURL: String?
    private var pollTimer: Timer?
    private let publicDB = CKContainer(identifier: containerID).publicCloudDatabase
    
    func connectWithQRCode(_ qrData: Data) {
        let payload = try! JSONDecoder().decode(QRPayload.self, from: qrData)
        self.deviceID = payload.deviceID
        self.masterKey = payload.masterKey
        
        // Start polling immediately
        startPolling()
    }
    
    private func startPolling() {
        // Initial fetch
        fetchTunnelInfo()
        
        // Set up polling with smart intervals
        var pollInterval: TimeInterval = 5.0
        
        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { _ in
            self.fetchTunnelInfo()
            
            // Adjust polling rate based on status
            if self.connectionIsHealthy {
                pollInterval = min(pollInterval * 1.2, 30) // Slow down to max 30s
            } else {
                pollInterval = 5.0 // Speed up when reconnecting
            }
        }
    }
    
    private func fetchTunnelInfo() {
        guard let deviceID = deviceID else { return }
        
        let recordID = CKRecord.ID(recordName: deviceID)
        publicDB.fetch(withRecordID: recordID) { record, error in
            guard let record = record else {
                self.handleConnectionError(error)
                return
            }
            
            let newURL = record["url"] as? String
            let status = record["status"] as? String ?? "offline"
            let sessionKey = record["encryptionKey"] as? String
            
            if newURL != self.currentURL {
                self.handleURLChange(newURL, sessionKey: sessionKey)
            }
            
            self.updateUIStatus(status)
        }
    }
    
    private func handleURLChange(_ newURL: String?, sessionKey: String?) {
        currentURL = newURL
        
        guard let url = newURL, let key = sessionKey else {
            // Tunnel is down
            disconnect()
            return
        }
        
        // Derive actual encryption key from master + session
        let derivedKey = deriveKey(master: masterKey!, session: key)
        
        // Reconnect with new URL
        reconnectToTunnel(url: url, key: derivedKey)
    }
}
```

### 3.2 Connection Health Monitoring
```swift
extension ConnectionManager {
    func monitorConnection() {
        // Send periodic health checks
        Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { _ in
            self.sendHealthCheck { success in
                if !success {
                    // Force immediate CloudKit check
                    self.fetchTunnelInfo()
                }
            }
        }
    }
    
    private func sendHealthCheck(completion: @escaping (Bool) -> Void) {
        // Send encrypted ping to tunnel
        let ping = encrypt("ping", with: currentKey)
        
        URLSession.shared.dataTask(with: tunnelURL) { data, response, error in
            completion(error == nil)
        }.resume()
    }
}
```

## Phase 4: Error Handling & Edge Cases

### 4.1 Handle CloudKit Conflicts
```swift
private func retryWithServerRecord(_ error: CKError, url: String?, status: String) {
    guard let serverRecord = error.serverRecord else { return }
    
    // Merge our changes with server version
    if let url = url {
        serverRecord["url"] = url
        serverRecord["encryptionKey"] = generateSessionKey()
    }
    serverRecord["status"] = status
    serverRecord["lastUpdated"] = Date()
    
    publicDB.save(serverRecord) { _, error in
        if error != nil {
            // Retry with exponential backoff
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self.updateCloudKit(url: url, status: status)
            }
        }
    }
}
```

### 4.2 Cleanup Old Records
```swift
// Run periodically on Mac
func cleanupStaleRecords() {
    let oneDayAgo = Date().addingTimeInterval(-86400)
    let predicate = NSPredicate(format: "lastUpdated < %@ AND deviceID != %@", 
                                oneDayAgo as NSDate, deviceID)
    
    let query = CKQuery(recordType: "TunnelEndpoint", predicate: predicate)
    publicDB.perform(query, inZoneWith: nil) { records, error in
        records?.forEach { record in
            self.publicDB.delete(withRecordID: record.recordID) { _, _ in }
        }
    }
}
```

## Phase 5: Testing Strategy

### 5.1 Test Scenarios
1. **Happy path:** QR scan → connection → use LLM
2. **Tunnel death:** Kill cloudflared → verify auto-reconnect
3. **Network change:** Switch from WiFi to cellular
4. **Mac sleep/wake:** Verify reconnection after wake
5. **Simultaneous updates:** Both devices updating CloudKit
6. **Stale QR code:** Scan QR from previous session

### 5.2 Monitoring
```swift
// Add logging for debugging
enum TunnelEvent {
    case tunnelStarted(url: String)
    case tunnelDied(error: Error?)
    case cloudKitUpdated
    case cloudKitError(Error)
    case connectionEstablished
    case connectionLost
}

class TunnelLogger {
    static func log(_ event: TunnelEvent) {
        // Log to file for debugging
        // In production, could send to analytics
    }
}
```

## Phase 6: Production Considerations

### 6.1 CloudKit Quotas
- **Free tier:** 25 requests/second, 40 requests/second burst
- **Solution:** Implement adaptive polling rates
- **Monitor:** Dashboard for quota usage

### 6.2 Security Hardening
```swift
// Add request signing
struct SignedRequest {
    let payload: Data
    let timestamp: Date
    let nonce: String
    let signature: String  // HMAC of above fields
}

// Validate on proxy
func validateRequest(_ request: SignedRequest) -> Bool {
    // Check timestamp is recent (prevent replay)
    // Check nonce is unique
    // Verify signature
}
```

### 6.3 User Experience
- Show connection status in UI
- Clear error messages ("Mac offline", "Reconnecting...")  
- Manual refresh button as fallback
- Connection history/logs for debugging

This plan gives you automatic URL rotation with zero user intervention after the initial QR scan. The iPhone will automatically discover new tunnel URLs whenever the Mac restarts cloudflared or the tunnel dies.