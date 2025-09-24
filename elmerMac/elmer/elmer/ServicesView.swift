//
//  ServicesView.swift
//  elmer
//
//  Main services view - extracted from ContentView
//

import SwiftUI

struct ServicesView: View {
    @EnvironmentObject var serviceManager: ServiceManager
    @Binding var currentView: ContentView.AppView
    @State private var showingExport = false
    @State private var isRefreshing = false
    
    private var runningServices: [AIService] {
        serviceManager.services.filter { $0.isRunning }
    }
    
    // Consolidated iPhone connection status
    private var iPhoneConnectionColor: Color {
        if !runningServices.isEmpty && serviceManager.isRelayActive {
            return Color(nsColor: GeistTheme.success)
        } else if !runningServices.isEmpty || serviceManager.isRelayActive {
            return Color.orange
        } else {
            return Color(nsColor: GeistTheme.border)
        }
    }
    
    private var iPhoneConnectionStatus: String {
        if !runningServices.isEmpty && serviceManager.isRelayActive {
            return "iPhone connection ready"
        } else if !runningServices.isEmpty && !serviceManager.isRelayActive {
            return "iPhone connection unavailable - relay offline"
        } else if runningServices.isEmpty && serviceManager.isRelayActive {
            return "iPhone connection unavailable - no services running"
        } else {
            return "iPhone connection unavailable"
        }
    }
    
    private var iPhoneConnectionHelperText: String {
        if !runningServices.isEmpty && serviceManager.isRelayActive {
            return "Services are being announced via iCloud. Use the Elmer iPhone app to connect."
        } else if !runningServices.isEmpty && !serviceManager.isRelayActive {
            return "Start the relay to announce services via iCloud."
        } else if runningServices.isEmpty && serviceManager.isRelayActive {
            return "Start Ollama, LM Studio, or ComfyUI to share services with your iPhone."
        } else {
            return "Start AI services and enable the relay to connect your iPhone."
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Padding from divider
                Spacer()
                    .frame(height: 20)
                VStack(alignment: .leading, spacing: 0) {
                    // iPhone Connection Section (consolidated)
                    VStack(alignment: .leading, spacing: 0) {
                        ThemedSectionHeader("iPhone Connection")
                        ThemedSectionDivider()
                        
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(iPhoneConnectionColor)
                                    .frame(width: 6, height: 6)
                                Text(iPhoneConnectionStatus)
                                    .font(.system(size: 13, weight: .regular))
                                    .foregroundColor(Color(nsColor: GeistTheme.textPrimary))
                            }
                            
                            if serviceManager.isRelayActive && serviceManager.relayStatistics.totalRequests > 0 {
                                Text("\(serviceManager.relayStatistics.totalRequests) requests • \(Int(serviceManager.relayStatistics.successRate * 100))% success")
                                    .font(.system(size: 11, weight: .regular))
                                    .foregroundColor(Color(nsColor: GeistTheme.textSecondary))
                            }
                            
                            ThemedHelperText(text: iPhoneConnectionHelperText)
                        }
                    }
                    .padding(.horizontal, 32)
                    .padding(.bottom, 32)
                    
                    // Services Section
                    VStack(alignment: .leading, spacing: 0) {
                        ThemedSectionHeader("AI Services", 
                            actionTitle: "Add Custom", 
                            action: {
                                currentView = .addCustomService
                            },
                            actionIcon: "plus",
                            secondaryActionTitle: isRefreshing ? "Refreshing..." : "Refresh",
                            secondaryAction: isRefreshing ? {} : {
                                refreshServices()
                            },
                            secondaryIcon: "arrow.clockwise",
                            tertiaryActionTitle: "Tools",
                            tertiaryAction: {
                                currentView = .tools
                            },
                            tertiaryIcon: "wrench.and.screwdriver"
                        )
                        ThemedSectionDivider()
                        
                        if !serviceManager.visibleServices.isEmpty {
                            VStack(spacing: 8) {
                                ForEach(serviceManager.visibleServices) { service in
                                    ThemedServiceCard(service: service)
                                }
                            }
                        } else {
                            ThemedEmptyState(
                                icon: "circle.dashed",
                                title: "No services running",
                                subtitle: "Start Ollama, LM Studio, or ComfyUI on this Mac"
                            )
                        }
                    }
                    .padding(.horizontal, 32)
                    .padding(.bottom, 32)
                    
                    // Hidden Services Section (if any)
                    if !serviceManager.hiddenServiceIds.isEmpty {
                        let hiddenServices = serviceManager.services.filter { serviceManager.isServiceHidden($0) }
                        if !hiddenServices.isEmpty {
                            VStack(alignment: .leading, spacing: 0) {
                                ThemedSectionHeader("Hidden Services")
                                ThemedSectionDivider()
                                
                                VStack(spacing: 8) {
                                    ForEach(hiddenServices) { service in
                                        HStack {
                                            Text(service.displayName)
                                                .font(.system(size: 13, weight: .regular))
                                                .foregroundColor(Color(nsColor: GeistTheme.textSecondary))
                                            
                                            Spacer()
                                            
                                            ThemedButton(
                                                title: "Show",
                                                action: { serviceManager.unhideService(service) },
                                                style: .secondary
                                            )
                                        }
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                        .background(Color(nsColor: GeistTheme.surface))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .stroke(Color(nsColor: GeistTheme.border), lineWidth: 1)
                                        )
                                        .cornerRadius(6)
                                    }
                                }
                            }
                            .padding(.horizontal, 32)
                            .padding(.bottom, 32)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingExport) {
            ExportView()
        }
    }
    
    private func refreshServices() {
        guard !isRefreshing else { return }
        
        isRefreshing = true
        Task {
            await serviceManager.performServiceDetection()
            await MainActor.run {
                isRefreshing = false
            }
        }
    }
}