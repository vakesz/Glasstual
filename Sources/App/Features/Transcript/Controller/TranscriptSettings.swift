// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

/** The settings a printed line is rendered against, read once and kept.

 Reading them from the defaults store for every line cost more than the
 rendering it served, so the store below holds one copy for every transcript in
 every window and refreshes it when a setting it names changes. The
 conversation's own inline-media override is not here: it is in memory already
 and is read live. */
nonisolated struct TranscriptSettings: Sendable, Equatable {
	var textRules = TranscriptTextRules()
	var showsDateChanges = true
	/// The application-wide inline-media setting, which decides which half of a
	/// conversation's override applies.
	var showsInlineMedia = false

	/** Every key `current()` reads.

	 One list, so that the reload mapping and the test that checks it cannot
	 drift from what is actually read. A key added to `current()` and not here
	 would be stale for an in-app write until the catch-all caught up. */
	static let keys: [any AnySettingsKey] = [
		SettingsKeys.Messages.filterUnicodeTextSpam,
		SettingsKeys.Messages.detectHighlightSpam,
		SettingsKeys.Messages.showDateChanges,
		SettingsKeys.Messages.showInlineMedia,
		SettingsKeys.Highlights.matchingMethod,
		SettingsKeys.LinkSchemes.permitAny,
		SettingsKeys.LinkSchemes.permittedDefault,
		SettingsKeys.LinkSchemes.permitted,
	]

	/// The settings as the reader has them right now.
	@MainActor static func current() -> TranscriptSettings {
		TranscriptSettings(
			textRules: .current(),
			showsDateChanges: SettingsKeys.Messages.showDateChanges.value,
			showsInlineMedia: SettingsKeys.Messages.showInlineMedia.value
		)
	}
}

/** The one copy of ``TranscriptSettings``, owned by `AppServices`.

 An in-app write reaches it through `SettingsReload`, which refreshes it ahead
 of every redraw that would read it. A value written another way -- another
 process, the standard domain the link-scheme keys live in -- arrives as a
 defaults notification, which is delivered on a later turn of the main actor. */
@MainActor
final class TranscriptSettingsStore {
	private(set) var current: TranscriptSettings
	private let read: @MainActor () -> TranscriptSettings
	private let notifications = NotificationSubscriptions()

	init(
		read: @escaping @MainActor () -> TranscriptSettings = { .current() },
		center: NotificationCenter = .default
	) {
		self.read = read
		current = read()

		for name in [UserDefaults.didChangeNotification, .userDefaultsDidChange] {
			notifications.observe(name, center: center) { [weak self] _ in
				self?.refresh()
			}
		}
	}

	/// Reads the settings again, and keeps the new value only if it differs.
	func refresh() {
		let updated = read()
		guard updated != current else { return }
		current = updated
	}
}
