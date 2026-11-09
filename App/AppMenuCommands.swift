import AppKit
import SwiftUI

enum ProjectLinks {
    static let repository = URL(string: "https://github.com/alv67/time-machine-scheduler")!
}

struct AppMenuCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("menu.about") {
                AboutPanel.show()
            }
        }
        CommandGroup(replacing: .help) {
            Button("menu.help") {
                HelpWindowController.shared.show()
            }
            Button("menu.github") {
                NSWorkspace.shared.open(ProjectLinks.repository)
            }
        }
    }
}

enum AboutPanel {
    static func show() {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"

        let credits = NSMutableAttributedString(
            string: L("about.credits"),
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        )
        credits.append(NSAttributedString(
            string: "github.com/alv67/time-machine-scheduler",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .link: ProjectLinks.repository,
            ]
        ))

        NSApplication.shared.orderFrontStandardAboutPanel(options: [
            .applicationName: "Time Machine Scheduler",
            .applicationVersion: version,
            .version: L("about.build", build),
            .applicationIcon: AppIcon.image,
            .credits: credits,
        ])
    }
}

enum AppIcon {
    static var image: NSImage {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        return NSApp.applicationIconImage
    }
}
