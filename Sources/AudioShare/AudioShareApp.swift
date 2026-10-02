import AppKit
import SwiftUI

@main
struct AudioShareApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(controller: appDelegate.controller)
        } label: {
            Image(nsImage: MenuBarIcon.image(active: appDelegate.controller.isSharing))
                .accessibilityLabel("AudioShare")
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = AudioShareController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Never leave the system pointed at a device that no longer has an owner.
        controller.stopSharing()
    }
}

enum MenuBarIcon {
    static func image(active: Bool) -> NSImage {
        let name = active ? "MenuBarIconActiveTemplate" : "MenuBarIconTemplate"
        let fallback = active ? "headphones.circle.fill" : "headphones"
        let image = NSImage(named: name)
            ?? NSImage(systemSymbolName: fallback, accessibilityDescription: "AudioShare")
            ?? NSImage()
        image.isTemplate = true
        return image
    }
}
