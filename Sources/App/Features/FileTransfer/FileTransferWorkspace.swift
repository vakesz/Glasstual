/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
import os

/// UI access is independent of the descriptor used for transfer/retry I/O.
struct FileTransferLocalFile {
	let url: URL
	let accessURL: URL

	func withAccess<Value>(_ operation: (URL) throws -> Value) rethrows -> Value {
		let lease = FileTransferAccessLease(url: accessURL)
		return try withExtendedLifetime(lease) { try operation(url) }
	}
}

/// The feature's narrow bridge to Finder and the user's default applications.
///
/// Opening a file is asynchronous — LaunchServices answers once the
/// application has been handed the document — and the security scope has to
/// last that long. So each request is held here rather than detached: the
/// transfer center owns this, and letting it go cancels whatever is still in
/// flight and releases the scopes those requests were holding.
@MainActor
final class FileTransferWorkspace {
	private struct OpenRequest {
		let task: Task<Void, Never>
		/// Held for the request, not for a scope: dropping the request is what
		/// ends the access, which is why nothing here reads it.
		let lease: FileTransferAccessLease
	}

	private var openRequests: [UUID: OpenRequest] = [:]

	isolated deinit {
		cancelPendingWork()
	}

	func cancelPendingWork() {
		for request in openRequests.values {
			request.task.cancel()
		}

		openRequests.removeAll()
	}

	func open(_ files: [FileTransferLocalFile]) {
		for file in files {
			let identifier = UUID()
			let task = Task { [weak self] in
				do {
					_ = try await NSWorkspace.shared.open(file.url, configuration: .init())
				} catch {
					let reason = error.localizedDescription
					fileTransferLogger.error("Could not open transferred file: \(reason, privacy: .public)")
				}

				self?.openRequests[identifier] = nil
			}

			openRequests[identifier] = OpenRequest(
				task: task,
				lease: FileTransferAccessLease(url: file.accessURL)
			)
		}
	}

	func reveal(_ files: [FileTransferLocalFile]) {
		guard files.isEmpty == false else { return }

		let leases = files.map { FileTransferAccessLease(url: $0.accessURL) }

		withExtendedLifetime(leases) {
			NSWorkspace.shared.activateFileViewerSelecting(files.map(\.url))
		}
	}
}
