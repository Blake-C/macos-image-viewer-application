import SwiftUI

struct GalleryView: View {
    @EnvironmentObject var state: AppState

    private let columns = [GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 8)]

    var body: some View {
        ZStack(alignment: .topTrailing) {
            GeometryReader { geo in
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(Array(state.imageURLs.enumerated()), id: \.element) { i, url in
                                ThumbnailCell(
                                    url: url,
                                    isSelected: state.selectedIndex == i,
                                    squareThumbnails: state.squareThumbnails
                                ) {
                                    // Click: don't trigger scroll, just open image
                                    state.keyboardNavigated = false
                                    state.selectedIndex = i
                                    state.enterFullImage()
                                }
                            }
                        }
                        .padding(12)
                        .padding(.top, 44)
                        .id(state.folderVersion)
                    }
                    .background(Color.black)
                    .onChange(of: state.selectedIndex) { _, newIdx in
                        guard state.keyboardNavigated,
                              state.imageURLs.indices.contains(newIdx) else { return }
                        proxy.scrollTo(state.imageURLs[newIdx])
                    }
                    .onAppear {
                        // Give AppState the real column count based on actual width
                        state.galleryColumnCount = columnCount(for: geo.size.width)
                    }
                    .onChange(of: geo.size.width) { _, w in
                        state.galleryColumnCount = columnCount(for: w)
                    }
                }
            }

            // Toolbar: sort menu + thumbnail toggle
            HStack(spacing: 8) {
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

                // Thumbnail mode toggle
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
                .help(state.squareThumbnails ? "Switch to aspect ratio thumbnails" : "Switch to square thumbnails")
            }
            .padding(.top, 10)
            .padding(.trailing, 12)
        }
    }

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
        // Match the adaptive grid: min 160, spacing 8, padding 12 each side
        let available = width - 24
        return max(1, Int(available / 168))
    }
}
