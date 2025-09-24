//
//  UnifiedControlPanelView.swift
//  elmer
//
//  Mobile control panel matching Mac UI style with Geist design
//

import SwiftUI
import UIKit

// MARK: - Main Unified Control Panel
struct UnifiedControlPanelView: View {
    @EnvironmentObject var serviceStore: ServiceStore
    @State private var selectedService: String?
    @State private var showingMacSelector = false
    
    
    var body: some View {
        NavigationView {
            ZStack {
                // Dark background matching Mac
                Color(red: 0.08, green: 0.08, blue: 0.08)
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 0) {
                        VStack(alignment: .leading, spacing: 0) {
                            // Services Section
                            VStack(alignment: .leading, spacing: 0) {
                                ThemedSectionHeaderNew("AI Services")
                                ThemedSectionDividerNew()
                                
                                if !serviceStore.services.isEmpty {
                                    VStack(spacing: 8) {
                                        ForEach(serviceStore.services) { service in
                                            ThemedServiceCardNew(service: service)
                                        }
                                    }
                                } else if serviceStore.relayManager.isConnected {
                                    ThemedEmptyStateNew(
                                        icon: "circle.dashed",
                                        title: "No services available",
                                        subtitle: "Start Ollama, LM Studio, or ComfyUI on your Mac"
                                    )
                                } else {
                                    ThemedEmptyStateNew(
                                        icon: "wifi.slash",
                                        title: "Not connected",
                                        subtitle: "Tap below to discover and connect to your Mac"
                                    )
                                }
                            }
                            .padding(.horizontal, 32)
                            .padding(.bottom, 32)
                            
                            // Discovery Button if not connected
                            if !serviceStore.relayManager.isConnected {
                                VStack(spacing: 0) {
                                    ThemedDiscoveryButton()
                                        .environmentObject(serviceStore)
                                }
                                .padding(.horizontal, 32)
                                .padding(.bottom, 32)
                            }
                        }
                    }
                    .padding(.top, 20)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    MacConnectionNavTitle()
                        .environmentObject(serviceStore)
                        .onTapGesture {
                            if serviceStore.relayManager.availableMacs.count > 1 {
                                showingMacSelector = true
                            }
                        }
                }
            }
            .sheet(isPresented: $showingMacSelector) {
                MacSelectorSheet()
                    .environmentObject(serviceStore)
            }
        }
        .onAppear {
            if !serviceStore.relayManager.isConnected {
                serviceStore.relayManager.startDiscovery()
            }
        }
    }
}

// MARK: - Themed Components Matching Mac Style

// MARK: - Themed Section Header (New)
struct ThemedSectionHeaderNew: View {
    let title: String
    
    init(_ title: String) {
        self.title = title
    }
    
    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.5))
            .tracking(0.5)
            .padding(.bottom, 16)
    }
}

// MARK: - Themed Section Divider (New)
struct ThemedSectionDividerNew: View {
    var body: some View {
        Spacer()
            .frame(height: 0)
    }
}

// MARK: - Themed Helper Text (New)
struct ThemedHelperTextNew: View {
    let text: String
    
    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .regular))
            .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.5))
            .lineSpacing(2)
    }
}

// MARK: - Themed Service Card (New)
struct ThemedServiceCardNew: View {
    let service: RemoteService
    @EnvironmentObject var serviceStore: ServiceStore
    
    var body: some View {
        NavigationLink(destination: ChatView(service: service)) {
            HStack(spacing: 12) {
                // Service Info
                VStack(alignment: .leading, spacing: 2) {
                    Text(service.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                    
                    Text("Port \(String(service.baseService.localPort))")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(Color(red: 0.7, green: 0.7, blue: 0.7))
                }
                
                Spacer()
                
                // Navigation chevron
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.5))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .buttonStyle(PlainButtonStyle())
        .background(Color(red: 0.12, green: 0.12, blue: 0.12))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(red: 0.2, green: 0.2, blue: 0.2), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}


// MARK: - Themed Empty State (New)
struct ThemedEmptyStateNew: View {
    let icon: String
    let title: String
    let subtitle: String
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .light))
                .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.5))
            
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
            
            Text(subtitle)
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(Color(red: 0.7, green: 0.7, blue: 0.7))
                .multilineTextAlignment(.center)
                .lineSpacing(2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }
}

// MARK: - Themed Discovery Button
struct ThemedDiscoveryButton: View {
    @EnvironmentObject var serviceStore: ServiceStore
    
    var body: some View {
        Button(action: {
            serviceStore.relayManager.startDiscovery()
        }) {
            HStack(spacing: 8) {
                Image(systemName: serviceStore.relayManager.isDiscovering ? "stop.circle" : "magnifyingglass")
                    .font(.system(size: 13, weight: .medium))
                Text(serviceStore.relayManager.isDiscovering ? "Stop Discovery" : "Find My Mac")
                    .font(.system(size: 13, weight: .regular))
            }
            .foregroundColor(Color(red: 0.08, green: 0.08, blue: 0.08))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Mac Connection Nav Title
struct MacConnectionNavTitle: View {
    @EnvironmentObject var serviceStore: ServiceStore
    
    var body: some View {
        HStack(spacing: 4) {
            // Status indicator
            Circle()
                .fill(serviceStore.relayManager.isConnected ? Color(red: 0.2, green: 0.8, blue: 0.2) : Color(red: 0.2, green: 0.2, blue: 0.2))
                .frame(width: 6, height: 6)
            
            // Title text
            Text(navTitle)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(1)
            
            // Dropdown chevron if multiple Macs available
            if serviceStore.relayManager.availableMacs.count > 1 {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Color(red: 0.7, green: 0.7, blue: 0.7))
            }
        }
    }
    
    private var navTitle: String {
        if serviceStore.relayManager.isConnected {
            if let mac = serviceStore.relayManager.availableMacs.first(where: { $0.deviceID == serviceStore.relayManager.targetDeviceID }) {
                return mac.deviceName
            } else if let deviceName = serviceStore.relayManager.targetDeviceName {
                return deviceName
            }
            return "Connected Mac"
        } else if serviceStore.relayManager.isDiscovering {
            return "Discovering..."
        } else {
            return "Not Connected"
        }
    }
}

// MARK: - Mac Selector Sheet
struct MacSelectorSheet: View {
    @EnvironmentObject var serviceStore: ServiceStore
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(serviceStore.relayManager.availableMacs, id: \.deviceID) { mac in
                    Button(action: {
                        serviceStore.relayManager.connectToMac(mac)
                        dismiss()
                    }) {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(Color(red: 0.2, green: 0.8, blue: 0.2))
                                .frame(width: 8, height: 8)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(mac.deviceName)
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.white)
                                
                                Text("\(mac.services.count) services available")
                                    .font(.system(size: 13, weight: .regular))
                                    .foregroundColor(Color(red: 0.7, green: 0.7, blue: 0.7))
                            }
                            
                            Spacer()
                            
                            if mac.deviceID == serviceStore.relayManager.targetDeviceID {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(Color(red: 0.2, green: 0.8, blue: 0.2))
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                Spacer()
            }
            .padding(.top, 20)
            .background(Color(red: 0.08, green: 0.08, blue: 0.08))
            .navigationTitle("Select Mac")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
        }
    }
}


