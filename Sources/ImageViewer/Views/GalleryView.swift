import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct GalleryView: View {
    @EnvironmentObject var state: AppState

    @State private var isRefreshing      = false
    @State private var showFilterPopover = false
    @State private var showSettings      = false
    @State private var isDragTargeted    = false
    @FocusState private var searchFocused: Bool

    private var gridColumns: [GridItem] {
        let sz = state.thumbnailSize
        return [GridItem(.adaptive(minimum: sz, maximum: sz + 40), spacing: 8)]
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            GeometryReader { geo in
                ScrollViewReader { proxy in
                    ScrollView {
                        if state.masonryLayout {
                            masonryContent(availableWidth: geo.size.width)
                        } else {
                            LazyVGrid(columns: gridColumns, spacing: 8) {
                                ForEach(Array(state.imageURLs.enumerated()), id: \.element) { i, url in
                                    ThumbnailCell(
                                        url: url,
                                        isSelected: state.selectedIndex == i,
                                        isMultiSelected: state.selectedURLs.contains(url),
                                        isFavorite: state.isFavorite(url),
                                        squareThumbnails: state.squareThumbnails,
                                        cellWidth: state.thumbnailSize,
                                        onTap: { state.handleThumbnailTap(url: url, atIndex: i) },
                                        onDelete: { state.deleteImage(at: url) },
                                        onToggleFavorite: { state.toggleFavorite(url) }
                                    )
                                }
                            }
                            .padding(12)
                            .padding(.bottom, state.selectedURLs.isEmpty ? 0 : 56)
                            .id(state.folderVersion)
                        }
                    }
                    .safeAreaInset(edge: .top, spacing: 0) { toolbarOverlay }
                    .background(Color.black)
                    .onChange(of: state.selectedIndex) { _, newIdx in
                        guard state.keyboardNavigated,
                              state.imageURLs.indices.contains(newIdx) else { return }
                        proxy.scrollTo(state.imageURLs[newIdx], anchor: .center)
                    }
                    .onChange(of: state.needsScrollToSelected) { _, needs in
                        guard needs, state.imageURLs.indices.contains(state.selectedIndex) else { return }
                        state.needsScrollToSelected = false
                        let url = state.imageURLs[state.selectedIndex]
                        // Delay past the gallery transition animation (~0.4s spring)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                            withAnimation { proxy.scrollTo(url, anchor: .center) }
                        }
                    }
                    .onAppear {
                        state.galleryColumnCount = columnCount(for: geo.size.width)
                        DispatchQueue.main.async {
                            if state.focusSearchOnGalleryReturn {
                                state.focusSearchOnGalleryReturn = false
                                searchFocused = true
                            } else {
                                searchFocused = false
                            }
                        }
                    }
                    .onChange(of: geo.size.width) { _, w in
                        state.galleryColumnCount = columnCount(for: w)
                    }
                    .onChange(of: state.thumbnailSize) { _, _ in
                        state.galleryColumnCount = columnCount(for: geo.size.width)
                    }
                    .onDrop(of: [.folder, .fileURL], isTargeted: $isDragTargeted) { providers in
                        guard let provider = providers.first else { return false }
                        // Finder exposes dragged items as raw file-URL data, not as URL objects.
                        // loadDataRepresentation is the reliable path for macOS Finder drags.
                        _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                            guard let data,
                                  let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                            var isDir: ObjCBool = false
                            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir),
                                  isDir.boolValue else { return }
                            Task { @MainActor in
                                let images = await FolderScanner.scan(directory: url)
                                await state.loadImages(images, from: url)
                                state.viewMode = .gallery
                            }
                        }
                        return true
                    }
                    .overlay {
                        if isDragTargeted { FolderDropOverlay() }
                    }
                }
            }

            // Multi-select action bar
            if !state.selectedURLs.isEmpty {
                MultiSelectBar()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(2)
            }

        }
        .animation(.easeInOut(duration: 0.2), value: state.selectedURLs.isEmpty)
        .onChange(of: state.focusSearchOnGalleryReturn) { _, focus in
            if focus {
                state.focusSearchOnGalleryReturn = false
                DispatchQueue.main.async { searchFocused = true }
            }
        }
        .onChange(of: state.shouldFocusSearch) { _, focus in
            if focus {
                state.shouldFocusSearch = false
                searchFocused = true
            }
        }
    }

    // MARK: - Toolbar

    private var toolbarOverlay: some View {
        HStack(spacing: 0) {
            // Search field
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 13))
                TextField("Search", text: $state.searchText)
                    .textFieldStyle(.plain)
                    .foregroundStyle(.white)
                    .font(.system(size: 13))
                    .focused($searchFocused)
                    .onExitCommand {
                        if state.searchText.isEmpty {
                            searchFocused = false
                        } else {
                            state.searchText = ""
                        }
                    }
                if !state.searchText.isEmpty {
                    Button { state.searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
            .frame(maxWidth: 220)

            Spacer()

            HStack(spacing: 6) {
                // Filter button (type + date range)
                Button {
                    showFilterPopover = true
                } label: {
                    Image(systemName: state.hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(state.hasActiveFilters ? Color.accentColor : .white)
                        .padding(8)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .help("Filters")
                .popover(isPresented: $showFilterPopover, arrowEdge: .top) {
                    FilterPopover()
                        .environmentObject(state)
                }

                // Favorites toggle
                Button {
                    state.showFavoritesOnly.toggle()
                } label: {
                    Image(systemName: state.showFavoritesOnly ? "star.fill" : "star")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(state.showFavoritesOnly ? .yellow : .white)
                        .padding(8)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .help(state.showFavoritesOnly ? "Show all images" : "Show favorites only")

                // Full-screen
                Button {
                    NSApp.keyWindow?.toggleFullScreen(nil)
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .help("Toggle full screen")

                // Sort menu
                Menu {
                    Section("Name") {
                        sortButton(.nameAZ)
                        sortButton(.nameZA)
                    }
                    Section("Date Modified") {
                        sortButton(.newestFirst)
                        sortButton(.oldestFirst)
                    }
                    Section("File Size") {
                        sortButton(.largestFirst)
                        sortButton(.smallestFirst)
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .help("Sort images")

                // Thumbnail mode toggle (hidden in masonry — always aspect ratio there)
                if !state.masonryLayout {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            state.squareThumbnails.toggle()
                        }
                    } label: {
                        Image(systemName: state.squareThumbnails ? "rectangle.arrowtriangle.2.inward" : "square.grid.2x2")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(8)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .help(state.squareThumbnails ? "Aspect ratio thumbnails" : "Square thumbnails")
                }

                // Masonry layout toggle
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        state.masonryLayout.toggle()
                    }
                } label: {
                    Image(systemName: state.masonryLayout ? "rectangle.3.group.fill" : "rectangle.3.group")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(state.masonryLayout ? Color.accentColor : .white)
                        .padding(8)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .help(state.masonryLayout ? "Switch to grid layout" : "Switch to masonry layout")

                // Thumbnail size slider (grid mode only)
                if !state.masonryLayout {
                    HStack(spacing: 4) {
                        Image(systemName: "photo")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.6))
                        Slider(value: $state.thumbnailSize, in: 100...280, step: 10)
                            .frame(width: 80)
                            .tint(.white.opacity(0.8))
                        Image(systemName: "photo")
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .help("Adjust thumbnail size")
                }

                // Refresh
                Button {
                    guard !isRefreshing else { return }
                    isRefreshing = true
                    Task {
                        await state.refreshCurrentFolder()
                        isRefreshing = false
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                        .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                        .animation(isRefreshing ? .linear(duration: 0.6).repeatForever(autoreverses: false) : .default,
                                   value: isRefreshing)
                        .padding(8)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .help("Refresh folder")

                // Recent folders
                if !state.recentFolders.isEmpty {
                    Menu {
                        ForEach(state.recentFolders, id: \.self) { url in
                            Button {
                                Task { await state.openRecentFolder(url) }
                            } label: {
                                Text(url.lastPathComponent)
                            }
                        }
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(8)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .help("Recent folders")
                }

                // Settings
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: state.currentFolderIsLocked ? "gearshape.fill" : "gearshape")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(state.currentFolderIsLocked ? Color.accentColor : .white)
                        .padding(8)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .help("Folder settings")
                .sheet(isPresented: $showSettings) {
                    FolderSettingsSheet()
                        .environmentObject(state)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
    }

    // MARK: - Masonry layout

    @ViewBuilder
    private func masonryContent(availableWidth: CGFloat) -> some View {
        let spacing: CGFloat = 8
        let numCols = masonryColumnCount(for: availableWidth)
        let colWidth = (availableWidth - 24 - spacing * CGFloat(numCols - 1)) / CGFloat(numCols)
        let distributed = distributeURLs(state.imageURLs, into: numCols)

        HStack(alignment: .top, spacing: spacing) {
            ForEach(0..<numCols, id: \.self) { col in
                LazyVStack(spacing: spacing) {
                    ForEach(Array(distributed[col].enumerated()), id: \.element) { localIdx, url in
                        let globalIdx = col + localIdx * numCols
                        ThumbnailCell(
                            url: url,
                            isSelected: state.selectedIndex == globalIdx,
                            isMultiSelected: state.selectedURLs.contains(url),
                            isFavorite: state.isFavorite(url),
                            squareThumbnails: false,
                            masonry: true,
                            cellWidth: colWidth,
                            onTap: { state.handleThumbnailTap(url: url, atIndex: globalIdx) },
                            onDelete: { state.deleteImage(at: url) },
                            onToggleFavorite: { state.toggleFavorite(url) }
                        )
                    }
                }
            }
        }
        .padding(12)
        .padding(.bottom, state.selectedURLs.isEmpty ? 0 : 56)
        .id(state.folderVersion)
    }

    private func masonryColumnCount(for width: CGFloat) -> Int {
        max(2, Int(width / 360))
    }

    private func distributeURLs(_ urls: [URL], into columns: Int) -> [[URL]] {
        var result = Array(repeating: [URL](), count: columns)
        for (i, url) in urls.enumerated() {
            result[i % columns].append(url)
        }
        return result
    }

    // MARK: - Helpers

    @ViewBuilder
    private func sortButton(_ option: SortOption) -> some View {
        Button {
            state.sortOption = option
        } label: {
            Label(option.rawValue,
                  systemImage: state.sortOption == option ? "checkmark" : option.icon)
        }
    }

    private func columnCount(for width: CGFloat) -> Int {
        let available = width - 24
        return max(1, Int(available / (state.thumbnailSize + 8)))
    }
}

// MARK: - Folder drop overlay

private struct FolderDropOverlay: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12)
        ZStack {
            shape.stroke(Color.accentColor, lineWidth: 3)
            shape.fill(Color.accentColor.opacity(0.08))
            VStack(spacing: 8) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 36))
                    .foregroundStyle(Color.accentColor)
                Text("Drop folder to open")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(8)
        .allowsHitTesting(false)
    }
}

// MARK: - Multi-select action bar

private struct MultiSelectBar: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        HStack(spacing: 16) {
            Text("\(state.selectedURLs.count) selected")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)

            Spacer()

            Button {
                state.copyPathsOfSelected()
            } label: {
                Label("Copy Paths", systemImage: "doc.on.doc")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.8))

            Button {
                Task { await state.moveSelectedToFolder() }
            } label: {
                Label("Move to Folder", systemImage: "folder")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.8))

            Button(role: .destructive) {
                state.trashSelected()
            } label: {
                Label("Move to Trash", systemImage: "trash")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red.opacity(0.9))

            Button {
                state.clearMultiSelect()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.6))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Divider().opacity(0.3)
        }
    }
}

