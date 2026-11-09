import AppKit
import SwiftUI

@MainActor
final class HelpWindowController {
    static let shared = HelpWindowController()

    private var window: NSWindow?

    func show() {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 620, height: 560),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = L("help.window.title")
            window.contentView = NSHostingView(rootView: HelpView())
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}
