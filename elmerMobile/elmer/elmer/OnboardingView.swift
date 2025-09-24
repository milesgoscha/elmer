import SwiftUI

struct ActivityLogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let message: String
    let type: ActivityType
    
    enum ActivityType {
        case discovery, connection, service, relay
        
        var icon: String {
            switch self {
            case .discovery: return "magnifyingglass"
            case .connection: return "antenna.radiowaves.left.and.right"  
            case .service: return "cpu"
            case .relay: return "arrow.left.arrow.right"
            }
        }
        
        var color: Color {
            switch self {
            case .discovery: return ElmeriOSTheme.accentColor
            case .connection: return ElmeriOSTheme.successColor
            case .service: return Color.blue
            case .relay: return Color.orange
            }
        }
    }
}

struct OnboardingView: View {
    @EnvironmentObject var serviceStore: ServiceStore
    @State private var refreshTrigger = false
    @State private var activityLog: [ActivityLogEntry] = []
    @State private var lastDiscoveryTime: Date?
    
    // Computed properties that depend on refreshTrigger to force SwiftUI tracking
    private var availableMacs: [DeviceAnnouncement] {
        _ = refreshTrigger // Force dependency on refreshTrigger
        return serviceStore.relayManager.availableMacs
    }
    
    private var isDiscovering: Bool {
        _ = refreshTrigger // Force dependency on refreshTrigger
        return serviceStore.relayManager.isDiscovering
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Compact Header
                VStack(spacing: 16) {
                    Spacer()
                        .frame(height: 20)
                    
                    ThemedHelperText(
                        "Connect to AI services running on your Mac",
                        alignment: .center
                    )
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
                
                // Mac Discovery Section
                VStack(alignment: .leading, spacing: 0) {
                    ThemedSectionHeader(title: "Your Macs")
                    
                    let _ = print("📱 UI Logic - availableMacs.count: \(availableMacs.count), isDiscovering: \(isDiscovering)")
                    
                    if availableMacs.isEmpty {
                        if isDiscovering {
                            // Loading state
                            VStack(spacing: 16) {
                                HStack {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: ElmeriOSTheme.textSecondary))
                                        .scaleEffect(0.8)
                                    
                                    Text("Searching for Macs...")
                                        .font(.system(size: 14, weight: .regular))
                                        .foregroundColor(ElmeriOSTheme.textSecondary)
                                    
                                    Spacer()
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .background(ElmeriOSTheme.surfaceColor)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(ElmeriOSTheme.borderColor, lineWidth: 1)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .padding(.horizontal, 20)
                            .padding(.bottom, 24)
                        } else {
                            // Empty state with retry
                            VStack(spacing: 16) {
                                Text("No Macs Found")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(ElmeriOSTheme.textColor)
                                
                                ThemedHelperText("Make sure the Elmer Mac app is running and both devices use the same iCloud account.", alignment: .center)
                                
                                TactileButton(
                                    title: "SCAN",
                                    icon: "magnifyingglass",
                                    action: { serviceStore.relayManager.startDiscovery() }
                                )
                            }
                            .padding(.horizontal, 20)
                            .padding(.bottom, 24)
                        }
                    } else {
                        // Mac list
                        VStack(spacing: 8) {
                            ForEach(availableMacs, id: \.deviceID) { mac in
                                CompactMacRowView(mac: mac) {
                                    connectToMac(mac)
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)
                    }
                }
                
                // Live Activity Feed (Terminal Style)
                if !activityLog.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        ThemedSectionHeader(title: "System Monitor")
                        
                        TerminalDisplayView(activityLog: Array(activityLog.suffix(4)))
                            .padding(.horizontal, 20)
                            .padding(.bottom, 24)
                    }
                }
                
                // Service Status Cards  
                if !availableMacs.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        ThemedSectionHeader(title: "AI Services")
                        
                        if let connectedMac = availableMacs.first {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 12) {
                                ForEach(connectedMac.services, id: \.name) { service in
                                    ServiceStatusCard(service: service, isConnected: serviceStore.relayManager.isConnected)
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.bottom, 24)
                        }
                    }
                }
                
