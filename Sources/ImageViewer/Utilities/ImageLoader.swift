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

// MARK: - Full-image cache (prev/current/next + a few extras)

private final class FullImageCache: @unchecked Sendable {
	static let shared = FullImageCache()

	private let cache = NSCache<NSURL, NSImage>()

	init() { cache.countLimit = 8 }

	func get(_ url: URL) -> NSImage? { cache.object(forKey: url as NSURL) }
	func set(_ url: URL, image: NSImage) { cache.setObject(image, forKey: url as NSURL) }
	func removeAll() { cache.removeAllObjects() }
}

// MARK: - Pixel-size cache (16 bytes per entry, large limit is fine)

private final class PixelSizeCache: @unchecked Sendable {
	static let shared = PixelSizeCache()

	private let cache = NSCache<NSURL, NSValue>()

	init() { cache.countLimit = 2000 }

	func get(_ url: URL) -> CGSize? { cache.object(forKey: url as NSURL).map { $0.sizeValue } }
	func set(_ url: URL, size: CGSize) { cache.setObject(NSValue(size: size), forKey: url as NSURL) }
	func removeAll() { cache.removeAllObjects() }
}

// MARK: - Metadata cache (EXIF/IPTC dicts, capped to avoid excessive memory)

private final class MetadataCache: @unchecked Sendable {
	static let shared = MetadataCache()

	private let cache = NSCache<NSURL, NSDictionary>()

	init() { cache.countLimit = 100 }

	func get(_ url: URL) -> [String: Any]? { cache.object(forKey: url as NSURL) as? [String: Any] }
	func set(_ url: URL, meta: [String: Any]) { cache.setObject(meta as NSDictionary, forKey: url as NSURL) }
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
		if let cached = FullImageCache.shared.get(url) { return cached }
		return await Task.detached(priority: .userInitiated) {
			guard let img = NSImage(contentsOf: url) else { return nil }
			FullImageCache.shared.set(url, image: img)
			return img
		}.value
	}

	/// Returns the actual pixel dimensions of the image file.
	static func pixelSize(for url: URL) async -> CGSize? {
		if let cached = PixelSizeCache.shared.get(url) { return cached }
		return await Task.detached(priority: .userInitiated) {
			guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
				  let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
				  let w = props[kCGImagePropertyPixelWidth] as? CGFloat,
				  let h = props[kCGImagePropertyPixelHeight] as? CGFloat
			else { return nil }
			let size = CGSize(width: w, height: h)
			PixelSizeCache.shared.set(url, size: size)
			return size
		}.value
	}

	/// Returns the full ImageIO metadata dictionary for an image file.
	static func rawMetadata(for url: URL) async -> [String: Any]? {
		if let cached = MetadataCache.shared.get(url) { return cached }
		return await Task.detached(priority: .userInitiated) {
			guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
			guard let meta = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [String: Any]
			else { return nil }
			MetadataCache.shared.set(url, meta: meta)
			return meta
		}.value
	}

	/// Warms the full-image cache for `url` at background priority.
	/// Safe to call speculatively — no-ops if already cached.
	static func prefetch(for url: URL) {
		guard FullImageCache.shared.get(url) == nil else { return }
		Task.detached(priority: .background) {
			guard let img = NSImage(contentsOf: url) else { return }
			FullImageCache.shared.set(url, image: img)
		}
	}

	/// Clears the thumbnail cache (call when a folder is changed).
	static func clearThumbnailCache() {
		ThumbnailCache.shared.removeAll()
	}

	/// Clears all caches (call on folder change to avoid serving stale decoded images).
	static func clearAllCaches() {
		ThumbnailCache.shared.removeAll()
		FullImageCache.shared.removeAll()
		PixelSizeCache.shared.removeAll()
		MetadataCache.shared.removeAll()
	}
}
