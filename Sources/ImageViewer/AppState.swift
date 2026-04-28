import SwiftUI
import AppKit

enum ViewMode: Equatable {
    case folderPicker
    case gallery
    case fullImage
}

enum SortOption: String, CaseIterable, Identifiable, Codable {
    case nameAZ        = "Name (A → Z)"
    case nameZA        = "Name (Z → A)"
    case newestFirst   = "Date Modified (Newest)"
    case oldestFirst   = "Date Modified (Oldest)"
    case largestFirst  = "Size (Largest)"
    case smallestFirst = "Size (Smallest)"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .nameAZ, .nameZA:              return "textformat.abc"
        case .newestFirst, .oldestFirst:    return "calendar"
        case .largestFirst, .smallestFirst: return "doc"
        }
    }
}

final class AppState: ObservableObject {

    // MARK: - Per-folder settings (persisted)

    private struct FolderSettings: Codable {
        var sortOption: SortOption
        var searchText: String
        var filterFileType: String?
        var filterDateFrom: Date?
        var filterDateTo: Date?
        var showFavoritesOnly: Bool
        var squareThumbnails: Bool
        var masonryLayout: Bool
        var thumbnailSize: CGFloat
        var scanRecursively: Bool
    }

    /// True while restoring settings from disk — suppresses redundant saves & sort triggers.
    private var restoringSettings = false

    // MARK: - View state

    @Published var viewMode: ViewMode = .folderPicker
    @Published var imageURLs: [URL] = []        // sorted + filtered — what views render
    @Published var selectedIndex: Int = 0
    @Published var noImagesFound: Bool = false
    @Published var folderVersion: Int = 0
    @Published var squareThumbnails: Bool = true {
        didSet {
            guard !restoringSettings, currentFolder != nil else { return }
            saveFolderSettings()
        }
    }
    @Published var masonryLayout: Bool = false {
        didSet {
            guard !restoringSettings, currentFolder != nil else { return }
            saveFolderSettings()
        }
    }
    @Published var thumbnailSize: CGFloat = 160 {
        didSet {
            guard !restoringSettings, currentFolder != nil else { return }
            saveFolderSettings()
        }
    }
    @Published var scanRecursively: Bool = false {
        didSet {
            guard !restoringSettings, currentFolder != nil else { return }
            saveFolderSettings()
            if let folder = currentFolder {
                Task { await refreshCurrentFolder(folder: folder) }
            }
        }
    }
    @Published var keyboardNavigated: Bool = false
    @Published var galleryColumnCount: Int = 5
    @Published var masonryColumnCount: Int = 2
    @Published var imageDimensions: [URL: CGSize] = [:]

    // MARK: - Sort

    @Published var sortOption: SortOption = .nameAZ {
        didSet {
            guard !restoringSettings else { return }
            Task { await applyCurrentSort(resetSelection: true) }
        }
    }

    // MARK: - Full-image viewer

    @Published var zoomScale: CGFloat = 1.0
    @Published var panOffset: CGSize = .zero
    @Published var showInfoOverlay: Bool = false
    @Published var showMetadataPanel: Bool = false
    @Published var focusSearchOnGalleryReturn: Bool = false
    @Published var shouldFocusSearch: Bool = false
    @Published var totalFileSize: Int64 = 0
    @Published var fullImageViewSize: CGSize = .zero    // set by FullImageView GeometryReader
    @Published var currentImagePixelSize: CGSize? = nil  // set by FullImageView task
    @Published var currentImageMetadata: [String: Any]? = nil  // set by FullImageView task

    // MARK: - Filters

    @Published var searchText: String = "" {
        didSet { guard !restoringSettings else { return }; scheduleFilter() }
    }
    @Published var filterFileType: String? = nil {
        didSet { guard !restoringSettings else { return }; scheduleFilter() }
    }
    @Published var filterDateFrom: Date? = nil {
        didSet { guard !restoringSettings else { return }; scheduleFilter() }
    }
    @Published var filterDateTo: Date? = nil {
        didSet { guard !restoringSettings else { return }; scheduleFilter() }
    }
    @Published var showFavoritesOnly: Bool = false {
        didSet { guard !restoringSettings else { return }; scheduleFilter() }
    }

    // MARK: - Favorites (persisted)

    @Published private(set) var favoriteURLs: Set<URL>

    // MARK: - Multi-select

    @Published var selectedURLs: Set<URL> = []

    // MARK: - Slideshow

    @Published var slideshowActive: Bool = false
    @Published var slideshowInterval: Double
    @Published var kenBurnsEnabled: Bool
    @Published var slideshowShuffle: Bool
    /// Set to true by the slideshow timer so FullImageView knows to crossfade.
    /// Consumed (reset) at the start of each FullImageView task.
    @Published var isSlideshowTransition: Bool = false

