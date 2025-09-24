# Elmer Mac App Setup

## Next Steps in Xcode

### 1. Add Cloudflared Binaries to Project
1. In Xcode, right-click on the project navigator
2. Select "Add Files to elmer..."
3. Navigate to the Resources folder and select both:
   - cloudflared-arm
   - cloudflared-intel
4. Make sure "Copy items if needed" is checked
5. Add to target: elmer

### 2. Configure Build Phases
1. Select the elmer project in navigator
2. Select the elmer target
3. Go to Build Phases tab
4. Expand "Copy Bundle Resources"
5. Make sure both cloudflared binaries are listed there
6. If not, click + and add them

### 3. Build and Test
1. Build the project (Cmd+B)
2. Run the app
3. The app should show in the menu bar with a brain icon
4. Main window should display default AI services
5. Services will show as "running" if they're detected on localhost

## Features Implemented
- Service monitoring (checks if services are running on localhost)
- Cloudflare tunnel creation
- QR code export for iOS app configuration
- Menu bar app with main window
- Add custom services
- Copy tunnel URLs to clipboard

## Testing Checklist
- [ ] Launch the app
- [ ] Check if services are detected (green icon = running)
- [ ] Click "Enable Remote Access" on a running service
- [ ] Verify tunnel URL appears
- [ ] Click "Export Config" to generate QR code
- [ ] Test "Add Service" to add custom service

## Known Requirements
- macOS 12.0 or later
- Services must be running on localhost for tunnel creation
- Internet connection required for Cloudflare tunnels