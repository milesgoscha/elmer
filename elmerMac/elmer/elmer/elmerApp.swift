//
//  elmerApp.swift
//  elmer
//
//  Created by Miles Goscha on 8/6/25.
//

import SwiftUI
import CloudKit

@main
struct elmerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var serviceManager = ServiceManager()
    @Environment(\.openWindow) private var openWindow
    
    private var menuBarIcon: String {
        let runningCount = serviceManager.services.filter { $0.isRunning }.count
        
        if runningCount > 0 && serviceManager.isRelayActive {
            return "brain.head.profile"  // Services running and relay active
        } else if runningCount > 0 {
            return "brain"  // Services running but relay offline
        }
        return "brain"  // Default
    }
    
    
    var body: some Scene {
        WindowGroup("Elmer Settings", id: "settings") {
            ContentView()
                .environmentObject(serviceManager)
                .frame(minWidth: 650, minHeight: 600)
                .onAppear {
                    // Wire up AppDelegate to ServiceManager for push notifications
                    appDelegate.setServiceManager(serviceManager)
                    
                    // Adjust traffic lights position after window appears
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        if let window = NSApp.keyWindow ?? NSApp.windows.first {
                            appDelegate.adjustTrafficLights(for: window)
                        }
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Elmer Settings...") {
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "settings")
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(replacing: .appInfo) {
                Button("About Elmer") {
                    // Handle about action
                }
            }
        }
        
        MenuBarExtra("Elmer", systemImage: menuBarIcon) {
            MenuBarView()
                .environmentObject(serviceManager)
        }
        .menuBarExtraStyle(.window)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var serviceManager: ServiceManager?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        print("🚀 Mac AppDelegate: Starting up...")
        
        // Listen for window becoming key to adjust traffic lights
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { notification in
            if let window = notification.object as? NSWindow {
                self.adjustTrafficLights(for: window)
            }
        }
        
        // Listen for window resize to maintain traffic light positions
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: nil,
            queue: .main
        ) { notification in
            if let window = notification.object as? NSWindow {
                self.adjustTrafficLights(for: window)
            }
        }
        
        // Make the app a proper menu bar utility
        NSApp.setActivationPolicy(.accessory)
        
        // Configure window for seamless title bar and disable resizing
        DispatchQueue.main.async {
            for window in NSApp.windows {
                // Configure for seamless title bar
                window.titlebarAppearsTransparent = true
                window.titleVisibility = .hidden
                window.styleMask.insert(.fullSizeContentView)
                
                // Disable window resizing
                window.styleMask.remove(.resizable)
                
                window.orderOut(nil)
            }
        }
        
        // Register for remote notifications to receive CloudKit push notifications
        print("🚀 Mac AppDelegate: Registering for remote notifications")
        NSApplication.shared.registerForRemoteNotifications()
    }
    
    func adjustTrafficLights(for window: NSWindow) {
        // Only adjust for our settings window
        guard window.title == "Elmer Settings" || window.identifier?.rawValue == "settings" else { return }
        
        // Configure window for seamless title bar
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)
        
        // Disable window resizing
        window.styleMask.remove(.resizable)
        
        // Simply hide the traffic lights - we'll create our own in SwiftUI
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        
        print("🔍 Hidden traffic lights and configured window")
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        print("🛑 App terminating - cleaning up...")
        // No cleanup needed for CloudKit relay
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // For menu bar apps, don't open anything when dock icon is clicked
        // Users should use the menu bar as primary interface
        return false
    }
    
    // MARK: - Remote Notifications (CloudKit)
    
    func application(_ application: NSApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        print("✅ Mac: Successfully registered for remote notifications")
        let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        print("📱 Device token: \(tokenString)")
    }
    
    func application(_ application: NSApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("❌ Mac: Failed to register for remote notifications: \(error.localizedDescription)")
    }
    
    func application(_ application: NSApplication, didReceiveRemoteNotification userInfo: [String : Any]) {
        print("📬 Mac AppDelegate: Received remote notification")
        print("📬 Notification payload: \(userInfo)")
        
        // Check if this is a CloudKit notification
        if let _ = userInfo["ck"] {
            print("📬 Mac AppDelegate: CloudKit notification detected, forwarding to ServiceManager")
            
            // Forward to service manager's relay manager
            serviceManager?.relayManager?.handleRemoteNotification(userInfo)
        } else {
            print("📬 Mac AppDelegate: Non-CloudKit notification received")
        }
    }
    
    // Set service manager reference
    func setServiceManager(_ manager: ServiceManager) {
        self.serviceManager = manager
        print("🔗 Mac AppDelegate: ServiceManager reference set")
    }
}
