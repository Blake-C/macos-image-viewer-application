import Foundation
import LocalAuthentication

final class FolderLockManager {
	static let shared = FolderLockManager()
	private init() {}

	private let udKey = "lockedFolderPaths"

	var lockedPaths: Set<String> {
		Set(UserDefaults.standard.stringArray(forKey: udKey) ?? [])
	}

	func isLocked(_ url: URL) -> Bool {
		lockedPaths.contains(url.path)
	}

	func lock(_ url: URL) {
		var paths = lockedPaths
		paths.insert(url.path)
		UserDefaults.standard.set(Array(paths), forKey: udKey)
	}

	func unlock(_ url: URL) {
		var paths = lockedPaths
		paths.remove(url.path)
		UserDefaults.standard.set(Array(paths), forKey: udKey)
	}

	var biometricsAvailable: Bool {
		let ctx = LAContext()
		var error: NSError?
		return ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
	}

	func authenticate(for url: URL, reason: String) async -> Bool {
		let context = LAContext()
		var nsError: NSError?
		let policy = LAPolicy.deviceOwnerAuthentication
		guard context.canEvaluatePolicy(policy, error: &nsError) else { return false }
		return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
			context.evaluatePolicy(policy, localizedReason: reason) { success, _ in
				continuation.resume(returning: success)
			}
		}
	}
}
