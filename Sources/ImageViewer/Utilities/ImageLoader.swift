import AppKit
import CoreGraphics
import ImageIO

// MARK: - Thumbnail cache

private final class ThumbnailCache: @unchecked Sendable {
    static let shared = ThumbnailCache()

    private let lock = NSLock()
    private var cache: [URL: NSImage] = [:]
    private var order: [URL] = []          // LRU order (oldest first)
    private let maxCount = 400             // ~400 thumbnails at 320px ≈ reasonable memory

    func get(_ url: URL) -> NSImage? {
        lock.lock(); defer { lock.unlock() }
        guard let img = cache[url] else { return nil }
        // Move to most-recently-used end
        order.removeAll { $0 == url }
        order.append(url)
        return img
    }

    func set(_ url: URL, image: NSImage) {
        lock.lock(); defer { lock.unlock() }
        if cache[url] == nil { order.append(url) }
        cache[url] = image
        // Evict oldest entries when over capacity
        while order.count > maxCount {
            let oldest = order.removeFirst()
            cache.removeValue(forKey: oldest)
        }
    }

    func removeAll() {
        lock.lock(); defer { lock.unlock() }
        cache.removeAll()
        order.removeAll()
    }
}

// MARK: - ImageLoader

enum ImageLoader {
    static func thumbnail(for url: URL, size: CGFloat) async -> NSImage? {
        if let cached = ThumbnailCache.shared.get(url) { return cached }
        return await Task.detached(priority: .userInitiated) {
            guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceThumbnailMaxPixelSize: size,
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true
            ]
            guard let cgImg = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary)
            else { return nil }
            let img = NSImage(cgImage: cgImg, size: NSSize(width: cgImg.width, height: cgImg.height))
            ThumbnailCache.shared.set(url, image: img)
            return img
        }.value
    }

    static func fullImage(for url: URL) async -> NSImage? {
        await Task.detached(priority: .userInitiated) {
            NSImage(contentsOf: url)
        }.value
    }

    /// Returns the actual pixel dimensions of the image file.
    static func pixelSize(for url: URL) async -> CGSize? {
        await Task.detached(priority: .userInitiated) {
            guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
                  let w = props[kCGImagePropertyPixelWidth] as? CGFloat,
                  let h = props[kCGImagePropertyPixelHeight] as? CGFloat
            else { return nil }
            return CGSize(width: w, height: h)
        }.value
    }

    /// Clears the thumbnail cache (call when a folder is changed).
    static func clearThumbnailCache() {
        ThumbnailCache.shared.removeAll()
    }
}