                // Quick Setup Tips
                VStack(alignment: .leading, spacing: 0) {
                    ThemedSectionHeader(title: "Quick Setup")
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Text("•")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(ElmeriOSTheme.accentColor)
                            
                            Text("Run Elmer on your Mac to announce AI services")
                                .font(.system(size: 14, weight: .regular))
                                .foregroundColor(ElmeriOSTheme.textColor)
                        }
                        
                        HStack(spacing: 8) {
                            Text("•")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(ElmeriOSTheme.accentColor)
                            
                            Text("Services are discovered automatically via iCloud")
                                .font(.system(size: 14, weight: .regular))
                                .foregroundColor(ElmeriOSTheme.textColor)
                        }
                        
                        HStack(spacing: 8) {
                            Text("•")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(ElmeriOSTheme.accentColor)
                            
                            Text("Tap any Mac above to connect and start using AI")
                                .font(.system(size: 14, weight: .regular))
                                .foregroundColor(ElmeriOSTheme.textColor)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }
                
                Spacer()
                    .frame(height: 20)
            }
        }
        .background(ElmeriOSTheme.groupedBackground)
        .onAppear {
            serviceStore.relayManager.startDiscovery()
        }
        .onReceive(serviceStore.relayManager.$availableMacs) { macs in
            print("📱 OnboardingView: availableMacs updated, count: \(macs.count)")
            
            if macs.count > availableMacs.count {
                // New Mac discovered
                if let newMac = macs.last {
                    addActivityLogEntry("Found \(newMac.deviceName)", type: .discovery)
                    addActivityLogEntry("\(newMac.services.count) services detected", type: .service)
                }
            }
            
            refreshTrigger.toggle()
        }
        .onReceive(serviceStore.relayManager.$isDiscovering) { discovering in
            print("📱 OnboardingView: isDiscovering updated to: \(discovering)")
            
            if discovering && !isDiscovering {
                // Discovery started
                addActivityLogEntry("Scanning iCloud for Macs...", type: .discovery)
            } else if !discovering && isDiscovering {
                // Discovery completed
                addActivityLogEntry("Discovery cycle complete", type: .discovery)
            }
            
            refreshTrigger.toggle()
        }
        .onReceive(serviceStore.relayManager.$relayStatistics) { stats in
            // Update when relay stats change
            if stats.totalRequests > 0 {
                addActivityLogEntry("Processed \(stats.totalRequests) requests", type: .relay)
            }
            refreshTrigger.toggle()
        }
    }
    
    private func connectToMac(_ mac: DeviceAnnouncement) {
        addActivityLogEntry("Connecting to \(mac.deviceName)", type: .connection)
        
        // Connect to the selected Mac
        serviceStore.relayManager.connectToMac(mac)
        
        // Load services from the announcement
        serviceStore.loadServicesFromAnnouncement(mac)
        
        addActivityLogEntry("Loading \(mac.services.count) AI services", type: .service)
        
        // Force a refresh after a short delay to get the latest service status
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            serviceStore.relayManager.refreshConnection()
            addActivityLogEntry("Connection established", type: .connection)
        }
    }
    
    private func addActivityLogEntry(_ message: String, type: ActivityLogEntry.ActivityType) {
        let entry = ActivityLogEntry(timestamp: Date(), message: message, type: type)
        activityLog.append(entry)
        
        // Keep only the last 8 entries
        if activityLog.count > 8 {
            activityLog.removeFirst()
        }
    }
}

