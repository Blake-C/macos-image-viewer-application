import SwiftUI

struct SlideshowControlsOverlay: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        HStack(spacing: 20) {
            // Play / pause
            Button {
                state.toggleSlideshow()
            } label: {
                Image(systemName: state.slideshowActive ? "pause.fill" : "play.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .help(state.slideshowActive ? "Pause slideshow" : "Play slideshow")

            // Interval stepper
            HStack(spacing: 8) {
                Button {
                    state.setSlideshowInterval(state.slideshowInterval - 0.5)
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(state.slideshowInterval <= 0.5)

                Text(String(format: "%.1fs", state.slideshowInterval))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 36, alignment: .center)
                    .monospacedDigit()

                Button {
                    state.setSlideshowInterval(state.slideshowInterval + 0.5)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            // Image counter
            if !state.imageURLs.isEmpty {
                Text("\(state.selectedIndex + 1) / \(state.imageURLs.count)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .monospacedDigit()
            }

            Spacer()

            // Shuffle toggle
            Button {
                state.toggleShuffle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "shuffle")
                        .font(.system(size: 12, weight: .medium))
                    Text("Shuffle")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(state.slideshowShuffle ? Color.accentColor : .white.opacity(0.5))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(state.slideshowShuffle ? Color.accentColor.opacity(0.2) : Color.clear)
                )
            }
            .buttonStyle(.plain)
            .help(state.slideshowShuffle ? "Disable shuffle" : "Enable shuffle")

            // Ken Burns toggle
            Button {
                state.toggleKenBurns()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "camera.filters")
                        .font(.system(size: 12, weight: .medium))
                    Text("Ken Burns")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(state.kenBurnsEnabled ? Color.accentColor : .white.opacity(0.5))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(state.kenBurnsEnabled ? Color.accentColor.opacity(0.2) : Color.clear)
                )
            }
            .buttonStyle(.plain)
            .help(state.kenBurnsEnabled ? "Disable pan & zoom animation" : "Enable pan & zoom animation")

            // Stop
            Button {
                state.toggleSlideshow()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help("Stop slideshow")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.black.opacity(0.65))
        .overlay(alignment: .top) {
            Rectangle().fill(.white.opacity(0.08)).frame(height: 0.5)
        }
    }
}
