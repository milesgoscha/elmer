//
//  ContentView.swift
//  elmer
//
//  Created by Miles Goscha on 8/6/25.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var serviceStore: ServiceStore
    @EnvironmentObject var conversationManager: ConversationManager
    
    var body: some View {
        // Modern Unified Control Panel Interface
        UnifiedControlPanelView()
            .ignoresSafeArea()
    }
}

#Preview {
    ContentView()
        .environmentObject(ServiceStore())
}