// MARK: - Step View Component
struct StepView: View {
    let number: Int
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 12) {
            // Step Number
            Text("\(number)")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(ElmeriOSTheme.backgroundColor)
                .frame(width: 24, height: 24)
                .background(ElmeriOSTheme.accentColor)
                .clipShape(Circle())
            
            // Step Content
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(ElmeriOSTheme.textColor)
                
                ThemedHelperText(description)
            }
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(ElmeriOSTheme.cardColor)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(ElmeriOSTheme.borderColor, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Compact Mac Row Component (Server Rack Style)
struct CompactMacRowView: View {
    let mac: DeviceAnnouncement
    let onTap: () -> Void
    @State private var ledPulse = false
    
    private var timeSinceLastSeen: String {
        let interval = Date().timeIntervalSince(mac.lastSeen)
        if interval < 10 {
            return "ONLINE"
        } else if interval < 60 {
            return "\(Int(interval))s"
        } else {
            return "\(Int(interval / 60))m"
        }
    }
    
    private var isActive: Bool {
        Date().timeIntervalSince(mac.lastSeen) < 45
    }
    
    var body: some View {
        Button(action: onTap) {
            // Server Rack Unit
            VStack(spacing: 0) {
                // Top rack rail
                Rectangle()
                    .fill(LinearGradient(
                        colors: [Color.gray.opacity(0.3), Color.gray.opacity(0.6)],
                        startPoint: .top,
                        endPoint: .bottom
                    ))
                    .frame(height: 2)
                
                HStack(spacing: 0) {
                    // Left rack mounting holes
                    VStack(spacing: 6) {
                        ForEach(0..<3, id: \.self) { _ in
                            Circle()
                                .fill(Color.black.opacity(0.4))
                                .frame(width: 4, height: 4)
                        }
                    }
                    .padding(.leading, 6)
                    
                    // Main server unit content
                    HStack(spacing: 12) {
                        // LED Status Array
                        VStack(spacing: 2) {
                            HStack(spacing: 3) {
                                // Power LED
                                Circle()
                                    .fill(isActive ? Color.green : Color.gray.opacity(0.3))
                                    .frame(width: 6, height: 6)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.black.opacity(0.2), lineWidth: 0.5)
                                    )
                                    .scaleEffect(ledPulse && isActive ? 1.2 : 1.0)
                                    .opacity(ledPulse && isActive ? 0.8 : 1.0)
                                
                                // Network LED
                                Circle()
                                    .fill(isActive ? Color.blue : Color.gray.opacity(0.3))
                                    .frame(width: 6, height: 6)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.black.opacity(0.2), lineWidth: 0.5)
                                    )
                                
                                // Activity LED
                                Circle()
                                    .fill(mac.services.count > 0 ? Color.orange : Color.gray.opacity(0.3))
                                    .frame(width: 6, height: 6)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.black.opacity(0.2), lineWidth: 0.5)
                                    )
                            }
                            
                            // LED Labels
                            HStack(spacing: 1) {
                                Text("PWR")
                                    .font(.system(size: 6, weight: .medium, design: .monospaced))
                                    .foregroundColor(.black.opacity(0.6))
                                Text("NET")
                                    .font(.system(size: 6, weight: .medium, design: .monospaced))
                                    .foregroundColor(.black.opacity(0.6))
                                Text("ACT")
                                    .font(.system(size: 6, weight: .medium, design: .monospaced))
                                    .foregroundColor(.black.opacity(0.6))
                            }
                        }
                        .padding(.leading, 8)
                        
                        // Server Info Display
                        VStack(alignment: .leading, spacing: 1) {
                            // Device name with etched label style
                            Text(mac.deviceName.uppercased())
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(.black.opacity(0.8))
                            
                            HStack(spacing: 8) {
                                Text("\(mac.services.count) SVC")
                                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                                    .foregroundColor(.black.opacity(0.6))
                                
                                Text(timeSinceLastSeen)
                                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                                    .foregroundColor(isActive ? .green.opacity(0.8) : .red.opacity(0.6))
                            }
                        }
                        
                        Spacer()
                        
                        // Connection Port
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.black.opacity(0.6))
                            .frame(width: 12, height: 8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(isActive ? Color.green.opacity(0.3) : Color.clear)
                            )
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    
                    // Right rack mounting holes
                    VStack(spacing: 6) {
                        ForEach(0..<3, id: \.self) { _ in
                            Circle()
                                .fill(Color.black.opacity(0.4))
                                .frame(width: 4, height: 4)
                        }
                    }
                    .padding(.trailing, 6)
                }
                .background(
                    LinearGradient(
                        colors: [
                            Color.gray.opacity(0.1),
                            Color.gray.opacity(0.2),
                            Color.gray.opacity(0.15)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                
                // Bottom rack rail
                Rectangle()
                    .fill(LinearGradient(
                        colors: [Color.gray.opacity(0.6), Color.gray.opacity(0.3)],
                        startPoint: .top,
                        endPoint: .bottom
                    ))
                    .frame(height: 2)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(
                        LinearGradient(
                            colors: [Color.black.opacity(0.3), Color.clear, Color.black.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .shadow(color: .black.opacity(0.2), radius: 2, x: 1, y: 2)
        }
        .buttonStyle(PlainButtonStyle())
        .onAppear {
            if isActive {
                withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                    ledPulse = true
                }
            }
        }
        .onChange(of: isActive) { _, active in
            if active {
                withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                    ledPulse = true
                }
            } else {
                ledPulse = false
            }
        }
    }
}

// MARK: - Activity Feed Row Component
struct ActivityFeedRow: View {
    let entry: ActivityLogEntry
    @State private var isVisible = false
    
    private var timeAgo: String {
        let interval = Date().timeIntervalSince(entry.timestamp)
        if interval < 5 {
            return "now"
        } else if interval < 60 {
            return "\(Int(interval))s ago"
        } else {
            return "\(Int(interval / 60))m ago"
        }
    }
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: entry.type.icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(entry.type.color)
                .frame(width: 16)
            
            Text(entry.message)
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(ElmeriOSTheme.textColor)
            
            Spacer()
            
            Text(timeAgo)
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(ElmeriOSTheme.textTertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(ElmeriOSTheme.surfaceColor.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .scaleEffect(isVisible ? 1.0 : 0.8)
        .opacity(isVisible ? 1.0 : 0.0)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isVisible)
        .onAppear {
            isVisible = true
        }
    }
}

// MARK: - Terminal Display Component
struct TerminalDisplayView: View {
    let activityLog: [ActivityLogEntry]
    @State private var scanLineOffset: CGFloat = 0
    @State private var cursorBlink = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Terminal Header
            HStack {
                // Power LED
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)
                    .shadow(color: .green, radius: 2)
                
                Text("ELMER SYS MONITOR v2.1")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.green.opacity(0.8))
                
                Spacer()
                
                Text("READY")
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundColor(.green.opacity(0.6))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.black)
            
            // Terminal Screen
            VStack(alignment: .leading, spacing: 2) {
                ForEach(activityLog) { entry in
                    TerminalLogRow(entry: entry)
                }
                
                // Cursor Line
                HStack(spacing: 0) {
                    Text("> ")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.green.opacity(0.8))
                    
                    Rectangle()
                        .fill(.green.opacity(cursorBlink ? 0.8 : 0.2))
                        .frame(width: 8, height: 12)
                    
                    Spacer()
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.black)
            .overlay(
                // Scan lines effect
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                .clear,
                                .green.opacity(0.05),
                                .clear,
                                .green.opacity(0.03),
                                .clear
                            ],
                            startPoint: .init(x: 0, y: scanLineOffset),
                            endPoint: .init(x: 0, y: scanLineOffset + 0.1)
                        )
                    )
                    .allowsHitTesting(false)
            )
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.6), lineWidth: 2)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .green.opacity(0.2), radius: 4)
        .onAppear {
            withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) {
                scanLineOffset = 1.1
            }
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                cursorBlink = true
            }
        }
    }
}

