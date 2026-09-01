/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
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

private let preferencesActionsLogger = Logger(
	subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
	category: "PreferencesActions"
)

/// Presentation intent and the resulting domain updates for Settings. SwiftUI
/// presents each request; this model validates and applies the selected value.
extension PreferencesPaneModel {
	// MARK: - Style

	func importTranscriptTheme() {
		importRequest = .transcriptTheme
	}

	func exportTranscriptTheme() {
		do {
			exportedThemeData = try SharedApplication.sharedThemeController().exportTheme()
			exportedThemeFilename = "\(SharedApplication.sharedThemeController().name).plist"
		} catch {
			present(error)
		}
	}

	func resetTranscriptTheme() {
		SharedApplication.sharedThemeController().reset()
		refreshTheme()
		refreshChannelViewFont()
	}

	func selectChannelViewFont() {
		showsFontPicker = true
	}

	func applyChannelViewFont(name: String, size: CGFloat) {
		updateTheme {
			$0.fontName = name
			$0.fontSize = size
		}
		refreshChannelViewFont()
	}

	// MARK: - Folders

	func selectTranscriptFolder() {
		importRequest = .transcriptFolder
	}

	func clearTranscriptFolder() {
		setTranscriptFolder(nil)
	}

	func selectDownloadFolder() {
		importRequest = .downloadFolder
	}

	func clearDownloadFolder() {
		SharedApplication.sharedFileTransferCenter().setDownloadDestinationURL(nil)
		refreshFolders()
	}

	func completeImport(_ result: Result<URL, any Error>) {
		guard let request = importRequest else { return }
		importRequest = nil

		do {
			let url = try result.get()
			let accessWasGranted = url.startAccessingSecurityScopedResource()
			defer {
				if accessWasGranted {
					url.stopAccessingSecurityScopedResource()
				}
			}

			switch request {
			case .transcriptTheme:
				try SharedApplication.sharedThemeController().importTheme(from: Data(contentsOf: url))
				refreshTheme()
				refreshChannelViewFont()
			case .transcriptFolder:
				try setTranscriptFolder(securityScopedBookmark(for: url))
			case .downloadFolder:
				try SharedApplication.sharedFileTransferCenter().setDownloadDestinationURL(
					securityScopedBookmark(for: url)
				)
				refreshFolders()
			}
		} catch {
			guard (error as NSError).code != NSUserCancelledError else { return }
			present(error)
		}
	}

	func completeExport(_ result: Result<URL, any Error>) {
		exportedThemeData = nil
		if case let .failure(error) = result,
		   (error as NSError).code != NSUserCancelledError
		{
			present(error)
		}
	}

	private func setTranscriptFolder(_ bookmark: Data?) {
		PathInfo.setTranscriptFolderURL(bookmark)
		TextualPreferences.performReloadAction(.logTranscripts)
		refreshFolders()
	}

	private func securityScopedBookmark(for url: URL) throws -> Data {
		do {
			return try url.bookmarkData(
				options: .withSecurityScope,
				includingResourceValuesForKeys: nil,
				relativeTo: nil
			)
		} catch {
			preferencesActionsLogger.error(
				"Failed to retain access to the chosen folder: \(error.localizedDescription, privacy: .public)"
			)
			throw error
		}
	}

	func openCustomAddOnsFolder() {
		let scriptsURL = SharedApplication.sharedPluginManager().customScriptsURL
		if let scriptsURL,
		   FileManager.default.fileExists(atPath: scriptsURL.path)
		{
			externalURL = scriptsURL
		} else {
			/* A sandboxed app may read its Application Scripts directory but may
			 not create it. Finder gives the user the right place to create the
			 bundle-ID folder named in the pane's installation note. */
			externalURL = scriptsURL?.deletingLastPathComponent()
		}
	}

	private func present(_ error: any Error) {
		presentationError = error.localizedDescription
	}
}
