import SwiftUI
import AppKit

extension Notification.Name {
    static let openFolder = Notification.Name("openFolder")
}

// MARK: - AppDelegate

class AppDelegate: NSObject, NSApplicationDelegate {
    // Closure set by each window so Cmd+N can open a new window
    var openNewWindowAction: (() -> Void)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func newWindow(_ sender: Any?) {
        openNewWindowAction?()
    }
}

// MARK: - Per-window wrapper

/// Owns an independent AppState for each window.
struct WindowContent: View {
    @StateObject private var state = AppState()
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        RootView()
            .environmentObject(state)
            .focusedObject(state)       // exposes state to @FocusedObject in Commands
            .frame(minWidth: 900, minHeight: 600)
            .background(Color.black)
            .onAppear {
                // Register this window's open-new-window capability with the delegate
                if let delegate = NSApp.delegate as? AppDelegate {
                    delegate.openNewWindowAction = { openWindow(id: "main") }
                }
            }
    }
}

// MARK: - Commands

struct AppCommands: Commands {
    @FocusedObject var state: AppState?

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Window") {
                NSApp.sendAction(#selector(AppDelegate.newWindow(_:)), to: nil, from: nil)
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("Open Folder…") {
                state?.requestOpenFolder()
            }
            .keyboardShortcut("o", modifiers: .command)
            .disabled(state == nil)
        }

        CommandMenu("View") {
            Button(state?.squareThumbnails == true ? "Aspect Ratio Thumbnails" : "Square Thumbnails") {
                state?.squareThumbnails.toggle()
            }
            .keyboardShortcut("t", modifiers: .command)
            .disabled(state == nil)

            Divider()

            Button("Enter Full Screen") {
                NSApp.keyWindow?.toggleFullScreen(nil)
            }
            .keyboardShortcut("f", modifiers: .command)

            Divider()

            Button("Refresh Folder") {
                Task { await state?.refreshCurrentFolder() }
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(state == nil)
        }
    }
}

// MARK: - App entry point

@main
struct ImageViewerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup(id: "main") {
            WindowContent()
        }
        .windowStyle(.titleBar)
        .commands {
            AppCommands()
        }
    }
}
