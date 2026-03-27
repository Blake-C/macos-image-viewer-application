import SwiftUI
import AppKit

struct FullImageView: View {
    @EnvironmentObject var state: AppState

    @State private var fullImage: NSImage?
    @State private var outgoingImage: NSImage?          // previous image during crossfade
    @State private var outgoingZoom: CGFloat   = 1.0   // captured at transition start
    @State private var outgoingOffset: CGSize  = .zero  // captured at transition start
    @State private var transitionOpacity: Double = 1.0  // 0 = outgoing fully visible, 1 = incoming

    @State private var isLoading  = true
    @State private var dragLive: CGSize = .zero
    @State private var imageInfo: ImageInfo? = nil

    // Ken Burns local state — keeps animation separate from state.zoomScale/panOffset
    // so that flipping kenBurnsActive to false instantly snaps the displayed zoom to fit.
    @State private var kbZoom: CGFloat = 1.0
    @State private var kbPan: CGSize = .zero
    @State private var kenBurnsActive: Bool = false

    var currentURL: URL { state.imageURLs[state.selectedIndex] }

    // Effective zoom/pan accounting for whether Ken Burns owns the transform
    private var effectiveZoom: CGFloat { kenBurnsActive ? kbZoom : state.zoomScale }
    private var effectivePan: CGSize {
        kenBurnsActive ? kbPan : state.panOffset
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // --- Outgoing image (frozen during crossfade) ---
            if let outgoing = outgoingImage {
                Image(nsImage: outgoing)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .scaleEffect(outgoingZoom)
                    .offset(x: outgoingOffset.width, y: outgoingOffset.height)
                    .allowsHitTesting(false)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .opacity(1.0 - transitionOpacity)
            }

            // --- Incoming / current image ---
            if let img = fullImage {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .scaleEffect(effectiveZoom)
                    .offset(
                        x: effectivePan.width  + dragLive.width,
                        y: effectivePan.height + dragLive.height
                    )
                    .allowsHitTesting(false)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .opacity(transitionOpacity)
            } else if isLoading && outgoingImage == nil {
                ProgressView().scaleEffect(1.5)
            } else if outgoingImage == nil {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("Could not load image")
                        .foregroundStyle(.secondary)
                }
                .allowsHitTesting(false)
            }

            // Mouse handler
            MouseEventHandler(
                onDragLive: { offset in dragLive = offset },
                onDragEnd:  { offset in
                    if kenBurnsActive {
                        kbPan.width  += offset.width
                        kbPan.height += offset.height
                    } else {
                        state.panOffset.width  += offset.width
                        state.panOffset.height += offset.height
                    }
                    dragLive = .zero
                },
                onTap: { state.handleTapInFullImage() }
            )

            // Nav arrows
            NavArrow(direction: .prev)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

