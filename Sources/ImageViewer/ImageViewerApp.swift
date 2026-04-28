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
    @State private var window: NSWindow?

    var body: some View {
        RootView()
            .environmentObject(state)
            .focusedObject(state)       // exposes state to @FocusedObject in Commands
            .frame(minWidth: 900, minHeight: 600)
            .background(WindowAccessor(window: $window).ignoresSafeArea())
            .onChange(of: state.currentFolder)   { _, _ in updateTitle() }
            .onChange(of: state.imageURLs.count) { _, _ in updateTitle() }
            .onChange(of: state.totalFileSize)   { _, _ in updateTitle() }
            .onAppear {
                if let delegate = NSApp.delegate as? AppDelegate {
                    delegate.openNewWindowAction = { openWindow(id: "main") }
                }
            }
    }

    private func updateTitle() {
        guard let folder = state.currentFolder else {
            window?.title = "Image Viewer"
            return
        }
        let count = state.imageURLs.count
        let sizeStr = ByteCountFormatter.string(fromByteCount: state.totalFileSize, countStyle: .file)
        let itemStr = count == 1 ? "1 item" : "\(count) items"
        window?.title = "\(folder.lastPathComponent) — \(itemStr), \(sizeStr)"
    }
}

/// Captures the NSWindow reference for the current view so title updates work
/// even when the app is not the key window.
private struct WindowAccessor: NSViewRepresentable {
    @Binding var window: NSWindow?

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { self.window = view.window }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { self.window = nsView.window }
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