// MARK: - Terminal Log Row Component
struct TerminalLogRow: View {
    let entry: ActivityLogEntry
    @State private var isVisible = false
    
    private var timeStamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: entry.timestamp)
    }
    
    private var logPrefix: String {
        switch entry.type {
        case .discovery: return "[SCAN]"
        case .connection: return "[CONN]"
        case .service: return "[SVC ]"
        case .relay: return "[RLAY]"
        }
    }
    
    var body: some View {
        HStack(spacing: 4) {
            Text(timeStamp)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(.green.opacity(0.6))
                .frame(width: 50, alignment: .leading)
            
            Text(logPrefix)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(entry.type.color.opacity(0.8))
                .frame(width: 35, alignment: .leading)
            
            Text(entry.message.uppercased())
                .font(.system(size: 9, weight: .regular, design: .monospaced))
                .foregroundColor(.green.opacity(0.8))
            
            Spacer()
        }
        .opacity(isVisible ? 1.0 : 0.0)
        .scaleEffect(x: isVisible ? 1.0 : 0.8, y: 1.0)
        .animation(.easeOut(duration: 0.3), value: isVisible)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isVisible = true
            }
        }
    }
}

// MARK: - Service Status Card Component (Circuit Board Style)
struct ServiceStatusCard: View {
    let service: QRServiceInfo
    let isConnected: Bool
    @State private var isPulsing = false
    @State private var ledGlow = false
    
