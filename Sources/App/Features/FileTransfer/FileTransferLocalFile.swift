/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation

/// Each recipient owns an independent scope count, including across retries.
final nonisolated class FileTransferAccessLease: Sendable { // nonisolated: immutable
	let url: URL
	let isAccessing: Bool
	private let stopAccess: @Sendable (URL) -> Void

	init(
		url: URL,
		startAccess: @Sendable (URL) -> Bool = { $0.startAccessingSecurityScopedResource() },
		stopAccess: @escaping @Sendable (URL) -> Void = { $0.stopAccessingSecurityScopedResource() }
	) {
		self.url = url
		self.stopAccess = stopAccess
		isAccessing = startAccess(url)
	}

	deinit {
		if isAccessing {
			stopAccess(url)
		}
	}
}

/// UI access is independent of the descriptor used for transfer/retry I/O.
struct FileTransferLocalFile {
	let url: URL
	let accessURL: URL

	func withAccess<Value>(_ operation: (URL) throws -> Value) rethrows -> Value {
		let lease = FileTransferAccessLease(url: accessURL)
		return try withExtendedLifetime(lease) { try operation(url) }
	}
}