    // MARK: - Open-folder trigger (per-window, replaces notification)

    @Published var openFolderRequested: Bool = false
    @Published var needsScrollToSelected: Bool = false

    // MARK: - Recent folders

    @Published private(set) var recentFolders: [URL] = []

    // MARK: - Lock / auth state

    @Published var currentFolderIsLocked: Bool = false
    @Published var authFailed: Bool = false
    @Published var pendingAuthFolder: URL? = nil
    @Published var retryAuthRequested: Bool = false

    // MARK: - Pipeline internals

    private var unsortedURLs: [URL] = []
    private var sortedURLs: [URL] = [] {
        didSet { _availableFileTypes = nil }   // invalidate cache on sort
    }
    private var modDateCache: [URL: Date] = [:]
    private var fileSizeCache: [URL: Int] = [:]
    private var _availableFileTypes: [String]? = nil
    private(set) var currentFolder: URL?

    private var keyMonitor: Any?
    private var scrollMonitor: Any?
    private var magnifyMonitor: Any?
    private var slideshowTask: Task<Void, Never>?
    private var lastSizedURLs: [URL] = []
    private var folderWatchSource: DispatchSourceFileSystemObject?
    private var folderWatchFd: Int32 = -1
    private var folderRefreshTask: Task<Void, Never>?
    private var suppressFolderRefresh = false

    // MARK: - UserDefaults keys

    private enum UDKey {
        static let lastFolderPath    = "lastFolderPath"
        static let favorites         = "favoriteImagePaths"
        static let favoriteBookmarks = "favoriteImageBookmarks"
        static let slideshowInterval = "slideshowInterval"
        static let kenBurnsEnabled   = "kenBurnsEnabled"
        static let slideshowShuffle  = "slideshowShuffle"
        static let folderSettings    = "folderSettings"
        static let recentFolders     = "recentFolders"
    }

    // MARK: - Init / deinit

    init() {
        let ud = UserDefaults.standard

        // Load favorites from bookmarks (survives renames/moves), fall back to paths
        var resolved: Set<URL> = []
        if let bookmarkList = ud.array(forKey: UDKey.favoriteBookmarks) as? [Data] {
            for data in bookmarkList {
                var stale = false
                if let url = try? URL(resolvingBookmarkData: data,
                                      options: .withSecurityScope,
                                      relativeTo: nil,
                                      bookmarkDataIsStale: &stale) {
                    resolved.insert(url)
                } else if let url = try? URL(resolvingBookmarkData: data,
                                             options: [],
                                             relativeTo: nil,
                                             bookmarkDataIsStale: &stale) {
                    resolved.insert(url)
                }
            }
        }
        if resolved.isEmpty {
            // First-run migration from old path-based storage
            resolved = Set(
                (ud.stringArray(forKey: UDKey.favorites) ?? []).map { URL(fileURLWithPath: $0) }
            )
        }
        favoriteURLs = resolved
        let stored = ud.double(forKey: UDKey.slideshowInterval)
        slideshowInterval = stored > 0 ? stored : 3.0
        kenBurnsEnabled = ud.object(forKey: UDKey.kenBurnsEnabled) != nil
            ? ud.bool(forKey: UDKey.kenBurnsEnabled) : true   // on by default
        slideshowShuffle = ud.bool(forKey: UDKey.slideshowShuffle)
        recentFolders = (ud.stringArray(forKey: UDKey.recentFolders) ?? [])
            .map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        startMonitors()
    }

    deinit {
        if let m = keyMonitor     { NSEvent.removeMonitor(m) }
        if let m = scrollMonitor  { NSEvent.removeMonitor(m) }
        if let m = magnifyMonitor { NSEvent.removeMonitor(m) }
        slideshowTask?.cancel()
    }

    // MARK: - Folder lock

    func refreshLockState() {
        currentFolderIsLocked = currentFolder.map { FolderLockManager.shared.isLocked($0) } ?? false
    }

    func enableLockForCurrentFolder() {
        guard let folder = currentFolder else { return }
        FolderLockManager.shared.lock(folder)
        currentFolderIsLocked = true
    }

    @MainActor
    func disableLockForCurrentFolder() async -> Bool {
        guard let folder = currentFolder else { return false }
        let ok = await FolderLockManager.shared.authenticate(
            for: folder,
            reason: "Authenticate to remove Touch ID protection from \"\(folder.lastPathComponent)\""
        )
        if ok {
            FolderLockManager.shared.unlock(folder)
            currentFolderIsLocked = false
        }
        return ok
    }

