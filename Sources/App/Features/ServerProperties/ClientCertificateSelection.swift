/* *********************************************************************
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation
import Security

/// Owns the asynchronous stages of one certificate choice. Closing, resetting
/// or replacing the choice invalidates results even if Security finishes late.
@MainActor
final class ClientCertificateSelection {
	private var generation = UUID()
	private(set) var task: Task<Void, Never>?
	private(set) var isResolvingReference = false

	isolated deinit { task?.cancel() }

	func cancel() {
		generation = UUID()
		task?.cancel()
		task = nil
		isResolvingReference = false
	}

	func chooseIdentities(
		using load: @escaping @Sendable () async -> sending [SecIdentity] = { await ClientCertificateLoader.identities() },
		present: @escaping ([SecIdentity]) -> Void
	) {
		cancel()
		let request = generation
		task = Task { [weak self] in
			let identities = await load()
			guard !Task.isCancelled, let self, generation == request else { return }
			task = nil
			present(identities)
		}
	}

	func resolveReference(
		using load: @escaping @Sendable () async -> Data?,
		apply: @escaping (Data) -> Void
	) {
		cancel()
		let request = generation
		isResolvingReference = true
		task = Task { [weak self] in
			let reference = await load()
			guard !Task.isCancelled, let self, generation == request else { return }
			task = nil
			isResolvingReference = false
			if let reference {
				apply(reference)
			}
		}
	}
}
