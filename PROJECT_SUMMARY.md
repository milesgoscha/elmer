# Elmer Project - Simplified Architecture

## Overview
Elmer is a clean, minimalist system for connecting iOS devices to local AI services running on Mac. It uses iCloud's private database as a secure relay mechanism, requiring no external infrastructure or third-party services.

## Core Architecture

### Mac App (Server)
The Mac app serves as the local hub for AI services:
- **Auto-detects** running AI services (ComfyUI, Ollama, LM Studio, etc.)
- **Processes requests** from iOS devices via iCloud relay
- **Generates QR codes** for easy device pairing
- **Menu bar app** for minimal UI footprint

### iOS App (Client)
The iOS app provides mobile access to AI services:
- **Scans QR code** to connect to Mac
- **Sends requests** through iCloud private database
- **Receives responses** with push notifications
- **Service-specific UIs** for different AI tools

## Key Components

### Shared
- `CloudKitRelay.swift` - Core relay data models
- `Models.swift` - Service definitions
- `QRPayload` - Device connection info (deviceID + services)

### Mac-specific
- `CloudKitRelayManager.swift` - Handles incoming requests
- `ServiceManager.swift` - Manages local AI services
- `ServiceDetector.swift` - Auto-discovers services

### iOS-specific
- `CloudKitRelayClient.swift` - Sends requests to Mac
- `RelayConnectionManager.swift` - Manages Mac connection
- `ServiceStore.swift` - Tracks available services

## Communication Flow

1. **Setup**: Mac generates QR code with device ID
2. **Connect**: iOS scans QR to establish connection
3. **Request**: iOS sends request to CloudKit
4. **Process**: Mac receives notification, processes locally
5. **Response**: Mac uploads response to CloudKit
6. **Receive**: iOS gets response via push notification

## Benefits

- **Zero configuration** - Just scan and connect
- **No exposed ports** - Everything through iCloud
- **Automatic cleanup** - Old records deleted automatically
- **Secure by default** - Apple's iCloud encryption
- **No dependencies** - Pure SwiftUI/CloudKit

## Project Structure

```
elmer/
├── elmerMac/           # Mac menu bar app
│   └── elmer/
│       ├── CloudKitRelay.swift
│       ├── CloudKitRelayManager.swift
│       ├── ServiceManager.swift
│       ├── ServiceDetector.swift
│       └── UI components...
├── elmerMobile/        # iOS client app
│   └── elmer/
│       ├── CloudKitRelay.swift
│       ├── CloudKitRelayClient.swift
│       ├── RelayConnectionManager.swift
│       ├── ServiceStore.swift
│       └── UI views...
└── Documentation files
```

## Next Steps

With this clean foundation, you can now:
1. Add new AI service integrations
2. Enhance UI/UX for specific workflows
3. Implement advanced features (caching, offline support, etc.)
4. Add analytics and monitoring

The simplified architecture makes it easy to understand, modify, and extend.