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
        .onReceive(NotificationCenter.default.publisher(for: .openFolder)) { _ in
            Task { await openFolder() }
        }
        .task {
            await openFolder()
        }
    }

    func openFolder() async {
        guard let result = await FolderScanner.openPanelAndScan() else {
            // User cancelled — stay on whatever is currently showing
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first?.makeKeyAndOrderFront(nil)

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
