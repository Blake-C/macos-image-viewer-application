import SwiftUI
import AppKit

struct FullImageView: View {
    @EnvironmentObject var state: AppState

    @State private var fullImage: NSImage?
    @State private var isLoading = true
    @State private var dragLive: CGSize = .zero
    @State private var imageInfo: ImageInfo? = nil

    var currentURL: URL { state.imageURLs[state.selectedIndex] }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if isLoading {
                ProgressView()
                    .scaleEffect(1.5)
            } else if let img = fullImage {
                GeometryReader { geo in
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .scaleEffect(state.zoomScale)
                        .offset(
                            x: state.panOffset.width + dragLive.width,
                            y: state.panOffset.height + dragLive.height
                        )
                        .allowsHitTesting(false)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .onAppear {
                            state.fullImageViewSize = geo.size
                        }
                        .onChange(of: geo.size) { _, size in
                            state.fullImageViewSize = size
                        }
                }
            } else {
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
                    state.panOffset.width  += offset.width
                    state.panOffset.height += offset.height
                    dragLive = .zero
                },
                onTap: { state.handleTapInFullImage() }
            )

            // Nav arrows
            NavArrow(direction: .prev)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .allowsHitTesting(true)

            NavArrow(direction: .next)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                .allowsHitTesting(true)

            // Top-right controls: star + info toggle
            VStack {
                HStack(spacing: 8) {
                    Spacer()

                    // Favorites toggle
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

                    // Info overlay toggle
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
                }
                .padding(.top, 12)
                .padding(.trailing, 12)

                Spacer()
            }
            .allowsHitTesting(true)
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
        .animation(.easeInOut(duration: 0.2), value: state.showInfoOverlay)
        .animation(.easeInOut(duration: 0.2), value: state.slideshowActive)
        .ignoresSafeArea()
        .task(id: currentURL) {
            isLoading = true
            state.zoomScale = 1.0
            state.panOffset = .zero
            dragLive = .zero
            imageInfo = nil

            async let img       = ImageLoader.fullImage(for: currentURL)
            async let info      = ImageInfo.load(for: currentURL)
            async let pixelSize = ImageLoader.pixelSize(for: currentURL)

            let (loadedImg, loadedInfo, loadedPixelSize) = await (img, info, pixelSize)

            fullImage = loadedImg
            imageInfo = loadedInfo
            state.currentImagePixelSize = loadedPixelSize
            isLoading = false
        }
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
