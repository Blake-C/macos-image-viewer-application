import SwiftUI
import AppKit

struct FullImageView: View {
    @EnvironmentObject var state: AppState

    @State private var fullImage: NSImage?
    @State private var isLoading = true
    @State private var dragLive: CGSize = .zero

    var currentURL: URL { state.imageURLs[state.selectedIndex] }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if isLoading {
                ProgressView()
                    .scaleEffect(1.5)
            } else if let img = fullImage {
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

            // Native mouse handler covers full window — reliable tap vs drag
            MouseEventHandler(
                onDragLive: { offset in
                    dragLive = offset
                },
                onDragEnd: { offset in
                    state.panOffset.width  += offset.width
                    state.panOffset.height += offset.height
                    dragLive = .zero
                },
                onTap: {
                    state.handleTapInFullImage()
                }
            )

        }
        .overlay(alignment: .leading)  { NavArrow(direction: .prev) }
        .overlay(alignment: .trailing) { NavArrow(direction: .next) }
        .ignoresSafeArea()
        .task(id: currentURL) {
            isLoading = true
            state.zoomScale = 1.0
            state.panOffset = .zero
            dragLive = .zero
            fullImage = await ImageLoader.fullImage(for: currentURL)
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
        v.onDragEnd = onDragEnd
        v.onTap = onTap
        return v
    }

    func updateNSView(_ nsView: MouseNSView, context: Context) {
        nsView.onDragLive = onDragLive
        nsView.onDragEnd = onDragEnd
        nsView.onTap = onTap
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
            let dy = -(loc.y - start.y) // flip: AppKit Y is bottom-up, SwiftUI top-down
            if !isDragging && sqrt(dx * dx + dy * dy) > 4 {
                isDragging = true
            }
            if isDragging {
                onDragLive?(CGSize(width: dx, height: dy))
            }
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
