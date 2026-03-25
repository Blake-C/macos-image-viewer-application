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
                        .frame(width: 20, height: 20)
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
                        .frame(width: 20, height: 20)
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
