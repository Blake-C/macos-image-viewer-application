import SwiftUI
import AppKit

enum ViewMode: Equatable {
    case folderPicker
    case gallery
    case fullImage
}

enum SortOption: String, CaseIterable, Identifiable {
    case nameAZ        = "Name (A → Z)"
    case nameZA        = "Name (Z → A)"
    case newestFirst   = "Date Modified (Newest)"
    case oldestFirst   = "Date Modified (Oldest)"
    case largestFirst  = "Size (Largest)"
    case smallestFirst = "Size (Smallest)"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .nameAZ, .nameZA:             return "textformat.abc"
        case .newestFirst, .oldestFirst:   return "calendar"
        case .largestFirst, .smallestFirst: return "doc"
        }
    }
}

final class AppState: ObservableObject {
    @Published var viewMode: ViewMode = .folderPicker
    @Published var imageURLs: [URL] = []
    @Published var selectedIndex: Int = 0
    @Published var noImagesFound: Bool = false
    @Published var folderVersion: Int = 0
    @Published var squareThumbnails: Bool = true
    @Published var keyboardNavigated: Bool = false
    @Published var galleryColumnCount: Int = 5
    @Published var sortOption: SortOption = .nameAZ {
        didSet { Task { await applyCurrentSort(resetSelection: true) } }
    }

    // Full image viewer state
    @Published var zoomScale: CGFloat = 1.0
    @Published var panOffset: CGSize = .zero

    // Original unsorted URLs so re-sorting is always clean
    private var unsortedURLs: [URL] = []

    // Last opened folder, kept for refresh
    private(set) var currentFolder: URL?

    private var keyMonitor: Any?
    private var scrollMonitor: Any?

    init() {
        startMonitors()
    }

    deinit {
        if let m = keyMonitor { NSEvent.removeMonitor(m) }
        if let m = scrollMonitor { NSEvent.removeMonitor(m) }
    }

    // MARK: - Folder loading

    func loadImages(_ urls: [URL], from folder: URL? = nil) async {
        if let folder { currentFolder = folder }
        unsortedURLs = urls
        await applyCurrentSort(resetSelection: true)
    }

    func refreshCurrentFolder() async {
        guard let folder = currentFolder else { return }
        let urls = FolderScanner.scan(directory: folder)
        unsortedURLs = urls
        folderVersion += 1
        await applyCurrentSort(resetSelection: false)
    }

    @MainActor
    private func applyCurrentSort(resetSelection: Bool = false) async {
        guard !unsortedURLs.isEmpty else {
            imageURLs = []
            return
        }

        let option = sortOption
        let urls = unsortedURLs
        let currentURL = imageURLs.indices.contains(selectedIndex) ? imageURLs[selectedIndex] : nil

        let sorted = await Task.detached(priority: .userInitiated) {
            Self.sort(urls, by: option)
        }.value

        imageURLs = sorted
        if resetSelection {
            selectedIndex = 0
        } else if let current = currentURL, let idx = sorted.firstIndex(of: current) {
            selectedIndex = idx
        }
    }

    private static func sort(_ urls: [URL], by option: SortOption) -> [URL] {
        switch option {
        case .nameAZ:
            return urls.sorted {
                $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
            }
        case .nameZA:
            return urls.sorted {
                $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedDescending
            }
        case .newestFirst, .oldestFirst:
            let pairs: [(URL, Date)] = urls.compactMap { url in
                let vals = try? url.resourceValues(forKeys: [.contentModificationDateKey])
                guard let date = vals?.contentModificationDate else { return nil }
                return (url, date)
            }
            let sorted = pairs.sorted { option == .newestFirst ? $0.1 > $1.1 : $0.1 < $1.1 }
            // files without modification dates go to the end
            let withDates = sorted.map(\.0)
            let withoutDates = urls.filter { u in !withDates.contains(u) }
            return withDates + withoutDates
        case .largestFirst, .smallestFirst:
            let pairs: [(URL, Int)] = urls.compactMap { url in
                let vals = try? url.resourceValues(forKeys: [.fileSizeKey])
                guard let size = vals?.fileSize else { return nil }
                return (url, size)
            }
            let sorted = pairs.sorted { option == .largestFirst ? $0.1 > $1.1 : $0.1 < $1.1 }
            let withSizes = sorted.map(\.0)
            let withoutSizes = urls.filter { u in !withSizes.contains(u) }
            return withSizes + withoutSizes
        }
    }

    // MARK: - Event monitors

