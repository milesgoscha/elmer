import SwiftUI

struct ServiceListView: View {
    @EnvironmentObject var serviceStore: ServiceStore
    
    
    private var servicesContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            ThemedSectionHeader(title: "AI Services")
            
            if serviceStore.services.isEmpty {
                ThemedEmptyState(
                    icon: "brain.head.profile",
                    title: "No Services Connected",
                    subtitle: "Use 'Find My Macs' to automatically discover and connect to AI services on your Mac"
                )
                .padding(.horizontal, 20)
            } else {
                VStack(spacing: 8) {
                    ForEach(serviceStore.services) { service in
                        NavigationLink(destination: ServiceDetailView(service: service)) {
                            ThemedServiceCard(
                                service: service,
                                connectionStatus: serviceStore.getConnectionStatus(for: service)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .id(serviceStore.serviceUpdateTimestamp) // Force view refresh when services update
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
        }
    }
    
    var body: some View {
        ScrollView {
            servicesContent
        }
        .background(ElmeriOSTheme.groupedBackground)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(serviceStore.deviceName ?? "Elmer")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(ElmeriOSTheme.textColor)
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(action: { serviceStore.refreshConnection() }) {
                        Label("Refresh Status", systemImage: "arrow.clockwise")
                    }
                    
                    Button(action: { serviceStore.disconnect() }) {
                        Label("Disconnect from Mac", systemImage: "wifi.slash")
                    }
                    .foregroundColor(.red)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(ElmeriOSTheme.textSecondary)
                }
            }
        }
    }
}