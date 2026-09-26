// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

/// A connection owns its pending trust decision, including the wait for certificate
/// export. Cancellation refuses trust exactly once and dismisses only this prompt.
@MainActor
final class CertificateTrustRequest {
	typealias Presenter = (SecureConnectionInformation, @escaping (Bool) -> Void) -> (() -> Void)?

	private enum State {
		case waiting(Presenter)
		case presenting
		case visible(dismiss: () -> Void)
		case finished
	}

	private var state: State
	private var decided: ((Bool) -> Void)?

	init(present: @escaping Presenter, decided: @escaping (Bool) -> Void) {
		state = .waiting(present)
		self.decided = decided
	}

	isolated deinit { finish(false) }

	func present(_ information: SecureConnectionInformation) {
		guard case let .waiting(present) = state else { return }
		state = .presenting
		let dismiss = present(information) { [weak self] trusted in
			self?.finish(trusted)
		}
		// A presenter may complete or be cancelled before returning its dismiss action.
		guard case .presenting = state else {
			dismiss?()
			return
		}
		if let dismiss {
			state = .visible(dismiss: dismiss)
		} else {
			finish(false)
		}
	}

	func cancel() {
		finish(false)
	}

	private func finish(_ trusted: Bool) {
		if case .finished = state {
			return
		}
		let previous = state
		state = .finished
		let completion = decided
		decided = nil
		if case let .visible(dismiss) = previous {
			dismiss()
		}
		completion?(trusted)
	}
}