    private func startMonitors() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleKeyEvent(event) ? nil : event
        }

        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self else { return event }
            if self.viewMode == .fullImage {
                self.handleScrollWheel(event)
                return nil
            }
            return event
        }
    }

    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        switch viewMode {
        case .gallery:      return handleGalleryKey(event)
        case .fullImage:    return handleFullImageKey(event)
        case .folderPicker: return false
        }
    }

    private func handleGalleryKey(_ event: NSEvent) -> Bool {
        guard !imageURLs.isEmpty else { return false }
        let opt = event.modifierFlags.contains(.option)

        switch event.keyCode {
        case 123: navigate(-1,                keyboard: true); return true  // left
        case 124: navigate(+1,                keyboard: true); return true  // right
        case 125: // down
            if opt { navigate(imageURLs.count - 1 - selectedIndex, keyboard: true) }
            else   { navigate(+galleryColumnCount, keyboard: true) }
            return true
        case 126: // up
            if opt { navigate(-selectedIndex, keyboard: true) }
            else   { navigate(-galleryColumnCount, keyboard: true) }
            return true
        case 36:
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    self.viewMode = .fullImage
                }
            }
            return true
        default:
            return false
        }
    }

    private var atFit: Bool {
        zoomScale < 1.01 && abs(panOffset.width) < 1 && abs(panOffset.height) < 1
    }

    private func handleFullImageKey(_ event: NSEvent) -> Bool {
        let cmd = event.modifierFlags.contains(.command)

        switch event.keyCode {
        case 36:
            DispatchQueue.main.async { self.handleTapInFullImage() }
            return true

        case 24 where cmd:
            applyKeyboardZoom(factor: 1.25)
            return true

        case 27 where cmd:
            applyKeyboardZoom(factor: 1.0 / 1.25)
            return true

        case 29 where cmd:
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    self.zoomScale = 1.0
                    self.panOffset = .zero
                }
            }
            return true

        case 123: // left arrow
            if atFit { DispatchQueue.main.async { self.navigate(-1) } }
            else { DispatchQueue.main.async { withAnimation(.interactiveSpring()) { self.panOffset.width += 60 } } }
            return true

        case 124: // right arrow
            if atFit { DispatchQueue.main.async { self.navigate(+1) } }
            else { DispatchQueue.main.async { withAnimation(.interactiveSpring()) { self.panOffset.width -= 60 } } }
            return true

        case 125:
            DispatchQueue.main.async { withAnimation(.interactiveSpring()) { self.panOffset.height -= 60 } }
            return true

        case 126:
            DispatchQueue.main.async { withAnimation(.interactiveSpring()) { self.panOffset.height += 60 } }
            return true

        default:
            return false
        }
    }

    private func applyKeyboardZoom(factor: CGFloat) {
        let anchor = cursorInViewCenter()
        DispatchQueue.main.async {
            withAnimation(.interactiveSpring()) {
                self.applyZoom(factor: factor, anchor: anchor)
            }
        }
    }

    private func handleScrollWheel(_ event: NSEvent) {
        let delta = event.scrollingDeltaY
        guard delta != 0 else { return }
        let factor: CGFloat = delta > 0 ? 1.08 : 0.93

        guard let window = NSApp.keyWindow, let contentView = window.contentView else { return }
        let loc = event.locationInWindow
        let bounds = contentView.bounds
        let anchor = CGSize(width: loc.x - bounds.width / 2,
                            height: -(loc.y - bounds.height / 2))

        DispatchQueue.main.async {
            withAnimation(.interactiveSpring()) {
                self.applyZoom(factor: factor, anchor: anchor)
            }
        }
    }

    private func applyZoom(factor: CGFloat, anchor: CGSize) {
        let newZoom = max(0.1, min(30.0, zoomScale * factor))
        let ratio = newZoom / zoomScale
        panOffset.width  = panOffset.width  * ratio + anchor.width  * (1 - ratio)
        panOffset.height = panOffset.height * ratio + anchor.height * (1 - ratio)
        zoomScale = newZoom
    }

    private func cursorInViewCenter() -> CGSize {
        guard let window = NSApp.keyWindow, let contentView = window.contentView else { return .zero }
        let screenLoc = NSEvent.mouseLocation
        let windowLoc = window.convertPoint(fromScreen: screenLoc)
        let bounds = contentView.bounds
        return CGSize(width:  windowLoc.x - bounds.width  / 2,
                      height: -(windowLoc.y - bounds.height / 2))
    }

    // MARK: - Navigation & state

    func navigate(_ delta: Int, keyboard: Bool = false) {
        let newIdx = max(0, min(imageURLs.count - 1, selectedIndex + delta))
        keyboardNavigated = keyboard
        selectedIndex = newIdx
    }

    func enterFullImage() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            viewMode = .fullImage
        }
    }

    func handleTapInFullImage() {
        if atFit {
            returnToGallery()
        } else {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                zoomScale = 1.0
                panOffset = .zero
            }
        }
    }

    func returnToGallery() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            zoomScale = 1.0
            panOffset = .zero
            viewMode = .gallery
        }
    }
}