            NavArrow(direction: .next)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)

            // Top-right buttons: star + info
            VStack {
                HStack(spacing: 8) {
                    Spacer()
                    Button {
                        state.toggleFavorite(currentURL)
                    } label: {
                        Image(systemName: state.isFavorite(currentURL) ? "star.fill" : "star")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(state.isFavorite(currentURL) ? .yellow : .white)
                            .frame(width: 40, height: 40)
                            .background(.ultraThinMaterial.opacity(0.7), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help(state.isFavorite(currentURL) ? "Remove from favorites" : "Add to favorites")

                    Button {
                        state.showInfoOverlay.toggle()
                    } label: {
                        Image(systemName: state.showInfoOverlay ? "info.circle.fill" : "info.circle")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(.ultraThinMaterial.opacity(0.7), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Image info (i)")

                    Button {
                        let url = currentURL
                        state.deleteImage(at: url)
                        if state.imageURLs.isEmpty { state.viewMode = .gallery }
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(.red.opacity(0.9))
                            .frame(width: 40, height: 40)
                            .background(.ultraThinMaterial.opacity(0.7), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Move to Trash (⌘⌫)")
                }
                .padding(.top, 12)
                .padding(.trailing, 12)
                Spacer()
            }
            .zIndex(2)

            // Info overlay (bottom-left)
            if state.showInfoOverlay, let info = imageInfo {
                VStack {
                    Spacer()
                    HStack {
                        InfoOverlayView(info: info)
                        Spacer()
                    }
                }
                .allowsHitTesting(false)
                .zIndex(3)
                .transition(.opacity)
            }

            // Slideshow controls (bottom)
            if state.slideshowActive {
                VStack {
                    Spacer()
                    SlideshowControlsOverlay()
                }
                .zIndex(4)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .contextMenu {
            Button {
                NSWorkspace.shared.open(currentURL)
            } label: {
                Label("Open", systemImage: "arrow.up.right.square")
            }

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([currentURL])
            } label: {
                Label("Show in Finder", systemImage: "folder")
            }

            Divider()

            Button {
                state.toggleFavorite(currentURL)
            } label: {
                Label(state.isFavorite(currentURL) ? "Remove from Favorites" : "Add to Favorites",
                      systemImage: state.isFavorite(currentURL) ? "star.slash" : "star")
            }

            Divider()

            Button {
                Task {
                    if let image = NSImage(contentsOf: currentURL) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.writeObjects([image])
                    }
                }
            } label: {
                Label("Copy Image", systemImage: "doc.on.doc")
            }

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(currentURL.path, forType: .string)
            } label: {
                Label("Copy File Path", systemImage: "link")
            }

            Divider()

            Button {
                if let screen = NSScreen.main {
                    try? NSWorkspace.shared.setDesktopImageURL(currentURL, for: screen, options: [:])
                }
            } label: {
                Label("Set as Wallpaper", systemImage: "photo")
            }

            Divider()

            Button(role: .destructive) {
                let url = currentURL
                state.deleteImage(at: url)
                if state.imageURLs.isEmpty { state.viewMode = .gallery }
            } label: {
                Label("Move to Trash", systemImage: "trash")
            }
        }
        // Capture view size for Ken Burns / zoom-to-pixels calculations
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { state.fullImageViewSize = geo.size }
                    .onChange(of: geo.size) { _, size in state.fullImageViewSize = size }
            }
        )
        .animation(.easeInOut(duration: 0.2), value: state.showInfoOverlay)
        .animation(.easeInOut(duration: 0.2), value: state.slideshowActive)
        .ignoresSafeArea()
        // Stop Ken Burns when slideshow stops
        .onChange(of: state.slideshowActive) { _, active in
            if !active { cancelKenBurns() }
        }
        // Stop Ken Burns when toggled off
        .onChange(of: state.kenBurnsEnabled) { _, enabled in
            if !enabled { cancelKenBurns() }
        }
        .task(id: currentURL) {
            // Consume the transition flag — was this an auto-advance or manual navigation?
            let isCrossfade = state.isSlideshowTransition
            state.isSlideshowTransition = false

            if isCrossfade, let current = fullImage {
                // Freeze the outgoing image at its current effective zoom/offset
                outgoingImage  = current
                outgoingZoom   = effectiveZoom
                outgoingOffset = CGSize(
                    width:  effectivePan.width  + dragLive.width,
                    height: effectivePan.height + dragLive.height
                )
                transitionOpacity = 0.0   // show outgoing while loading
            } else {
                outgoingImage     = nil
                transitionOpacity = 1.0
            }

            isLoading = (outgoingImage == nil)   // show spinner only when no outgoing
            dragLive  = .zero
            imageInfo = nil

            // Stop any previous Ken Burns before loading new image
            kenBurnsActive = false
            kbZoom = 1.0
            kbPan  = .zero

            // Load image, info and pixel size concurrently
            async let img       = ImageLoader.fullImage(for: currentURL)
            async let info      = ImageInfo.load(for: currentURL)
            async let pixelSize = ImageLoader.pixelSize(for: currentURL)
            let (loadedImg, loadedInfo, loadedPixelSize) = await (img, info, pixelSize)

            imageInfo = loadedInfo
            state.currentImagePixelSize = loadedPixelSize

            // --- Ken Burns: set start state before revealing the image ---
            let doKenBurns = state.kenBurnsEnabled && state.slideshowActive
            var kbDuration: Double = 0
            if doKenBurns,
               let ps = loadedPixelSize,
               ps.width > 0, ps.height > 0,
               state.fullImageViewSize.width > 0, state.fullImageViewSize.height > 0 {

                let vw = state.fullImageViewSize.width
                let vh = state.fullImageViewSize.height
                let startZoom: CGFloat = 1.6
                let isPortrait = (ps.width / ps.height) < (vw / vh)
                let startOffset: CGSize = isPortrait
                    ? CGSize(width: 0,  height:  vh * (startZoom - 1) / 2)
                    : CGSize(width: vw * (startZoom - 1) / 2, height: 0)

                // Set local Ken Burns state (not state.zoomScale)
                kbZoom = startZoom
                kbPan  = startOffset
                kenBurnsActive = true
                kbDuration = max(1.0, state.slideshowInterval - 0.3)

                // Reset state zoom to fit so it's ready when Ken Burns ends
                state.zoomScale = 1.0
                state.panOffset = .zero
            } else {
                kenBurnsActive = false
                state.zoomScale = 1.0
                state.panOffset = .zero
            }

            fullImage = loadedImg
            isLoading = false

            // --- Crossfade: fade incoming image in over outgoing ---
            if isCrossfade {
                let fadeDuration = min(0.7, state.slideshowInterval * 0.25)
                withAnimation(.easeInOut(duration: fadeDuration)) {
                    transitionOpacity = 1.0
                }
                // Remove outgoing layer once fade is done
                let cleanupDelay = UInt64((fadeDuration + 0.05) * 1_000_000_000)
                Task { [weak state] in
                    try? await Task.sleep(nanoseconds: cleanupDelay)
                    _ = state   // suppress warning
                    await MainActor.run { outgoingImage = nil }
                }
            }

            // --- Ken Burns: animate local kbZoom/kbPan to fit over the slideshow interval ---
            if doKenBurns && kbDuration > 0 {
                withAnimation(.easeInOut(duration: kbDuration)) {
                    kbZoom = 1.0
                    kbPan  = .zero
                }
            }
        }
    }

    /// Instantly cancels Ken Burns animation and snaps to fit.
    /// Because kenBurnsActive is a Bool (not an animated numeric), flipping it to false
    /// causes an immediate view update that reads state.zoomScale (already 1.0).
    private func cancelKenBurns() {
        kenBurnsActive = false
        kbZoom = 1.0
        kbPan  = .zero
        outgoingImage = nil
        transitionOpacity = 1.0
    }
}

