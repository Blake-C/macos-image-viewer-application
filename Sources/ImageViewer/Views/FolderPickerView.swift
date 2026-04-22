import SwiftUI
import AppKit

struct FolderPickerView: View {
	@EnvironmentObject var state: AppState

	var body: some View {
		ZStack {
			Color.black.ignoresSafeArea()

			if state.authFailed, let folder = state.pendingAuthFolder {
				authLockedView(folderName: folder.lastPathComponent)
			} else {
				pickerContent
			}
		}
	}

	private var pickerContent: some View {
		VStack(spacing: 24) {
			Image(systemName: state.noImagesFound ? "photo.on.rectangle.angled" : "folder.badge.plus")
				.font(.system(size: 72))
				.foregroundStyle(.secondary)

			if state.noImagesFound {
				Text("No images found in that folder")
					.font(.title2)
					.foregroundStyle(.secondary)
				Text("Supported formats: JPG, PNG, GIF, HEIC, TIFF, BMP, WebP")
					.font(.caption)
					.foregroundStyle(.tertiary)
			}

			Button {
				state.requestOpenFolder()
			} label: {
				Label("Open Folder…", systemImage: "folder")
					.font(.title3)
					.padding(.horizontal, 8)
					.padding(.vertical, 4)
			}
			.buttonStyle(.borderedProminent)
			.controlSize(.large)
		}
	}

	@ViewBuilder
	private func authLockedView(folderName: String) -> some View {
		VStack(spacing: 20) {
			Image(systemName: "lock.circle.fill")
				.font(.system(size: 72))
				.foregroundStyle(.secondary)

			VStack(spacing: 6) {
				Text("Authentication Required")
					.font(.title2)
					.foregroundStyle(.secondary)
				Text("\"\(folderName)\" is protected with Touch ID.")
					.font(.callout)
					.foregroundStyle(.tertiary)
					.multilineTextAlignment(.center)
			}

			HStack(spacing: 12) {
				Button {
					state.retryAuthRequested = true
				} label: {
					Label(
						"Try Again",
						systemImage: FolderLockManager.shared.biometricsAvailable ? "touchid" : "lock.open"
					)
					.font(.title3)
					.padding(.horizontal, 8)
					.padding(.vertical, 4)
				}
				.buttonStyle(.borderedProminent)
				.controlSize(.large)

				Button {
					state.authFailed = false
					state.pendingAuthFolder = nil
					state.requestOpenFolder()
				} label: {
					Label("Open Different Folder…", systemImage: "folder")
						.font(.title3)
						.padding(.horizontal, 8)
						.padding(.vertical, 4)
				}
				.buttonStyle(.bordered)
				.controlSize(.large)
			}
		}
		.padding(32)
	}
}
