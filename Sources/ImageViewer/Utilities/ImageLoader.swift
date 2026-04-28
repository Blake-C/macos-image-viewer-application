import AppKit
import CoreGraphics
import ImageIO

// MARK: - Thumbnail cache

private final class ThumbnailCacheKey: NSObject {
    let url: URL
    let size: CGFloat

    init(url: URL, size: CGFloat) {
        self.url  = url
        self.size = size
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? ThumbnailCacheKey else { return false }
        return url == other.url && size == other.size
    }

    override var hash: Int {
        var h = Hasher()
        h.combine(url)
        h.combine(size)
        return h.finalize()
    }
}

private final class ThumbnailCache: @unchecked Sendable {
    static let shared = ThumbnailCache()

    private let cache = NSCache<ThumbnailCacheKey, NSImage>()

    init() { cache.countLimit = 400 }

    func get(_ url: URL, size: CGFloat) -> NSImage? {
        cache.object(forKey: ThumbnailCacheKey(url: url, size: size))
    }

    func set(_ url: URL, size: CGFloat, image: NSImage) {
        cache.setObject(image, forKey: ThumbnailCacheKey(url: url, size: size))
    }

    func removeAll() { cache.removeAllObjects() }
}

// MARK: - ImageLoader

enum ImageLoader {
    static func thumbnail(for url: URL, size: CGFloat) async -> NSImage? {
        if let cached = ThumbnailCache.shared.get(url, size: size) { return cached }
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
            ThumbnailCache.shared.set(url, size: size, image: img)
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

    /// Returns the full ImageIO metadata dictionary for an image file.
    static func rawMetadata(for url: URL) async -> [String: Any]? {
        await Task.detached(priority: .userInitiated) {
            guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            return CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [String: Any]
        }.value
    }

    /// Clears the thumbnail cache (call when a folder is changed).
    static func clearThumbnailCache() {
        ThumbnailCache.shared.removeAll()
    }
}
