import SwiftUI

struct FolderSettingsSheet: View {
	@EnvironmentObject var state: AppState
	@Environment(\.dismiss) private var dismiss
	@State private var isDisablingLock = false

	var body: some View {
		VStack(alignment: .leading, spacing: 0) {
			HStack {
				Label("Folder Settings", systemImage: "gearshape")
					.font(.headline)
				Spacer()
				Button { dismiss() } label: {
					Image(systemName: "xmark.circle.fill")
						.foregroundStyle(.secondary)
						.font(.system(size: 18))
				}
				.buttonStyle(.plain)
			}
			.padding(16)

			Divider()

			VStack(alignment: .leading, spacing: 14) {
				Text("Security")
					.font(.caption)
					.foregroundStyle(.secondary)
					.textCase(.uppercase)

				HStack(alignment: .top, spacing: 12) {
					VStack(alignment: .leading, spacing: 4) {
						Text("Require Touch ID")
							.font(.system(size: 13, weight: .medium))
						Text(
							state.currentFolderIsLocked
								? "Touch ID or your login password is required each time this folder is opened."
								: "Lock this folder so it requires Touch ID or your login password to open."
						)
						.font(.caption)
						.foregroundStyle(.secondary)
						.fixedSize(horizontal: false, vertical: true)
					}

					Spacer(minLength: 16)

					Toggle("", isOn: Binding(
						get: { state.currentFolderIsLocked },
						set: { newValue in
							if newValue {
								state.enableLockForCurrentFolder()
							} else {
								isDisablingLock = true
								Task {
									_ = await state.disableLockForCurrentFolder()
									await MainActor.run { isDisablingLock = false }
								}
							}
						}
					))
					.labelsHidden()
					.disabled(isDisablingLock)
				}

				if !FolderLockManager.shared.biometricsAvailable {
					Label(
						"Touch ID is not available. Your login password will be used as a fallback.",
						systemImage: "exclamationmark.triangle.fill"
					)
					.font(.caption)
					.foregroundStyle(.orange)
					.fixedSize(horizontal: false, vertical: true)
				}
			}
			.padding(16)

			Divider()

			VStack(alignment: .leading, spacing: 14) {
				Text("Scanning")
					.font(.caption)
					.foregroundStyle(.secondary)
					.textCase(.uppercase)

				HStack(alignment: .top, spacing: 12) {
					VStack(alignment: .leading, spacing: 4) {
						Text("Include Subfolders")
							.font(.system(size: 13, weight: .medium))
						Text("Scan all nested subfolders for images, not just the top-level folder.")
							.font(.caption)
							.foregroundStyle(.secondary)
							.fixedSize(horizontal: false, vertical: true)
					}

					Spacer(minLength: 16)

					Toggle("", isOn: $state.scanRecursively)
						.labelsHidden()
				}
			}
			.padding(16)

			Spacer(minLength: 0)
		}
		.frame(width: 340)
		.fixedSize(horizontal: false, vertical: true)
		.padding(.bottom, 16)
	}
}
