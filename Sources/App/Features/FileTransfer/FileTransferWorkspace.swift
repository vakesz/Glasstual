// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import Foundation
import os

/// Opens and reveals transferred files while holding their sandbox access.
@MainActor
final class FileTransferWorkspace {
	private(set) var openTasks: [UUID: Task<Void, Never>] = [:]
	private let openFile: @MainActor (URL) async throws -> Void
	private let acquireAccess: @MainActor (URL) -> FileTransferAccessLease

	init(
		openFile: @escaping @MainActor (URL) async throws -> Void = {
			_ = try await NSWorkspace.shared.open($0, configuration: .init())
		},
		acquireAccess: @escaping @MainActor (URL) -> FileTransferAccessLease = { FileTransferAccessLease(url: $0) }
	) {
		self.openFile = openFile
		self.acquireAccess = acquireAccess
	}

	isolated deinit {
		cancelPendingWork()
	}

	func cancelPendingWork() {
		for task in openTasks.values {
			task.cancel()
		}

		openTasks.removeAll()
	}

	func open(_ files: [FileTransferLocalFile]) {
		for file in files {
			let identifier = UUID()
			let lease = acquireAccess(file.accessURL)
			openTasks[identifier] = Task { [weak self, openFile, lease] in
				defer {
					// LaunchServices may finish after cancellation. Its access must last until this return.
					withExtendedLifetime(lease) {}
					self?.openTasks[identifier] = nil
				}
				guard !Task.isCancelled else { return }
				do {
					try await openFile(file.url)
				} catch is CancellationError {
					// Cancellation ends the request without reporting an opening failure.
				} catch {
					guard !Task.isCancelled else { return }
					fileTransferLogger.error("Could not open transferred file: \(error.localizedDescription, privacy: .public)")
				}
			}
		}
	}

	func reveal(_ files: [FileTransferLocalFile]) {
		guard files.isEmpty == false else { return }

		let leases = files.map { acquireAccess($0.accessURL) }

		withExtendedLifetime(leases) {
			NSWorkspace.shared.activateFileViewerSelecting(files.map(\.url))
		}
	}
}
