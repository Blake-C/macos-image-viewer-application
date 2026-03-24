import AppKit
import Foundation

enum FolderScanner {
    static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "heic", "heif",
        "tiff", "tif", "bmp", "webp", "avif"
    ]

    /// Returns nil if the user cancelled, or (folder, images) if they confirmed.
    static func openPanelAndScan() async -> (folder: URL, images: [URL])? {
        await MainActor.run {
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.message = "Choose a folder to view images"
            panel.prompt = "Open Folder"
            panel.title = "Select Image Folder"
            return panel
        }.run()
    }
}

private extension NSOpenPanel {
    func run() async -> (folder: URL, images: [URL])? {
        await withCheckedContinuation { continuation in
            self.begin { response in
                guard response == .OK, let url = self.url else {
                    continuation.resume(returning: nil) // cancelled
                    return
                }
                continuation.resume(returning: (url, FolderScanner.scan(directory: url)))
            }
        }
    }
}

extension FolderScanner {
    static func scan(directory: URL) -> [URL] {
        guard let contents = try? FileManager.default
            .contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: .skipsHiddenFiles
            )
        else { return [] }

        return contents
            .filter { FolderScanner.imageExtensions.contains($0.pathExtension.lowercased()) }
            .sorted {
                $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
            }
    }
}
