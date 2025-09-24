# Elmer Setup Guide

**Complete step-by-step guide to get Elmer running on your devices.**

## 📋 Prerequisites Checklist

Before starting, ensure you have:

- [ ] **Mac** running macOS 13.0+ (Ventura or later)
- [ ] **iOS device** running iOS 16.0+ (iPhone or iPad)
- [ ] **Same iCloud account** signed in on both devices
- [ ] **Xcode 15.0+** installed on Mac (for building apps)
- [ ] **AI services** running on Mac (Ollama, ComfyUI, etc.) - *optional but recommended*

## 🖥️ Step 1: Mac App Setup

### 1.1 Build the Mac App
```bash
# Navigate to Mac app directory
cd elmerMac/elmer

# Build the app
xcodebuild -scheme elmer -configuration Release build

# Launch the app
open build/Release/elmer.app
```

### 1.2 Grant Permissions
When you first launch, macOS will ask for permissions:
- [ ] **Menu Bar Access** - Allow Elmer to appear in menu bar
- [ ] **Network Access** - Allow communication with iCloud
- [ ] **CloudKit Access** - Enable if prompted

### 1.3 Verify Installation
1. Look for **Elmer icon** in your menu bar (📡)
2. Click icon → should see "Services", "Tools", "Export" menu
3. If you see "No services detected" - that's normal if no AI services are running

## 📱 Step 2: iOS App Setup

### 2.1 Build the iOS App

**Option A: Xcode (Recommended)**
```bash
cd elmerMobile/elmer
open elmer.xcodeproj
```
1. Select your iOS device as target
2. Click ▶️ to build and install
3. Trust the developer certificate in Settings → General → Device Management

**Option B: Command Line**
```bash
cd elmerMobile/elmer
xcodebuild -scheme elmer -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 15' build
```

### 2.2 Grant iOS Permissions
The app will request:
- [ ] **Camera access** - For QR code scanning
- [ ] **CloudKit access** - For device communication
- [ ] **Photo library access** - For saving generated images (if using ComfyUI)

## 🔗 Step 3: Connect Your Devices

### 3.1 Generate QR Code (Mac)
1. Click **Elmer menu bar icon**
2. Select **"Generate QR Code"**
3. QR code window will appear
4. Leave this window open

### 3.2 Scan QR Code (iOS)
1. Open **Elmer app** on iOS
2. Tap **"Scan QR Code"**
3. Point camera at QR code on Mac screen
4. App should automatically detect and connect

### 3.3 Verify Connection
✅ **Success indicators:**
- iOS app shows "Connected" status
- Mac menu shows "Connected devices: 1"
- iOS app displays available services (if any)

❌ **If connection fails:**
- Ensure both devices use same iCloud account
- Check iCloud is enabled in System Preferences (Mac) and Settings (iOS)
- Restart both apps and try again

## 🤖 Step 4: Set Up AI Services

### 4.1 Install AI Services (Mac)

**Ollama (Recommended)**
```bash
# Install Ollama
brew install ollama

# Start Ollama service
ollama serve

# Pull a model (in new terminal)
ollama pull llama3.1:8b
```

**ComfyUI**
```bash
# Clone ComfyUI
git clone https://github.com/comfyanonymous/ComfyUI.git
cd ComfyUI

# Install dependencies
pip install -r requirements.txt

# Start ComfyUI
python main.py
```

