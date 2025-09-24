//
//  elmerApp.swift
//  elmer
//
//  Created by Miles Goscha on 8/6/25.
//

import SwiftUI

@main
struct elmerApp: App {
    
    init() {
        // Lock orientation to portrait on iPhone
        if UIDevice.current.userInterfaceIdiom == .phone {
            UIDevice.current.setValue(UIInterfaceOrientation.portrait.rawValue, forKey: "orientation")
        }
    }
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var serviceStore = ServiceStore()
    @StateObject private var conversationManager = ConversationManager()
    @StateObject private var cloudKitConversationManager = CloudKitConversationManager()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(serviceStore)
                .environmentObject(conversationManager)
                .environmentObject(cloudKitConversationManager)
                .onReceive(NotificationCenter.default.publisher(for: Notification.Name("CloudKitRemoteNotification"))) { notification in
                    // Pass CloudKit notifications to RelayConnectionManager
                    if let userInfo = notification.userInfo {
                        serviceStore.handleRemoteNotification(userInfo)
                    }
                }
        }
    }
}