    // MARK: - Last-opened folder

    var lastFolderURL: URL? {
        guard let path = UserDefaults.standard.string(forKey: UDKey.lastFolderPath) else { return nil }
        return FileManager.default.fileExists(atPath: path) ? URL(fileURLWithPath: path) : nil
    }

    private func recordRecentFolder(_ url: URL) {
        var recents = recentFolders.filter { $0 != url }
        recents.insert(url, at: 0)
        if recents.count > 10 { recents = Array(recents.prefix(10)) }
        recentFolders = recents
        UserDefaults.standard.set(recents.map(\.path), forKey: UDKey.recentFolders)
    }

    func requestOpenFolder() {
        openFolderRequested = true
    }

    @MainActor
    func openRecentFolder(_ url: URL) async {
        guard FileManager.default.fileExists(atPath: url.path) else {
            // Remove stale entry
            recentFolders.removeAll { $0 == url }
            UserDefaults.standard.set(recentFolders.map(\.path), forKey: UDKey.recentFolders)
            return
        }

        if FolderLockManager.shared.isLocked(url) {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
            let authorized = await FolderLockManager.shared.authenticate(
                for: url,
                reason: "Authenticate to open \"\(url.lastPathComponent)\""
            )
            guard authorized else {
                authFailed = true
                pendingAuthFolder = url
                viewMode = .folderPicker
                return
            }
        }

        let images = await FolderScanner.scan(directory: url)
        zoomScale = 1.0
        panOffset = .zero
        noImagesFound = images.isEmpty
        folderVersion += 1
        await loadImages(images, from: url)
        withAnimation {
            viewMode = images.isEmpty ? .folderPicker : .gallery
        }
    }

    // MARK: - Folder loading

    @MainActor
    func loadImages(_ urls: [URL], from folder: URL? = nil) async {
        if let folder {
            currentFolder = folder
            refreshLockState()
            startWatchingFolder(folder)
            UserDefaults.standard.set(folder.path, forKey: UDKey.lastFolderPath)
            recordRecentFolder(folder)
            if let saved = loadFolderSettings(for: folder) {
                restoringSettings = true
                sortOption        = saved.sortOption
                searchText        = saved.searchText
                filterFileType    = saved.filterFileType
                filterDateFrom    = saved.filterDateFrom
                filterDateTo      = saved.filterDateTo
                showFavoritesOnly = saved.showFavoritesOnly
                squareThumbnails  = saved.squareThumbnails
                masonryLayout     = saved.masonryLayout
                thumbnailSize     = saved.thumbnailSize > 0 ? saved.thumbnailSize : 160
                scanRecursively   = saved.scanRecursively
                restoringSettings = false
            }
        }
        // If recursive scanning is enabled, re-scan now that settings are restored
        if let folder, scanRecursively {
            unsortedURLs = await FolderScanner.scan(directory: folder, recursive: true)
        } else {
            unsortedURLs = urls
        }
        if folder != nil {
            imageDimensions = [:]
        }
        prefetchDimensions(for: unsortedURLs)
        ImageLoader.clearThumbnailCache()
        await applyCurrentSort(resetSelection: true)
    }

    @MainActor
    private func applyCurrentSort(resetSelection: Bool = false) async {
        guard !unsortedURLs.isEmpty else {
            sortedURLs = []
            modDateCache = [:]
            imageURLs = []
            return
        }

        let option = sortOption
        let urls = unsortedURLs
        let currentURL = imageURLs.indices.contains(selectedIndex) ? imageURLs[selectedIndex] : nil

        let (sorted, dateCache, sizeCache) = await Task.detached(priority: .userInitiated) {
            Self.sortAndCache(urls, by: option)
        }.value

        sortedURLs    = sorted
        modDateCache  = dateCache
        fileSizeCache = sizeCache
        applyFiltersNow(resetSelection: resetSelection,
                        preserveURL: resetSelection ? nil : currentURL)
    }

    private func scheduleFilter() {
        Task { @MainActor in applyFiltersNow() }
    }

