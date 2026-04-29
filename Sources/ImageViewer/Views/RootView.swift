import SwiftUI
import AppKit

struct RootView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            GalleryView()
                .allowsHitTesting(state.viewMode == .gallery)
                .opacity(state.viewMode == .folderPicker ? 0 : 1)

            if state.viewMode == .fullImage {
                FullImageView()
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.15).combined(with: .opacity),
                            removal:   .scale(scale: 0.15).combined(with: .opacity)
                        )
                    )
                    .zIndex(1)
            }

            if state.viewMode == .folderPicker {
                FolderPickerView()
                    .transition(.opacity)
                    .zIndex(2)
            }
        }
        .onAppear {
            NSApp.activate(ignoringOtherApps: true)
        }
        // Watch per-window open-folder request (replaces notification)
        .onChange(of: state.openFolderRequested) { _, requested in
            guard requested else { return }
            state.openFolderRequested = false
            Task { await openFolder() }
        }
        .onChange(of: state.retryAuthRequested) { _, requested in
            guard requested else { return }
            state.retryAuthRequested = false
            if let folder = state.pendingAuthFolder {
                Task { await loadFolder(folder) }
            }
        }
        .task {
            if let lastFolder = state.lastFolderURL {
                await loadFolder(lastFolder)
            } else {
                await openFolder()
            }
        }
    }

    // MARK: - Folder helpers

    private func loadFolder(_ folder: URL) async {
        state.authFailed = false
        state.pendingAuthFolder = nil

        // Bring the app forward before prompting — biometric dialogs require the app to be frontmost.
        NSApp.activate(ignoringOtherApps: true)
        (NSApp.keyWindow ?? NSApp.windows.first)?.makeKeyAndOrderFront(nil)

        if FolderLockManager.shared.isLocked(folder) {
            let authorized = await FolderLockManager.shared.authenticate(
                for: folder,
                reason: "Authenticate to open \"\(folder.lastPathComponent)\""
            )
            guard authorized else {
                state.authFailed = true
                state.pendingAuthFolder = folder
                // viewMode may already be .folderPicker on launch — set directly to avoid
                // a redundant animation that can produce a blank frame.
                state.viewMode = .folderPicker
                return
            }
        }
        let urls = await FolderScanner.scan(directory: folder)
        state.zoomScale = 1.0
        state.panOffset = .zero
        state.noImagesFound = urls.isEmpty
        state.folderVersion += 1
        await state.loadImages(urls, from: folder)
        withAnimation {
            state.viewMode = urls.isEmpty ? .folderPicker : .gallery
        }
    }

    func openFolder() async {
        guard let result = await FolderScanner.openPanelAndScan() else {
            // User cancelled — stay on whatever is currently showing
            NSApp.activate(ignoringOtherApps: true)
            (NSApp.keyWindow ?? NSApp.windows.first)?.makeKeyAndOrderFront(nil)
            return
        }

        state.authFailed = false
        state.pendingAuthFolder = nil

        if FolderLockManager.shared.isLocked(result.folder) {
            let authorized = await FolderLockManager.shared.authenticate(
                for: result.folder,
                reason: "Authenticate to open \"\(result.folder.lastPathComponent)\""
            )
            guard authorized else {
                state.authFailed = true
                state.pendingAuthFolder = result.folder
                NSApp.activate(ignoringOtherApps: true)
                (NSApp.keyWindow ?? NSApp.windows.first)?.makeKeyAndOrderFront(nil)
                return
            }
        }

        NSApp.activate(ignoringOtherApps: true)
        (NSApp.keyWindow ?? NSApp.windows.first)?.makeKeyAndOrderFront(nil)

        state.zoomScale = 1.0
        state.panOffset = .zero
        state.noImagesFound = result.images.isEmpty
        state.folderVersion += 1
        await state.loadImages(result.images, from: result.folder)
        withAnimation {
            state.viewMode = result.images.isEmpty ? .folderPicker : .gallery
        }
    }
}
