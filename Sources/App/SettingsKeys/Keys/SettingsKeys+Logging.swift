// Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

nonisolated extension SettingsKeys {
	/// Transcript logging and the scrollback the transcript keeps.
	enum Logging {
		private static let group = "Logging -> "

		static let logToDisk = SettingsKey(group + "Log To Disk", default: false)
		static let logHighlights = SettingsKey(group + "Log Highlights", default: true)
		static let reloadScrollbackOnLaunch = SettingsKey(
			group + "Reload Scrollback On Launch",
			default: true
		)
		static let loadHistoryLazily = SettingsKey(group + "Load History Lazily", default: true)

		/// How many lines a conversation keeps on disk. The bounds are the ones the
		/// field has always enforced, declared here so an import obeys them too.
		static let scrollbackSaveRange: ClosedRange<UInt> = 100 ... 50000

		/// How many lines the transcript draws, where zero means "no limit".
		static let scrollbackVisibleRange: ClosedRange<UInt> = 100 ... 15000

		static let scrollbackSaveLimit = SettingsKey(
			group + "Scrollback Save Limit",
			default: UInt(15000),
			validation: { Self.scrollbackSaveRange.contains($0) }
		)

		static let scrollbackVisibleLimit = SettingsKey(
			group + "Scrollback Visible Limit",
			default: UInt(0),
			validation: { $0 == 0 || Self.scrollbackVisibleRange.contains($0) }
		)

		/// A security-scoped bookmark for the folder the user picked; useless in
		/// another user account, so it never leaves this one.
		static let transcriptFolderBookmark = SettingsKey(
			group + "Transcript Folder Bookmark",
			default: Data(),
			traits: [.unregistered, .excludedFromExport]
		)

		/// The name of the database this installation minted, so the same file is
		/// reopened on the next launch. A database written by any other schema is
		/// never named here, so it is left where it is and never opened.
		static let scrollbackDatabaseFileName = SettingsKey(
			group + "Scrollback Database File Name",
			default: "",
			traits: [.unregistered, .excludedFromExport]
		)

		static let all: [any AnySettingsKey] = [
			logToDisk, logHighlights, reloadScrollbackOnLaunch, loadHistoryLazily,
			scrollbackSaveLimit, scrollbackVisibleLimit, transcriptFolderBookmark,
			scrollbackDatabaseFileName,
		]
	}
}