    @MainActor
    private func applyFiltersNow(resetSelection: Bool = false, preserveURL: URL? = nil) {
        let text      = searchText.lowercased()
        let ext       = filterFileType
        let from      = filterDateFrom
        let to        = filterDateTo
        let favs      = favoriteURLs
        let onlyFavs  = showFavoritesOnly
        let cache     = modDateCache

        var filtered = sortedURLs

        let lowerNames: [URL: String] = text.isEmpty ? [:] :
            Dictionary(uniqueKeysWithValues: sortedURLs.map { ($0, $0.lastPathComponent.lowercased()) })

        if onlyFavs      { filtered = filtered.filter { favs.contains($0) } }
        if !text.isEmpty { filtered = filtered.filter { lowerNames[$0, default: ""].contains(text) } }
        if let ext       { filtered = filtered.filter { $0.pathExtension.lowercased() == ext } }
        if let from      {
            filtered = filtered.filter { (cache[$0] ?? .distantPast) >= from }
        }
        if let to        {
            let endOfDay = Calendar.current.date(bySettingHour: 23, minute: 59,
                                                  second: 59, of: to) ?? to
            filtered = filtered.filter { (cache[$0] ?? .distantFuture) <= endOfDay }
        }

        // Prune stale multi-selections
        let newSet = Set(filtered)
        selectedURLs = selectedURLs.intersection(newSet)

        imageURLs = filtered

        if resetSelection {
            selectedIndex = 0
        } else if let url = preserveURL, let idx = filtered.firstIndex(of: url) {
            selectedIndex = idx
        } else {
            selectedIndex = min(selectedIndex, max(0, filtered.count - 1))
        }

        // Persist settings after every sort/filter operation (not during restore)
        if !restoringSettings { saveFolderSettings() }

        // Recompute total file size (skip if URLs haven't changed)
        let urls      = imageURLs
        let sizeCache = fileSizeCache
        guard urls != lastSizedURLs else { return }
        lastSizedURLs = urls
        Task.detached(priority: .utility) {
            let size = urls.reduce(into: Int64(0)) { total, url in
                if let cached = sizeCache[url] {
                    total += Int64(cached)
                } else {
                    let v = try? url.resourceValues(forKeys: [.fileSizeKey])
                    total += Int64(v?.fileSize ?? 0)
                }
            }
            await MainActor.run { self.totalFileSize = size }
        }
    }

    // All file-type extensions present in the current folder (pre-filter), cached
    var availableFileTypes: [String] {
        if let cached = _availableFileTypes { return cached }
        let types = Array(Set(sortedURLs.map { $0.pathExtension.lowercased() })).sorted()
        _availableFileTypes = types
        return types
    }

    var hasActiveFilters: Bool {
        !searchText.isEmpty || filterFileType != nil ||
        filterDateFrom != nil || filterDateTo != nil || showFavoritesOnly
    }

    func clearFilters() {
        searchText     = ""
        filterFileType = nil
        filterDateFrom = nil
        filterDateTo   = nil
        showFavoritesOnly = false
    }

    // MARK: - Per-folder settings persistence

    /// In-memory copy of the full settings dictionary — avoids decode on every save.
    private var folderSettingsCache: [String: FolderSettings]?

    private static let folderSettingsLimit = 50

    private func saveFolderSettings() {
        guard let folder = currentFolder else { return }
        let settings = FolderSettings(
            sortOption:        sortOption,
            searchText:        searchText,
            filterFileType:    filterFileType,
            filterDateFrom:    filterDateFrom,
            filterDateTo:      filterDateTo,
            showFavoritesOnly: showFavoritesOnly,
            squareThumbnails:  squareThumbnails,
            masonryLayout:     masonryLayout,
            thumbnailSize:     thumbnailSize,
            scanRecursively:   scanRecursively
        )
        var all = cachedFolderSettings()
        all[folder.path] = settings

        // Prune oldest entries if over limit, keeping recent folders first
        if all.count > Self.folderSettingsLimit {
            let sorted = recentFolders.map(\.path)
            let keep = Set(sorted.prefix(Self.folderSettingsLimit))
            all = all.filter { keep.contains($0.key) || $0.key == folder.path }
            // If still over (e.g. no recentFolders populated), take arbitrary subset
            if all.count > Self.folderSettingsLimit {
                all = Dictionary(uniqueKeysWithValues: Array(all.prefix(Self.folderSettingsLimit)))
            }
        }

        folderSettingsCache = all
        if let data = try? JSONEncoder().encode(all) {
            UserDefaults.standard.set(data, forKey: UDKey.folderSettings)
        }
    }

    private func loadFolderSettings(for folder: URL) -> FolderSettings? {
        cachedFolderSettings()[folder.path]
    }

    private func cachedFolderSettings() -> [String: FolderSettings] {
        if let cached = folderSettingsCache { return cached }
        guard let data = UserDefaults.standard.data(forKey: UDKey.folderSettings),
              let all  = try? JSONDecoder().decode([String: FolderSettings].self, from: data)
        else {
            folderSettingsCache = [:]
            return [:]
        }
        folderSettingsCache = all
        return all
    }

    // MARK: - Refresh

