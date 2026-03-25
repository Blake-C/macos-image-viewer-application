import SwiftUI
import AppKit

struct ThumbnailCell: View {
    let url: URL
    let isSelected: Bool
    let squareThumbnails: Bool
    let onTap: () -> Void
    let onDelete: () -> Void

    @State private var thumbnail: NSImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white.opacity(0.06))

            if let img = thumbnail {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: squareThumbnails ? .fill : .fit)
            } else {
                ProgressView()
                    .scaleEffect(0.7)
            }
        }
        .frame(width: 160, height: 160)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
        )
        .shadow(color: isSelected ? Color.accentColor.opacity(0.4) : .clear, radius: 8)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .contextMenu {
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } label: {
                Label("Show in Finder", systemImage: "folder")
            }

            Divider()

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Move to Trash", systemImage: "trash")
            }
        }
        .id(url)
        .task(id: url) {
            thumbnail = await ImageLoader.thumbnail(for: url, size: 320)
        }
    }
}
