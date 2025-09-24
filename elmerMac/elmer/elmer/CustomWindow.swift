//
//  CustomWindow.swift
//  elmer
//
//  Custom window configuration for unified title bar
//

import Cocoa

class CustomWindow: NSWindow {
    override func awakeFromNib() {
        super.awakeFromNib()
        configureWindow()
    }
    
    override func makeKeyAndOrderFront(_ sender: Any?) {
        configureWindow()
        super.makeKeyAndOrderFront(sender)
    }
    
    private func configureWindow() {
        self.titlebarAppearsTransparent = true
        self.titleVisibility = .hidden
        self.styleMask.insert(.fullSizeContentView)
        self.isMovableByWindowBackground = true
    }
}