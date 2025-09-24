# CloudKit Relay Implementation

## Overview
This implementation uses CloudKit as a secure relay mechanism between Mac and iOS apps for AI service communication. The Mac app acts as a server that processes requests from iOS clients through iCloud's private database.

## Key Benefits
- **Zero infrastructure required** - Uses iCloud private database
- **Instant updates** via CloudKit push notifications
- **Secure by default** - Apple's iCloud security and encryption
- **Simple setup** - Just scan QR code to connect devices
- **No external dependencies** - No tunnels or third-party services

## Architecture

### Communication Flow
1. iOS app sends request to CloudKit private database
2. Mac app receives push notification for new request
3. Mac app processes request locally with AI service
4. Mac app uploads response to CloudKit
5. iOS app receives push notification with response

### Core Components

#### Shared Models
- `AIRequest`: Request record for AI service calls
- `AIResponse`: Response record with results
- `QRPayload`: Device connection information
- `RequestStatus`: Track request lifecycle

#### Mac App (Server)
- **CloudKitRelayManager**: Listens for incoming requests
- **ServiceManager**: Manages local AI services
- **ServiceDetector**: Auto-detects running AI services

#### iOS App (Client)  
- **CloudKitRelayClient**: Sends requests and receives responses
- **RelayConnectionManager**: Manages connection to Mac
- **ServiceStore**: Tracks available services

## Setup

1. **Mac App**: Generates QR code with device ID
2. **iOS App**: Scans QR code to establish connection
3. **Both Apps**: Use same iCloud account for private database access

## Security

- All communication through iCloud private database
- Each user's data isolated in their iCloud account
- No exposed ports or public endpoints
- Automatic cleanup of old records

## Simplified Design

This implementation has been simplified from previous versions:
- Removed all external tunnel dependencies
- Single communication method (CloudKit only)
- Streamlined service detection and management
- Clean separation between Mac server and iOS client