// MARK: - Filter popover

private struct FilterPopover: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            // File type
            VStack(alignment: .leading, spacing: 8) {
                Text("File Type")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        typeChip(nil, label: "All")
                        ForEach(state.availableFileTypes, id: \.self) { ext in
                            typeChip(ext, label: ext.uppercased())
                        }
                    }
                }
            }

            Divider()

            // Date range
            VStack(alignment: .leading, spacing: 8) {
                Text("Date Modified")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                HStack {
                    Text("From")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, alignment: .leading)
                    DatePicker("", selection: Binding(
                        get: { state.filterDateFrom ?? Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? Date() },
                        set: { state.filterDateFrom = $0 }
                    ), displayedComponents: .date)
                    .labelsHidden()
                    if state.filterDateFrom != nil {
                        Button { state.filterDateFrom = nil } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }.buttonStyle(.plain)
                    }
                }

                HStack {
                    Text("To")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, alignment: .leading)
                    DatePicker("", selection: Binding(
                        get: { state.filterDateTo ?? Date() },
                        set: { state.filterDateTo = $0 }
                    ), displayedComponents: .date)
                    .labelsHidden()
                    if state.filterDateTo != nil {
                        Button { state.filterDateTo = nil } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }.buttonStyle(.plain)
                    }
                }
            }

            if state.hasActiveFilters {
                Divider()
                Button("Clear All Filters") { state.clearFilters() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(.red.opacity(0.8))
            }
        }
        .padding(16)
        .frame(width: 280)
    }

    @ViewBuilder
    private func typeChip(_ ext: String?, label: String) -> some View {
        let active = state.filterFileType == ext
        Button {
            state.filterFileType = active ? nil : ext
        } label: {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(active ? Color.accentColor : Color.primary.opacity(0.08),
                            in: Capsule())
                .foregroundStyle(active ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}