**LM Studio**
1. Download from [lmstudio.ai](https://lmstudio.ai)
2. Install and launch
3. Download a model
4. Start local server (default port 1234)

### 4.2 Verify Service Detection
1. With AI services running, click Elmer menu bar icon
2. Should see services listed under **"Services"**
3. Green dot = detected and available
4. Red dot = not responding

## 🛠️ Step 5: Add Custom Tools

### 5.1 Create Tools Directory
```bash
mkdir -p ~/.elmer/tools
```

### 5.2 Add Example Tools
```bash
# Copy provided examples
cp example-tools/*.json ~/.elmer/tools/

# Verify tools are loaded
# Check Mac menu bar → Tools menu
```

### 5.3 Create Your Own Tool
```bash
# Create a simple system info tool
cat > ~/.elmer/tools/system-info.json << 'EOF'
{
  "name": "System Info",
  "description": "Display macOS system information",
  "command": ["system_profiler", "SPSoftwareDataType", "-json"],
  "category": "system",
  "outputFormat": "json"
}
EOF
```

### 5.4 Test Tools
1. **Mac menu**: Click Elmer → Tools → "System Info"
2. **iOS app**: Tap any service → "Tools" tab → "System Info"

## 🧪 Step 6: Test Everything

### 6.1 Test LLM Chat
1. **iOS**: Open Elmer app
2. Tap an **LLM service** (Ollama, LM Studio)
3. Type a message: "Hello, can you help me?"
4. Should receive response within 5-10 seconds

### 6.2 Test Image Generation (if ComfyUI installed)
1. **iOS**: Tap **ComfyUI** service
2. Enter an image prompt
3. Tap generate
4. Should see progress and final image

### 6.3 Test Custom Tools
1. **iOS**: Tap any service → **"Tools"** tab
2. Select a tool from the list
3. Run it and verify output appears

## 🚨 Troubleshooting

### Connection Issues

**"iCloud account not available"**
```bash
# On Mac - check iCloud status
defaults read ~/Library/Preferences/MobileMeAccounts.plist Accounts

# On iOS - Settings → [Your Name] → iCloud → ensure enabled
```

**"QR code scanning not working"**
- Ensure camera permission granted
- Try holding phone steady for 2-3 seconds
- QR code must fill most of the screen
- Restart iOS app if scanner freezes

### Service Detection Issues

**"No services detected"**
```bash
# Check if services are actually running
curl http://localhost:11434/api/version  # Ollama
curl http://localhost:8188/system_stats  # ComfyUI
curl http://localhost:1234/v1/models     # LM Studio
```

**Services detected but not responding**
- Check firewall isn't blocking connections
- Verify services are listening on correct ports
- Restart AI services

### Performance Issues

**Slow responses**
- CloudKit relay adds ~1-2 second latency
- Large responses (images) take longer
- Check your internet connection
- Try smaller models for faster responses

**iOS app crashes**
```bash
# Check device logs
xcrun devicectl list devices
xcrun devicectl logs -v --verbose --show-process-names --quiet=false --device [DEVICE_ID]
```

### Tool Issues

**Tools not appearing**
```bash
# Verify tools directory
ls -la ~/.elmer/tools/

# Check JSON syntax
cat ~/.elmer/tools/your-tool.json | python -m json.tool

# Restart Mac app to reload tools
```

**Tools failing to execute**
- Check command exists: `which your-command`
- Verify permissions: `ls -la /path/to/command`
- Test manually in Terminal
- Check Mac app logs in Console.app

## 📊 Monitoring & Logs

### Mac App Logs
```bash
# View real-time logs
log stream --predicate 'processImagePath contains "elmer"' --level debug

# Or use Console.app:
# Applications → Utilities → Console
# Filter: "elmer"
```

### iOS App Logs
```bash
# Connect device and view logs
xcrun devicectl logs --device [DEVICE_ID] --follow
```

### CloudKit Dashboard
1. Visit [CloudKit Console](https://icloud.developer.apple.com/dashboard/)
2. Sign in with Apple ID
3. View database records and activity

## 🎯 Success Verification

✅ **Your setup is complete when:**

- [ ] Mac app runs in menu bar without errors
- [ ] iOS app successfully scans QR code
- [ ] iOS shows "Connected" status
- [ ] AI services appear in both apps
- [ ] Chat messages get responses
- [ ] Custom tools execute properly
- [ ] No error messages in logs

🎉 **You're ready for beta testing!**

## 📞 Getting Help

**If you're still having issues:**

1. **Check logs** using commands above
2. **Try minimal setup**: Just Ollama + basic chat
3. **Test step-by-step**: Don't skip verification steps
4. **Report issues**: Include logs and exact error messages

**Common "gotchas":**
- Different iCloud accounts on devices
- Firewall blocking local connections
- Old CloudKit data interfering
- Services running on non-standard ports
- iOS app not trusting developer certificate

---

*This guide covers 99% of setup scenarios. If you encounter something not covered here, it's likely a bug worth reporting.*