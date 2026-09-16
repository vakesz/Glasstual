/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2020 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *  * Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *  * Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *  * Neither the name of Textual, "Codeux Software, LLC", nor the
 *    names of its contributors may be used to endorse or promote products
 *    derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 *********************************************************************** */

import AppKit
import Foundation
import os

extension FileTransferCenter {
	var downloadDestinationURL: URL? {
		downloadDestinationURLPrivate
	}

	func startUsingDownloadDestinationURL() {
		let bookmark = Preferences.FileTransfers.downloadFolderBookmark.value
		guard bookmark.isEmpty == false else { return }

		var isStale = false
		let resolvedURL: URL

		do {
			resolvedURL = try URL(
				resolvingBookmarkData: bookmark,
				options: .withSecurityScope,
				relativeTo: nil,
				bookmarkDataIsStale: &isStale
			)
		} catch {
			let reason = error.localizedDescription
			fileTransferLogger.error("Error resolving download bookmark: \(reason, privacy: .public)")
			return
		}

		if isStale {
			refreshDownloadDestinationBookmark(for: resolvedURL)
			return
		}

		guard resolvedURL.startAccessingSecurityScopedResource() else {
			fileTransferLogger.error("Failed to access download bookmark")
			return
		}

		/* Resolving again while a scope is already held would strand it: the
		 URL it belongs to is about to be the only reference dropped. */
		downloadDestinationURLPrivate?.stopAccessingSecurityScopedResource()
		downloadDestinationURLPrivate = resolvedURL
	}

	func setDownloadDestinationURL(_ bookmark: Data?) {
		downloadDestinationURLPrivate?.stopAccessingSecurityScopedResource()
		downloadDestinationURLPrivate = nil
		if let bookmark {
			Preferences.FileTransfers.downloadFolderBookmark.value = bookmark
		} else {
			Preferences.FileTransfers.downloadFolderBookmark.reset()
		}
		startUsingDownloadDestinationURL()
	}

	private func refreshDownloadDestinationBookmark(for resolvedURL: URL) {
		guard resolvedURL.startAccessingSecurityScopedResource() else {
			fileTransferLogger.error("Failed to access stale download bookmark")
			return
		}

		defer { resolvedURL.stopAccessingSecurityScopedResource() }

		do {
			let refreshed = try resolvedURL.bookmarkData(
				options: .withSecurityScope,
				includingResourceValuesForKeys: nil,
				relativeTo: nil
			)
			setDownloadDestinationURL(refreshed)
		} catch {
			let reason = error.localizedDescription
			fileTransferLogger.error("Failed to refresh stale download bookmark: \(reason, privacy: .public)")
		}
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
