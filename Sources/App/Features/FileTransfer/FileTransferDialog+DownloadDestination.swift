/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
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

import Foundation
import os

public extension FileTransferDialog {
	@objc var downloadDestinationURL: URL? {
		downloadDestinationURLPrivate
	}

	@objc func startUsingDownloadDestinationURL() {
		guard let bookmark = TextualUserDefaults.shared().data(
			forKey: FileTransferDialogConstants.bookmarkKey
		) else {
			return
		}

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
			fileTransferDialogLogger
				.error("Error resolving download bookmark: \(error.localizedDescription, privacy: .public)")
			return
		}

		if isStale {
			refreshDownloadDestinationBookmark(for: resolvedURL)
			return
		}

		guard resolvedURL.startAccessingSecurityScopedResource() else {
			fileTransferDialogLogger.error("Failed to access download bookmark")
			return
		}

		downloadDestinationURLPrivate = resolvedURL
	}

	@objc(setDownloadDestinationURL:)
	func setDownloadDestinationURL(_ bookmark: Data?) {
		downloadDestinationURLPrivate?.stopAccessingSecurityScopedResource()
		downloadDestinationURLPrivate = nil
		TextualUserDefaults.shared().set(bookmark, forKey: FileTransferDialogConstants.bookmarkKey)
		startUsingDownloadDestinationURL()
	}

	private func refreshDownloadDestinationBookmark(for resolvedURL: URL) {
		guard resolvedURL.startAccessingSecurityScopedResource() else {
			fileTransferDialogLogger.error("Failed to access stale download bookmark")
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
			fileTransferDialogLogger
				.error("Failed to refresh stale download bookmark: \(error.localizedDescription, privacy: .public)")
		}
	}
}
