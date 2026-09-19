// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import CocoaExtensions
import Foundation
import Observation
import os
import Synchronization

extension Notification.Name {
	static let themeAppearanceChanged = Notification.Name("Glasstual.themeAppearanceChanged")
	static let themeWasModified = Notification.Name("Glasstual.themeWasModified")
}

/// The immutable theme values message rendering may read away from the main
/// actor. The controller republishes the whole value after each edit.
nonisolated struct ThemeSnapshot: Sendable, Equatable {
	let transcript: TranscriptTheme
	let isDarkAppearance: Bool
	/// Whether the reader has asked the system for increased contrast, which
	/// picks the stronger half of every colour role.
	let increasesContrast: Bool

	var timestampFormat: String {
		transcript.timestampFormat
	}
}

/** The theme as the paths that draw a line off the main actor see it, kept
 current by `ThemeStore`.

 It is a namespace of its own rather than a pair of members on the controller
 because the controller is a main-actor class with main-actor state, and a
 `nonisolated` accessor on it says nothing true about that class. An `enum`
 around a `let Mutex` of a value is a value, which is all this is. */
nonisolated enum LiveThemeSnapshot {
	private static let published = Mutex(ThemeSnapshot(
		transcript: .lines,
		isDarkAppearance: false,
		increasesContrast: false
	))

	/// The theme and appearance a render should use right now.
	static var current: ThemeSnapshot {
		published.withLock { $0 }
	}

	/// Publishes `snapshot`, reporting whether it moved so a caller can skip
	/// announcing a change that is not one.
	@discardableResult
	static func publish(_ snapshot: ThemeSnapshot) -> Bool {
		published.withLock { published in
			guard published != snapshot else {
				return false
			}

			published = snapshot

			return true
		}
	}
}

/// Owns the native transcript theme. A single Codable value is used for live
/// rendering, settings, and plist import/export.
@MainActor
@Observable
final class ThemeStore {
	private static let logger = Logger(
		subsystem: LogSubsystem.current,
		category: "ThemeStore"
	)

	private(set) var theme = TranscriptTheme.lines
	private let stores: SettingsStores
	private let notifications = NotificationSubscriptions()

	var name: String {
		theme.name
	}

	var font: NSFont {
		NSFont(name: theme.fontName, size: theme.fontSize)
			?? NSFont.systemFont(ofSize: theme.fontSize)
	}

	var backgroundColor: NSColor {
		resolved(theme.palette.background)
	}

	convenience init() {
		self.init(stores: .live)
	}

	init(stores: SettingsStores) {
		self.stores = stores

		/* The snapshot carries the appearance the colours off the main actor are
		 resolved against, and the system's own light/dark switch never passes
		 through a setting change, so the appearance notifications are the
		 only thing that says the snapshot has gone stale. */
		for name in [Notification.Name.applicationAppearanceChanged, .systemAppearanceChanged] {
			notifications.observe(name) { [weak self] _ in
				self?.appearanceDidChange()
			}
		}

		/* Increase Contrast and Differentiate Without Color both change what a
		 line draws as, and neither is an appearance switch or a setting of
		 ours; the workspace's own notification is what says they moved. */
		notifications.observe(
			NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
			center: NSWorkspace.shared.notificationCenter
		) { [weak self] _ in
			self?.appearanceDidChange()
		}
	}

	func reload() {
		let key = SettingsKeys.Theme.transcriptTheme
		let stored = stores.store(for: key).data(forKey: key.name) ?? Data()
		guard stored.isEmpty == false else {
			publish(.lines, persist: false)
			return
		}

		do {
			try publish(TranscriptTheme.decoded(from: stored), persist: false)
		} catch {
			Self.logger.error(
				"Using fallback for unreadable stored transcript theme: \(error.localizedDescription, privacy: .public)"
			)
			publish(.lines, persist: false)
		}
	}

	/// Publishes a theme, or reports that it was rejected so the caller can say
	/// so instead of dropping the edit silently.
	@discardableResult
	func apply(_ newTheme: TranscriptTheme) -> Bool {
		guard newTheme.isValid else {
			Self.logger.error("Rejected a transcript theme with values outside the supported ranges")
			return false
		}

		publish(newTheme, persist: true)
		return true
	}

	func reset(layout: TranscriptThemeLayout? = nil) {
		let layout = layout ?? theme.layout
		apply(layout == .bubbles ? .bubbles : .lines)
	}

	func importTheme(from data: Data) throws {
		/* `decoded(from:)` rejects anything `isValid` would, so `apply` cannot
		 fail here. */
		try apply(TranscriptTheme.decoded(from: data))
	}

	func exportTheme() throws -> Data {
		let encoder = PropertyListEncoder()
		encoder.outputFormat = .xml
		return try encoder.encode(theme)
	}

	/// Republishes the snapshot for the appearance and contrast now in effect,
	/// and says so.
	///
	/// The setting path, the system's own switch and its accessibility
	/// settings all arrive here, and the second of them is not news: a snapshot
	/// that already says what this one would say leaves the transcript alone
	/// rather than redrawing it twice.
	func appearanceDidChange() {
		guard publishSnapshot() else {
			return
		}

		NotificationCenter.default.post(name: .themeAppearanceChanged, object: self)
	}

	func resolved(_ color: AdaptiveTranscriptColor) -> NSColor {
		color.resolved(
			isDark: AppServices.appearance.properties.isDarkAppearance,
			increasesContrast: NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
		)
	}

	private func publish(_ newTheme: TranscriptTheme, persist: Bool) {
		theme = newTheme
		publishSnapshot()

		if persist {
			do {
				try stores.set(.data(exportTheme()), for: SettingsKeys.Theme.transcriptTheme)
			} catch {
				Self.logger.error(
					"Failed to store transcript theme: \(error.localizedDescription, privacy: .public)"
				)
			}
		}

		NotificationCenter.default.post(name: .themeWasModified, object: self)
	}

	/// Reports whether the snapshot moved, so a caller can skip announcing a
	/// change that is not one.
	@discardableResult
	private func publishSnapshot() -> Bool {
		let snapshot = ThemeSnapshot(
			transcript: theme,
			isDarkAppearance: AppServices.appearance.properties.isDarkAppearance,
			increasesContrast: NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
		)

		return LiveThemeSnapshot.publish(snapshot)
	}
}
