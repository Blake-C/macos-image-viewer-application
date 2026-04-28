import SwiftUI
import AppKit

struct ThumbnailCell: View {
    let url: URL
    let isSelected: Bool
    let isMultiSelected: Bool
    let isFavorite: Bool
    let squareThumbnails: Bool
    var masonry: Bool = false
    var cellWidth: CGFloat = 160  // controls both grid cell size and masonry column width
    let onTap: () -> Void
    let onDelete: () -> Void
    let onToggleFavorite: () -> Void

    @State private var thumbnail: NSImage?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white.opacity(0.06))

                if let img = thumbnail {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: masonry ? .fit : (squareThumbnails ? .fill : .fit))
                } else {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(height: masonry ? 180 : nil)
                }
            }
            .frame(width: cellWidth, height: masonry ? nil : cellWidth)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(borderColor, lineWidth: 3)
            )
            .shadow(color: shadowColor, radius: 8)

            // Favorites star badge
            if isFavorite {
                Image(systemName: "star.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.yellow)
                    .shadow(color: .black.opacity(0.6), radius: 2)
                    .padding(6)
            }

            // Multi-select checkmark badge
            if isMultiSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.white, Color.accentColor)
                    .padding(4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
        }
        .frame(width: cellWidth, height: masonry ? nil : cellWidth)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .contextMenu {
            Button {
                NSWorkspace.shared.open(url)
            } label: {
                Label("Open", systemImage: "arrow.up.right.square")
            }

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } label: {
                Label("Show in Finder", systemImage: "folder")
            }

            Divider()

            Button {
                onToggleFavorite()
            } label: {
                Label(isFavorite ? "Remove from Favorites" : "Add to Favorites",
                      systemImage: isFavorite ? "star.slash" : "star")
            }

            Divider()

            Button {
                Task {
                    if let image = NSImage(contentsOf: url) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.writeObjects([image])
                    }
                }
            } label: {
                Label("Copy Image", systemImage: "doc.on.doc")
            }

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url.path, forType: .string)
            } label: {
                Label("Copy File Path", systemImage: "link")
            }

            Divider()

            Button {
                if let screen = NSScreen.main {
                    try? NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:])
                }
            } label: {
                Label("Set as Wallpaper", systemImage: "photo")
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
            let size: CGFloat = masonry ? 800 : cellWidth * 2
            thumbnail = await ImageLoader.thumbnail(for: url, size: size)
            // If the file returned nil it may still be writing — retry up to 3 times
            if thumbnail == nil {
                for _ in 0..<3 {
                    try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5s
                    guard !Task.isCancelled else { return }
                    thumbnail = await ImageLoader.thumbnail(for: url, size: size)
                    if thumbnail != nil { return }
                }
            }
        }
    }

    private var borderColor: Color {
        if isMultiSelected { return .accentColor }
        if isSelected      { return .accentColor.opacity(0.7) }
        return .clear
    }

    private var shadowColor: Color {
        if isMultiSelected || isSelected { return Color.accentColor.opacity(0.4) }
        return .clear
    }
}