// MARK: - Navigation arrow

enum NavDirection { case prev, next }

struct NavArrow: View {
    @EnvironmentObject var state: AppState
    let direction: NavDirection
    @State private var hovering = false

    var isVisible: Bool {
        direction == .prev
            ? state.selectedIndex > 0
            : state.selectedIndex < state.imageURLs.count - 1
    }

    var body: some View {
        if isVisible {
            Button {
                state.navigate(direction == .prev ? -1 : +1)
            } label: {
                Image(systemName: direction == .prev ? "chevron.left" : "chevron.right")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(.ultraThinMaterial.opacity(hovering ? 1 : 0.55), in: Circle())
                    .scaleEffect(hovering ? 1.1 : 1.0)
            }
            .buttonStyle(.plain)
            .padding(direction == .prev ? .leading : .trailing, 16)
            .animation(.easeOut(duration: 0.15), value: hovering)
            .onHover { hovering = $0 }
        }
    }
}

// MARK: - Native mouse event handler

struct MouseEventHandler: NSViewRepresentable {
    var onDragLive: (CGSize) -> Void
    var onDragEnd: (CGSize) -> Void
    var onTap: () -> Void

    func makeNSView(context: Context) -> MouseNSView {
        let v = MouseNSView()
        v.onDragLive = onDragLive
        v.onDragEnd  = onDragEnd
        v.onTap      = onTap
        return v
    }

    func updateNSView(_ nsView: MouseNSView, context: Context) {
        nsView.onDragLive = onDragLive
        nsView.onDragEnd  = onDragEnd
        nsView.onTap      = onTap
    }

    class MouseNSView: NSView {
        var onDragLive: ((CGSize) -> Void)?
        var onDragEnd: ((CGSize) -> Void)?
        var onTap: (() -> Void)?

        private var mouseDownLocation: NSPoint?
        private var isDragging = false

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .openHand)
        }

        override func mouseDown(with event: NSEvent) {
            mouseDownLocation = event.locationInWindow
            isDragging = false
        }

        override func mouseDragged(with event: NSEvent) {
            guard let start = mouseDownLocation else { return }
            let loc = event.locationInWindow
            let dx = loc.x - start.x
            let dy = -(loc.y - start.y)
            if !isDragging && sqrt(dx * dx + dy * dy) > 4 { isDragging = true }
            if isDragging { onDragLive?(CGSize(width: dx, height: dy)) }
        }

        override func mouseUp(with event: NSEvent) {
            if isDragging {
                guard let start = mouseDownLocation else { return }
                let loc = event.locationInWindow
                let dx = loc.x - start.x
                let dy = -(loc.y - start.y)
                onDragEnd?(CGSize(width: dx, height: dy))
            } else {
                onTap?()
            }
            mouseDownLocation = nil
            isDragging = false
        }
    }
}
