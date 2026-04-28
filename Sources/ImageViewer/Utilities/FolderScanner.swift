import AppKit
import Foundation

enum FolderScanner {
    static let imageExtensions: Set<String> = [
        // Common formats
        "jpg", "jpeg", "png", "gif", "heic", "heif",
        "tiff", "tif", "bmp", "webp", "avif",
        // RAW formats (supported natively by macOS ImageIO)
        "dng", "raw", "cr2", "cr3", "arw", "nef", "orf", "rw2", "raf",
        "pef", "srw", "x3f", "3fr", "mef", "nrw", "rwl", "iiq",
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
        guard let url = await withCheckedContinuation({ continuation in
            self.begin { response in
                continuation.resume(returning: response == .OK ? self.url : nil)
            }
        }) else { return nil }
        let images = await FolderScanner.scan(directory: url)
        return (url, images)
    }
}

extension FolderScanner {
    static func scan(directory: URL, recursive: Bool = false) async -> [URL] {
        await Task.detached(priority: .userInitiated) {
            if recursive {
                return scanRecursive(directory: directory)
            }
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
        }.value
    }

    private static func scanRecursive(directory: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .isHiddenKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var results: [URL] = []
        for case let url as URL in enumerator {
            guard let vals = try? url.resourceValues(forKeys: [.isRegularFileKey]),
                  vals.isRegularFile == true else { continue }
            if FolderScanner.imageExtensions.contains(url.pathExtension.lowercased()) {
                results.append(url)
            }
        }
        return results.sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }
    }
}