    func refreshCurrentFolder(folder: URL? = nil) async {
        guard let folder = folder ?? currentFolder else { return }
        let urls = await FolderScanner.scan(directory: folder, recursive: scanRecursively)
        unsortedURLs = urls
        folderVersion += 1
        ImageLoader.clearThumbnailCache()
        await applyCurrentSort(resetSelection: false)
    }

    // MARK: - Favorites

    func toggleFavorite(_ url: URL) {
        if favoriteURLs.contains(url) { favoriteURLs.remove(url) }
        else                          { favoriteURLs.insert(url) }
        saveFavorites()
        if showFavoritesOnly { scheduleFilter() }
    }

    private func saveFavorites() {
        let ud = UserDefaults.standard
        // Save paths (legacy / readable)
        ud.set(favoriteURLs.map(\.path), forKey: UDKey.favorites)
        // Save bookmarks (survive renames and moves within a volume)
        let bookmarks = favoriteURLs.compactMap {
            try? $0.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        }
        ud.set(bookmarks, forKey: UDKey.favoriteBookmarks)
    }

    func isFavorite(_ url: URL) -> Bool { favoriteURLs.contains(url) }

    // MARK: - Multi-select

    func handleThumbnailTap(url: URL, atIndex idx: Int) {
        let cmd   = NSEvent.modifierFlags.contains(.command)
        let shift = NSEvent.modifierFlags.contains(.shift)

        if cmd {
            if selectedURLs.contains(url) { selectedURLs.remove(url) }
            else                          { selectedURLs.insert(url) }
            selectedIndex = idx
        } else if shift, !selectedURLs.isEmpty {
            let lo = min(selectedIndex, idx)
            let hi = max(selectedIndex, idx)
            let clamped = max(0, lo)...min(imageURLs.count - 1, hi)
            imageURLs[clamped].forEach { selectedURLs.insert($0) }
        } else if !selectedURLs.isEmpty {
            // Plain click while selection exists → clear and navigate
            selectedURLs.removeAll()
            keyboardNavigated = false
            selectedIndex = idx
        } else {
            // Normal tap — open full image
            keyboardNavigated = false
            selectedIndex = idx
            enterFullImage()
        }
    }

    func clearMultiSelect() { selectedURLs.removeAll() }

    func trashSelected() {
        let toDelete = selectedURLs
        selectedURLs.removeAll()
        Task { @MainActor in
            toDelete.forEach { deleteImage(at: $0, playSound: false) }
            NSSound(contentsOfFile: "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/dock/drag to trash.aif", byReference: true)?.play()
        }
    }

    func copyPathsOfSelected() {
        let paths = selectedURLs.map(\.path).sorted().joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(paths, forType: .string)
    }

    @MainActor
    func moveSelectedToFolder() async {
        let toMove = selectedURLs
        guard !toMove.isEmpty else { return }

        let panel = NSOpenPanel()
        panel.canChooseFiles       = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a destination folder"
        panel.prompt  = "Move Here"
        panel.title   = "Move \(toMove.count) Image\(toMove.count == 1 ? "" : "s")"

        guard await panel.begin() == .OK, let destination = panel.url else { return }

        suppressFolderRefresh = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.suppressFolderRefresh = false
        }

        selectedURLs.removeAll()

        for url in toMove {
            let dest = destination.appendingPathComponent(url.lastPathComponent)
            try? FileManager.default.moveItem(at: url, to: dest)
            unsortedURLs.removeAll { $0 == url }
            sortedURLs.removeAll   { $0 == url }
            imageURLs.removeAll    { $0 == url }
        }

