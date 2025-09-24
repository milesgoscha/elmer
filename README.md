# Elmer

**Connect iOS devices to local AI services running on your Mac with zero configuration.**

Elmer is a minimalist system that bridges iOS and macOS, allowing your iPhone or iPad to securely access AI services running locally on your Mac. No exposed ports, no complex networking—just scan a QR code and start using your local AI infrastructure from anywhere.

## ✨ Key Features

- **🔐 Zero-config security** - Uses iCloud private database as encrypted relay
- **📱 Native iOS interface** - Chat with LLMs, generate images, run custom tools
- **🤖 Auto-discovery** - Detects ComfyUI, Ollama, LM Studio automatically
- **🛠️ Custom tools** - Define your own command-line tools and scripts
- **☁️ No external services** - Everything routes through your iCloud account
- **📡 MCP integration** - Connect to Model Context Protocol servers

## 🏗️ Architecture

```
┌─────────────────┐    ┌─────────────────────┐    ┌─────────────────┐
│                 │    │                     │    │                 │
│   iPhone/iPad   │◄──►│   iCloud Private    │◄──►│   Mac (Server)  │
│   (Client)      │    │   Database (Relay)  │    │                 │
│                 │    │                     │    │                 │
└─────────────────┘    └─────────────────────┘    └─────────────────┘
```

1. **Mac app** runs as menu bar service, detects local AI services
2. **QR code** contains connection info for easy device pairing
3. **iOS app** sends requests via CloudKit to Mac
4. **Mac processes** requests locally and returns responses
5. **Push notifications** deliver responses back to iOS instantly

## 🚀 Quick Start

### Prerequisites
- macOS device with AI services (Ollama, ComfyUI, LM Studio, etc.)
- iOS device signed into same iCloud account
- Xcode for building apps

### 1. Build & Run Mac App
```bash
cd elmerMac/elmer
xcodebuild -scheme elmer -configuration Release build
open build/Release/elmer.app
```

### 2. Build & Install iOS App
```bash
cd elmerMobile/elmer
xcodebuild -scheme elmer -sdk iphonesimulator build
# Or open in Xcode and run on device
```

### 3. Connect Devices
1. **Mac**: Click menu bar icon → "Generate QR Code"
2. **iOS**: Open Elmer app → Scan QR code
3. **Done!** Your devices are now connected

## 📱 iOS App Usage

### Chat with LLMs
- Tap any detected language model service
- Start chatting immediately with native iOS interface
- Supports text, images, and multimodal conversations

### Generate Images
- Access ComfyUI workflows through dedicated interface
- Generate and save images directly to Photos app

### Run Custom Tools
- Use predefined tools or create your own
- Execute terminal commands, scripts, and automations
- See `USER_TOOLS_GUIDE.md` for tool creation

## 🛠️ Custom Tools

Create your own tools by adding JSON files to `~/.elmer/tools/`:

```json
{
  "name": "System Info",
  "description": "Get macOS system information",
  "command": ["system_profiler", "SPSoftwareDataType"],
  "category": "system"
}
```

See `USER_TOOLS_GUIDE.md` for complete documentation.

## 🔧 Supported Services

**Auto-detected:**
- Ollama (http://localhost:11434)
- ComfyUI (http://localhost:8188)
- LM Studio (http://localhost:1234)
- Text Generation WebUI (http://localhost:7860)

**Manual configuration:**
- Any OpenAI-compatible API
- Custom web services
- MCP servers

## 📁 Project Structure

```
elmer/
├── elmerMac/           # macOS menu bar application
│   └── elmer/
│       ├── ServiceManager.swift      # AI service detection
│       ├── CloudKitRelayManager.swift # Request processing
│       ├── UserToolManager.swift     # Custom tools
│       └── MCPServerManager.swift    # MCP integration
├── elmerMobile/        # iOS client application
│   └── elmer/
│       ├── UnifiedControlPanelView.swift # Main interface
│       ├── CloudKitRelayClient.swift     # Request sending
│       └── RelayConnectionManager.swift  # Connection handling
├── example-tools/      # Sample tool definitions
└── docs/              # Documentation
```

## 🔒 Security & Privacy

- **End-to-end encryption** via iCloud's private database
- **No external servers** - all communication through Apple's infrastructure
- **Local processing** - AI requests never leave your devices
- **Automatic cleanup** - Old requests deleted automatically
- **iCloud sync** - Works across all your signed-in devices

## 🧰 Development

### Building from Source
Both apps are standard Xcode projects:
```bash
# Mac app
cd elmerMac/elmer && xcodebuild -scheme elmer build

# iOS app
cd elmerMobile/elmer && xcodebuild -scheme elmer -sdk iphonesimulator build
```

### Adding New Services
1. Add detection logic to `ServiceDetector.swift`
2. Update service definitions in `Models.swift`
3. Test auto-discovery in Mac app

### Contributing
1. Fork the repository
2. Create feature branch (`git checkout -b feature/amazing-feature`)
3. Test on both Mac and iOS
4. Submit pull request

## 📋 Requirements

**macOS:**
- macOS 13.0+ (Ventura)
- iCloud account
- Xcode 15.0+ (for building)

**iOS:**
- iOS 16.0+
- Same iCloud account as Mac
- Camera access (for QR scanning)

## 🐛 Troubleshooting

**Connection Issues:**
- Verify both devices use same iCloud account
- Check iCloud is enabled in System Preferences/Settings
- Restart both apps if QR scanning fails

**Service Detection:**
- Ensure AI services are running on default ports
- Check Console.app for service detection logs
- Manually add services if auto-detection fails

**Performance:**
- CloudKit sync may take 1-2 seconds in some regions
- Large responses (images) may take longer to transfer
- Check network connectivity if requests timeout

## 📚 Documentation

- [`USER_TOOLS_GUIDE.md`](USER_TOOLS_GUIDE.md) - Creating custom tools
- [`PROJECT_SUMMARY.md`](PROJECT_SUMMARY.md) - Architecture overview
- [`MIGRATION_NOTES.md`](MIGRATION_NOTES.md) - Version history
- [`CLOUDKIT_IMPLEMENTATION.md`](CLOUDKIT_IMPLEMENTATION.md) - Technical details

## 📄 License

MIT License - see LICENSE file for details.

## 🤝 Support

- **Issues**: [GitHub Issues](https://github.com/yourusername/elmer/issues)
- **Discussions**: [GitHub Discussions](https://github.com/yourusername/elmer/discussions)
- **Email**: your-email@example.com

---

**Elmer: Your AI services, everywhere.**