    var body: some View {
        // Circuit Board PCB
        VStack(spacing: 0) {
            // PCB Header with component labels
            HStack {
                Text(service.name.uppercased())
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.9))
                
                Spacer()
                
                Text("REV 2.1")
                    .font(.system(size: 6, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.black.opacity(0.8))
            
            // Main PCB Area
            HStack(spacing: 8) {
                // Service IC Chip
                VStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.black.opacity(0.9))
                        .frame(width: 24, height: 16)
                        .overlay(
                            VStack(spacing: 1) {
                                // IC pins
                                ForEach(0..<3, id: \.self) { _ in
                                    HStack(spacing: 2) {
                                        Rectangle().fill(Color.gray.opacity(0.8)).frame(width: 1, height: 1)
                                        Spacer()
                                        Rectangle().fill(Color.gray.opacity(0.8)).frame(width: 1, height: 1)
                                    }
                                }
                            }
                            .padding(.horizontal, 2)
                        )
                    
                    Text(serviceChipLabel)
                        .font(.system(size: 5, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.7))
                }
                
                // Circuit Traces
                VStack(spacing: 1) {
                    Rectangle()
                        .fill(LinearGradient(
                            colors: [Color.clear, statusColor.opacity(0.6), Color.clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        ))
                        .frame(height: 1)
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 0.5)
                    Rectangle()
                        .fill(LinearGradient(
                            colors: [Color.clear, statusColor.opacity(0.4), Color.clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        ))
                        .frame(height: 1)
                }
                .frame(width: 20)
                
                // LED Array
                VStack(spacing: 3) {
                    HStack(spacing: 3) {
                        // Power LED
                        Circle()
                            .fill(isConnected ? Color.green : Color.gray.opacity(0.4))
                            .frame(width: 4, height: 4)
                            .overlay(
                                Circle()
                                    .stroke(Color.black.opacity(0.3), lineWidth: 0.5)
                            )
                            .shadow(color: isConnected ? .green : .clear, radius: ledGlow ? 3 : 1)
                            .scaleEffect(ledGlow && isConnected ? 1.2 : 1.0)
                        
                        // Status LED
                        Circle()
                            .fill(service.isRunning ? Color.blue : Color.gray.opacity(0.4))
                            .frame(width: 4, height: 4)
                            .overlay(
                                Circle()
                                    .stroke(Color.black.opacity(0.3), lineWidth: 0.5)
                            )
                            .shadow(color: service.isRunning ? .blue : .clear, radius: ledGlow ? 2 : 1)
                    }
                    
                    HStack(spacing: 3) {
                        // Activity LED
                        Circle()
                            .fill(isPulsing ? Color.orange : Color.gray.opacity(0.4))
                            .frame(width: 4, height: 4)
                            .overlay(
                                Circle()
                                    .stroke(Color.black.opacity(0.3), lineWidth: 0.5)
                            )
                            .shadow(color: isPulsing ? .orange : .clear, radius: ledGlow ? 2 : 1)
                        
                        // Error LED
                        Circle()
                            .fill(!isConnected && service.isRunning ? Color.red : Color.gray.opacity(0.4))
                            .frame(width: 4, height: 4)
                            .overlay(
                                Circle()
                                    .stroke(Color.black.opacity(0.3), lineWidth: 0.5)
                            )
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.0, green: 0.3, blue: 0.2).opacity(0.8),
                        Color(red: 0.0, green: 0.4, blue: 0.3).opacity(0.6),
                        Color(red: 0.0, green: 0.3, blue: 0.2).opacity(0.8)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            
            // Status Display
            HStack {
                Text(statusText)
                    .font(.system(size: 7, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.9))
                
                Spacer()
                
                Text(service.port > 0 ? ":\(service.port)" : "N/A")
                    .font(.system(size: 6, weight: .regular, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.black.opacity(0.6))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.gray.opacity(0.4), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .shadow(color: statusColor.opacity(0.3), radius: 3, x: 1, y: 2)
        .onAppear {
            if isConnected {
                isPulsing = true
                withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                    ledGlow = true
                }
            }
        }
        .onChange(of: isConnected) { _, connected in
            isPulsing = connected
            if connected {
                withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                    ledGlow = true
                }
            } else {
                ledGlow = false
            }
        }
    }
    
    private var serviceChipLabel: String {
        switch service.name.lowercased() {
        case "ollama": return "LLM01"
        case "comfyui": return "IMG01"
        case "openai": return "GPT01"
        default: return "AI01"
        }
    }
    
    private var statusText: String {
        if isConnected && service.isRunning {
            return "ACTIVE"
        } else if service.isRunning {
            return "STANDBY"
        } else {
            return "OFFLINE"
        }
    }
    
    private var statusColor: Color {
        if isConnected && service.isRunning {
            return Color.green
        } else if service.isRunning {
            return Color.blue
        } else {
            return Color.gray
        }
    }
}

// MARK: - Tactile Button Component
struct TactileButton: View {
    let title: String
    let icon: String
    let action: () -> Void
    @State private var isPressed = false
    
    var body: some View {
        Button(action: {
            // Haptic feedback
            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
            impactFeedback.impactOccurred()
            action()
        }) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                
                Text(title)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(
                ZStack {
                    // Button body with realistic shading
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            LinearGradient(
                                colors: isPressed ? [
                                    Color(red: 0.15, green: 0.15, blue: 0.15),
                                    Color(red: 0.25, green: 0.25, blue: 0.25)
                                ] : [
                                    Color(red: 0.35, green: 0.35, blue: 0.35),
                                    Color(red: 0.2, green: 0.2, blue: 0.2)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    // Top highlight
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(isPressed ? 0.1 : 0.3),
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: .center
                            ),
                            lineWidth: 1
                        )
                    
                    // Bottom shadow
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.clear,
                                    Color.black.opacity(isPressed ? 0.6 : 0.4)
                                ],
                                startPoint: .center,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                }
            )
            .scaleEffect(isPressed ? 0.95 : 1.0)
            .shadow(
                color: .black.opacity(isPressed ? 0.2 : 0.4),
                radius: isPressed ? 2 : 4,
                x: 0,
                y: isPressed ? 1 : 2
            )
        }
        .buttonStyle(PlainButtonStyle())
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity) { pressing in
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = pressing
            }
        } perform: {
            // Action already handled in button closure
        }
    }
}