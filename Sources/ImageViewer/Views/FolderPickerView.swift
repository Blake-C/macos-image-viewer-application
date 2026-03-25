import SwiftUI
import AppKit

struct FolderPickerView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 24) {
                Image(systemName: state.noImagesFound ? "photo.on.rectangle.angled" : "folder.badge.plus")
                    .font(.system(size: 72))
                    .foregroundStyle(.secondary)

                if state.noImagesFound {
                    Text("No images found in that folder")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("Supported formats: JPG, PNG, GIF, HEIC, TIFF, BMP, WebP")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Button {
                    state.requestOpenFolder()
                } label: {
                    Label("Open Folder…", systemImage: "folder")
                        .font(.title3)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
    }
}
