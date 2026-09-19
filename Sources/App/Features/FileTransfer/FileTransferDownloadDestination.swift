// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2020 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
import os

extension FileTransferStore {
	var downloadDestinationURL: URL? {
		customDownloadDestinationURL ?? defaultDownloadDestinationURL
	}

	var hasCustomDownloadDestination: Bool {
		customDownloadDestinationURL != nil
	}

	func startUsingDownloadDestinationURL() {
		let bookmark = SettingsKeys.FileTransfers.downloadFolderBookmark.value
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
		customDownloadDestinationURL?.stopAccessingSecurityScopedResource()
		customDownloadDestinationURL = resolvedURL
	}

	func setDownloadDestinationURL(_ bookmark: Data?) {
		customDownloadDestinationURL?.stopAccessingSecurityScopedResource()
		customDownloadDestinationURL = nil
		if let bookmark {
			SettingsKeys.FileTransfers.downloadFolderBookmark.value = bookmark
		} else {
			SettingsKeys.FileTransfers.downloadFolderBookmark.reset()
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
