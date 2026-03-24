import SwiftUI
import AppKit

extension Notification.Name {
    static let openFolder = Notification.Name("openFolder")
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct ImageViewerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .frame(minWidth: 900, minHeight: 600)
                .background(Color.black)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Folder…") {
                    NotificationCenter.default.post(name: .openFolder, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)
            }
            CommandMenu("View") {
                Button(appState.squareThumbnails ? "Aspect Ratio Thumbnails" : "Square Thumbnails") {
                    appState.squareThumbnails.toggle()
                }
                .keyboardShortcut("t", modifiers: .command)
            }
        }
    }
}
