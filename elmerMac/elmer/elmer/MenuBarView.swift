import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var serviceManager: ServiceManager
    
    private var runningServices: [AIService] {
        serviceManager.visibleServices.filter { $0.isRunning }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with relay status and toggle
            HStack {
                HStack(spacing: 8) {
                    Circle()
                        .fill(serviceManager.isRelayActive ? Color(nsColor: GeistTheme.success) : Color(nsColor: GeistTheme.border))
                        .frame(width: 4, height: 4)
                    
                    Text(serviceManager.isRelayActive ? "Relay active" : "Relay offline")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(Color(nsColor: GeistTheme.textPrimary))
                    
                    if serviceManager.isRelayActive && serviceManager.relayStatistics.totalRequests > 0 {
                        Text("(\(serviceManager.relayStatistics.totalRequests))")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(Color(nsColor: GeistTheme.textTertiary))
                    }
                }
                
                Spacer()
                
                // Relay toggle
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        if serviceManager.isRelayActive {
                            serviceManager.stopRelay()
                        } else {
                            serviceManager.startRelay()
                        }
                    }
                }) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(serviceManager.isRelayActive ? Color(nsColor: GeistTheme.accent) : Color(nsColor: GeistTheme.border))
                        .frame(width: 24, height: 14)
                        .overlay(
                            Circle()
                                .fill(serviceManager.isRelayActive ? Color(nsColor: GeistTheme.background) : Color(nsColor: GeistTheme.textSecondary))
                                .frame(width: 10, height: 10)
                                .offset(x: serviceManager.isRelayActive ? 5 : -5)
                                .animation(.easeInOut(duration: 0.15), value: serviceManager.isRelayActive)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            
            Divider()
                .background(Color(nsColor: GeistTheme.border))
            
            // Services
            VStack(alignment: .leading, spacing: 4) {
                if runningServices.isEmpty {
                    Text("No services running")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(Color(nsColor: GeistTheme.textTertiary))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                } else {
                    ForEach(runningServices) { service in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Color(nsColor: GeistTheme.success))
                                .frame(width: 4, height: 4)
                            
                            Text(service.displayName)
                                .font(.system(size: 11, weight: .regular))
                                .foregroundColor(Color(nsColor: GeistTheme.textPrimary))
                            
                            Spacer()
                            
                            Text("Port \(String(service.localPort))")
                                .font(.system(size: 10, weight: .regular))
                                .foregroundColor(Color(nsColor: GeistTheme.textTertiary))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                    }
                }
            }
            .padding(.vertical, 4)
            
            // Actions
            Divider()
                .background(Color(nsColor: GeistTheme.border))
            
            VStack(alignment: .leading, spacing: 0) {
                Button(action: {
                    // Find and click the Settings menu item from the main menu
                    if let mainMenu = NSApp.mainMenu {
                        for menuItem in mainMenu.items {
                            if let submenu = menuItem.submenu {
                                for subMenuItem in submenu.items {
                                    if subMenuItem.title.contains("Settings") || subMenuItem.title.contains("Preferences") {
                                        if let action = subMenuItem.action, let target = subMenuItem.target {
                                            _ = target.perform(action, with: subMenuItem)
                                        }
                                        return
                                    }
                                }
                            }
                        }
                    }
                }) {
                    HStack {
                        Text("Settings")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(Color(nsColor: GeistTheme.textSecondary))
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                
                Button(action: { NSApplication.shared.terminate(nil) }) {
                    HStack {
                        Text("Quit")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(Color(nsColor: GeistTheme.textSecondary))
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
        }
        .frame(width: 220)
        .background(Color(nsColor: GeistTheme.surface))
    }
}

#Preview {
    MenuBarView()
        .environmentObject(ServiceManager())
}