        selectedIndex = min(selectedIndex, max(0, imageURLs.count - 1))
    }

    // MARK: - Delete

    @MainActor
    func deleteImage(at url: URL, playSound: Bool = true) {
        suppressFolderRefresh = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.suppressFolderRefresh = false
        }
        try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
        if playSound { NSSound(contentsOfFile: "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/dock/drag to trash.aif", byReference: true)?.play() }
        unsortedURLs.removeAll { $0 == url }
        sortedURLs.removeAll   { $0 == url }
        guard let idx = imageURLs.firstIndex(of: url) else { return }
        imageURLs.remove(at: idx)
        selectedIndex = min(selectedIndex, max(0, imageURLs.count - 1))
    }

    // MARK: - Slideshow

    func toggleSlideshow() {
        if slideshowActive {
            slideshowActive = false     // FullImageView observes this and snaps Ken Burns
            slideshowTask?.cancel()
            slideshowTask = nil
            isSlideshowTransition = false
            // Snap any user-applied zoom (non-Ken-Burns) to fit
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { zoomScale = 1.0; panOffset = .zero }
        } else {
            slideshowActive = true
            if viewMode != .fullImage { enterFullImage() }
            startSlideshowTask()
        }
    }

    private func startSlideshowTask() {
        slideshowTask?.cancel()
        let interval = slideshowInterval
        slideshowTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.slideshowActive else { return }
                let nanos = UInt64(max(0.5, interval) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanos)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard self.slideshowActive else { return }
                    self.isSlideshowTransition = true
                    if self.slideshowShuffle, self.imageURLs.count > 1 {
                        var next: Int
                        repeat { next = Int.random(in: 0..<self.imageURLs.count) }
                        while next == self.selectedIndex
                        self.selectedIndex = next
                    } else {
                        let next = self.selectedIndex + 1
                        self.selectedIndex = next >= self.imageURLs.count ? 0 : next
                    }
                }
            }
        }
    }

    func toggleShuffle() {
        slideshowShuffle.toggle()
        UserDefaults.standard.set(slideshowShuffle, forKey: UDKey.slideshowShuffle)
    }

    func setSlideshowInterval(_ interval: Double) {
        slideshowInterval = max(0.5, interval)
        UserDefaults.standard.set(slideshowInterval, forKey: UDKey.slideshowInterval)
        if slideshowActive { startSlideshowTask() }
    }

    func toggleKenBurns() {
        kenBurnsEnabled.toggle()
        UserDefaults.standard.set(kenBurnsEnabled, forKey: UDKey.kenBurnsEnabled)
        if !kenBurnsEnabled {
            // Cancel any in-flight animation and snap back to fit
            var snap = Transaction()
            snap.disablesAnimations = true
            withTransaction(snap) {
                zoomScale = 1.0
                panOffset = .zero
            }
        }
    }

    // MARK: - Zoom to actual pixels (Cmd+1)

    func zoomToActualPixels() {
        guard let pixelSize = currentImagePixelSize,
              pixelSize.width > 0, pixelSize.height > 0 else { return }
        let vw = fullImageViewSize.width
        let vh = fullImageViewSize.height
        guard vw > 0, vh > 0 else { return }

        // At zoomScale 1.0 the image fits inside the view.
        // fitScale is how much the image is scaled down to fit.
        let fitScale = min(vw / pixelSize.width, vh / pixelSize.height)
        // We want 1 image pixel = 1 screen point → zoom = 1 / fitScale
        let targetZoom = 1.0 / fitScale
        let factor = targetZoom / zoomScale
        let anchor = cursorInViewCenter()
        withAnimation(.interactiveSpring()) {
            applyZoom(factor: factor, anchor: anchor)
        }
    }

    // MARK: - Folder watching

    private func startWatchingFolder(_ url: URL) {
        stopWatchingFolder()
        guard (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { return }
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        folderWatchFd = fd
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete, .link],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            guard let self, !self.suppressFolderRefresh else { return }
            folderRefreshTask?.cancel()
            folderRefreshTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s debounce
                guard !Task.isCancelled, let self else { return }
                await self.refreshCurrentFolder()
            }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        folderWatchSource = source
    }

    private func stopWatchingFolder() {
        folderRefreshTask?.cancel()
        folderRefreshTask = nil
        folderWatchSource?.cancel()
        folderWatchSource = nil
        folderWatchFd = -1
    }

    // MARK: - Event monitors

    private func startMonitors() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            // AppKit guarantees event monitor callbacks fire on the main thread;
            // assumeIsolated makes the compiler aware of that invariant.
            return MainActor.assumeIsolated { self.handleKeyEvent(event) } ? nil : event
        }

        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, self.viewMode == .fullImage else { return event }

            // The local monitor fires for every window in the app, including the
            // metadata sheet. While the sheet is open, pass all events through so
            // the sheet's ScrollView can receive them. The main image window has no
            // SwiftUI ScrollView, so passed-through events there are harmless.
            if self.showMetadataPanel { return event }

            let delta = event.scrollingDeltaY
            guard delta != 0 else { return nil }
            let factor: CGFloat = delta > 0 ? 1.08 : 0.93
            guard let contentView = event.window?.contentView else { return nil }
            let bounds = contentView.bounds
            let loc = event.locationInWindow
            let anchor = CGSize(
                width:  loc.x - bounds.width  / 2,
                height: -(loc.y - bounds.height / 2)
            )
            DispatchQueue.main.async {
                withAnimation(.interactiveSpring()) { self.applyZoom(factor: factor, anchor: anchor) }
            }
            return nil
        }

        magnifyMonitor = NSEvent.addLocalMonitorForEvents(matching: .magnify) { [weak self] event in
            guard let self, self.viewMode == .fullImage, !self.showMetadataPanel else { return event }
            let factor = 1.0 + event.magnification
            guard let contentView = event.window?.contentView else { return nil }
            let bounds = contentView.bounds
            let loc = event.locationInWindow
            let anchor = CGSize(
                width:  loc.x - bounds.width  / 2,
                height: -(loc.y - bounds.height / 2)
            )
            DispatchQueue.main.async {
                withAnimation(.interactiveSpring()) { self.applyZoom(factor: factor, anchor: anchor) }
            }
            return nil
        }
    }

    @MainActor
    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        guard !(NSApp.keyWindow is NSOpenPanel) else { return false }
        switch viewMode {
        case .gallery:      return handleGalleryKey(event)
        case .fullImage:    return handleFullImageKey(event)
        case .folderPicker: return false
        }
    }

    @MainActor
    private func handleGalleryKey(_ event: NSEvent) -> Bool {
        let cmd = event.modifierFlags.contains(.command)

        if event.keyCode == 15 && cmd {      // Cmd+R — refresh
            Task { await refreshCurrentFolder() }
            return true
        }
        if event.keyCode == 31 && cmd {      // Cmd+O — open folder
            requestOpenFolder()
            return true
        }
        if event.keyCode == 1 && cmd {       // Cmd+S — focus search
            shouldFocusSearch = true
            return true
        }

        guard !imageURLs.isEmpty else { return false }
        let opt = event.modifierFlags.contains(.option)

        switch event.keyCode {
        case 123: navigate(-1,                keyboard: true); return true
        case 124: navigate(+1,                keyboard: true); return true
        case 125:
            if opt { navigate(imageURLs.count - 1 - selectedIndex, keyboard: true) }
            else   { navigate(+(masonryLayout ? masonryColumnCount : galleryColumnCount), keyboard: true) }
            return true
        case 126:
            if opt { navigate(-selectedIndex, keyboard: true) }
            else   { navigate(-(masonryLayout ? masonryColumnCount : galleryColumnCount), keyboard: true) }
            return true
        case 36, 49:        // Enter or Space — open image
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                viewMode = .fullImage
            }
            return true
        case 51 where cmd:  // Cmd+Delete — trash selected/focused image
            let url = imageURLs[selectedIndex]
            deleteImage(at: url)
            return true
        case 53:   // Escape — clear multi-select
            if !selectedURLs.isEmpty { selectedURLs.removeAll(); return true }
            return false
        default:
            return false
        }
    }

    private var atFit: Bool {
        zoomScale < 1.01 && abs(panOffset.width) < 1 && abs(panOffset.height) < 1
    }

    @MainActor
    private func handleFullImageKey(_ event: NSEvent) -> Bool {
        let cmd = event.modifierFlags.contains(.command)

        switch event.keyCode {
        case 3:                 // f — toggle favorite
            if imageURLs.indices.contains(selectedIndex) {
                toggleFavorite(imageURLs[selectedIndex])
            }
            return true

        case 34:                // i — toggle info overlay
            showInfoOverlay.toggle()
            return true

        case 46:                // m — toggle metadata panel
            showMetadataPanel.toggle()
            return true

        case 49:                // Space — same as Enter (toggle full image / back to gallery)
            handleTapInFullImage()
            return true

        case 35 where cmd:      // Cmd+P — toggle slideshow
            toggleSlideshow()
            return true

        case 15 where cmd:      // Cmd+R — refresh
            Task { await refreshCurrentFolder() }
            return true

        case 31 where cmd:      // Cmd+O — open folder
            requestOpenFolder()
            return true

        case 18 where cmd:      // Cmd+1 — zoom to actual pixels
            zoomToActualPixels()
            return true

        case 36:                // Enter
            handleTapInFullImage()
            return true

        case 24 where cmd:      // Cmd+=
            applyKeyboardZoom(factor: 1.25)
            return true

        case 27 where cmd:      // Cmd+-
            applyKeyboardZoom(factor: 1.0 / 1.25)
            return true

        case 29 where cmd:      // Cmd+0
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                zoomScale = 1.0
                panOffset = .zero
            }
            return true

        case 123:               // left arrow
            if atFit { navigate(-1) }
            else { withAnimation(.interactiveSpring()) { panOffset.width += 60 } }
            return true

        case 124:               // right arrow
            if atFit { navigate(+1) }
            else { withAnimation(.interactiveSpring()) { panOffset.width -= 60 } }
            return true

        case 125:
            withAnimation(.interactiveSpring()) { panOffset.height -= 60 }
            return true

        case 126:
            withAnimation(.interactiveSpring()) { panOffset.height += 60 }
            return true

        case 51 where cmd:  // Cmd+Delete — trash current image
            let url = imageURLs[selectedIndex]
            deleteImage(at: url)
            if imageURLs.isEmpty { viewMode = .gallery }
            return true

        case 53:            // Escape — stop slideshow and back to gallery
            returnToGallery()
            return true

        case 1 where cmd:   // Cmd+S — back to gallery and focus search
            focusSearchOnGalleryReturn = true
            viewMode = .gallery
            return true

        default:
            return false
        }
    }

    private func applyKeyboardZoom(factor: CGFloat) {
        let anchor = cursorInViewCenter()
        withAnimation(.interactiveSpring()) {
            applyZoom(factor: factor, anchor: anchor)
        }
    }

    func applyZoom(factor: CGFloat, anchor: CGSize) {
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

    // MARK: - Navigation

    func navigate(_ delta: Int, keyboard: Bool = false) {
        let newIdx = max(0, min(imageURLs.count - 1, selectedIndex + delta))
        keyboardNavigated = keyboard
        selectedIndex = newIdx
    }

    func enterFullImage() {
        NSApp.activate(ignoringOtherApps: true)
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
        slideshowTask?.cancel()
        slideshowTask = nil
        slideshowActive = false
        isSlideshowTransition = false
        keyboardNavigated = false
        needsScrollToSelected = true
        // Cancel any in-flight Ken Burns animation — snap zoom immediately
        var snap = Transaction()
        snap.disablesAnimations = true
        withTransaction(snap) {
            zoomScale = 1.0
            panOffset = .zero
        }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            viewMode = .gallery
        }
    }

    // MARK: - Image dimension prefetch (masonry layout stability)

    func prefetchDimensions(for urls: [URL]) {
        let known = Set(imageDimensions.keys)
        let todo = urls.filter { !known.contains($0) }
        guard !todo.isEmpty else { return }
        // Outer Task is @MainActor so 'self' is only ever accessed from the main actor.
        // Each batch is read by an inner detached task that captures only the URL slice
        // (a value type) — 'self' never appears in a concurrent closure, fixing the
        // captured-var warning that arose from the previous Task.detached { [weak self] } pattern.
        Task { @MainActor [weak self] in
            let batchSize = 100
            var start = 0
            while start < todo.count {
                guard self != nil else { return }
                let end = min(start + batchSize, todo.count)
                let slice = Array(todo[start..<end])
                start = end
                let dims = await Task.detached(priority: .utility) {
                    var result: [URL: CGSize] = [:]
                    for url in slice {
                        if let size = AppState.readImageDimensions(url) {
                            result[url] = size
                        }
                    }
                    return result
                }.value
                self?.imageDimensions.merge(dims) { _, new in new }
            }
        }
    }

    private static func readImageDimensions(_ url: URL) -> CGSize? {
        let opts = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let src = CGImageSourceCreateWithURL(url as CFURL, opts),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int,
              w > 0, h > 0 else { return nil }
        return CGSize(width: w, height: h)
    }

    // MARK: - Sort (off main thread)

    private static func sortAndCache(_ urls: [URL], by option: SortOption) -> ([URL], [URL: Date], [URL: Int]) {
        var dateCache: [URL: Date] = [:]
        var sizeCache: [URL: Int]  = [:]

        if option == .newestFirst || option == .oldestFirst {
            for url in urls {
                if let vals = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
                   let date = vals.contentModificationDate {
                    dateCache[url] = date
                }
            }
        }

        if option == .largestFirst || option == .smallestFirst {
            for url in urls {
                if let vals = try? url.resourceValues(forKeys: [.fileSizeKey]),
                   let size = vals.fileSize {
                    sizeCache[url] = size
                }
            }
        }

        return (sort(urls, by: option, dateCache: dateCache, sizeCache: sizeCache), dateCache, sizeCache)
    }

    private static func sort(_ urls: [URL], by option: SortOption,
                             dateCache: [URL: Date], sizeCache: [URL: Int] = [:]) -> [URL] {
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
            return urls.sorted {
                let d0 = dateCache[$0] ?? .distantPast
                let d1 = dateCache[$1] ?? .distantPast
                return option == .newestFirst ? d0 > d1 : d0 < d1
            }
        case .largestFirst, .smallestFirst:
            let pairs: [(URL, Int)] = urls.compactMap { url in
                guard let size = sizeCache[url] else { return nil }
                return (url, size)
            }
            let sorted = pairs.sorted { option == .largestFirst ? $0.1 > $1.1 : $0.1 < $1.1 }
            let withSizes    = sorted.map(\.0)
            let withSizesSet = Set(withSizes)
            let withoutSizes = urls.filter { !withSizesSet.contains($0) }
            return withSizes + withoutSizes
        }
    }
}
