//
//  ContentView.swift
//  elmer
//
//  Created by Miles Goscha on 8/6/25.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var serviceManager: ServiceManager
    @State private var showingExport = false
    @State private var currentView: AppView = .services
    
    enum AppView {
        case services
        case addCustomService
        case tools
    }
    
    var body: some View {
        ZStack {
            // Background that fills entire window
            Color(nsColor: GeistTheme.background)
                .ignoresSafeArea(.all)
            
            VStack(spacing: 0) {
                // Title bar + divider area (44px + 0.5px)
                Spacer()
                    .frame(height: 44.5)
                
                // Main content - ScrollViews start exactly at divider
                switch currentView {
                case .services:
                    ServicesView(currentView: $currentView)
                        .environmentObject(serviceManager)
                        
                case .addCustomService:
                    AddCustomServiceView(currentView: $currentView)
                        .environmentObject(serviceManager)
                        
                case .tools:
                    ToolsView(currentView: $currentView)
                }
            }
        }
        .sheet(isPresented: $showingExport) {
            ExportView()
        }
        .overlay(
            // Custom title bar content positioned exactly like the reference image
            HStack(alignment: .center) {
                // Custom traffic lights positioned exactly where we want them
                HStack(spacing: 8) {
                    // Close button
                    Button(action: {
                        NSApp.terminate(nil)
                    }) {
                        Circle()
                            .fill(Color(nsColor: GeistTheme.textTertiary))
                            .frame(width: 12, height: 12)
                    }
                    .buttonStyle(.plain)
                    
                    // Minimize button
                    Button(action: {
                        NSApp.keyWindow?.miniaturize(nil)
                    }) {
                        Circle()
                            .fill(Color(nsColor: GeistTheme.textTertiary))
                            .frame(width: 12, height: 12)
                    }
                    .buttonStyle(.plain)
                    
                    // Zoom button
                    Button(action: {
                        NSApp.keyWindow?.zoom(nil)
                    }) {
                        Circle()
                            .fill(Color(nsColor: GeistTheme.textTertiary))
                            .frame(width: 12, height: 12)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.leading, 20)
                
                // Title right after traffic lights when in specific views
                if currentView == .addCustomService {
                    Text("Add Custom Service")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(Color(nsColor: GeistTheme.textPrimary))
                        .padding(.leading, 20)
                } else if currentView == .tools {
                    Text("Tools")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(Color(nsColor: GeistTheme.textPrimary))
                        .padding(.leading, 20)
                }
                
                Spacer()
                
                // Close button on the right
                if currentView == .addCustomService || currentView == .tools {
                    Button(action: {
                        currentView = .services
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Color(nsColor: GeistTheme.textSecondary))
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 20)
                }
            }
            .frame(height: 44) // Increased title bar height for better proportions
            .background(Color(nsColor: GeistTheme.background))
            .overlay(
                // Thin divider to match reference image
                Rectangle()
                    .frame(height: 0.5)
                    .foregroundColor(Color(nsColor: GeistTheme.border).opacity(0.3)),
                alignment: .bottom
            ),
            alignment: .top
        )
        .ignoresSafeArea(.container, edges: .top)
    }
}

#Preview {
    ContentView()
        .environmentObject(ServiceManager())
}