// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import CocoaExtensions
import Foundation
import Observation
import os
import Synchronization

struct ThemeAppearanceChanged: SubjectMessage {
	typealias Subject = ThemeStore

	nonisolated static let name = Notification.Name("Glasstual.themeAppearanceChanged")

	let subject: ThemeStore
}

struct ThemeWasModified: SubjectMessage {
	typealias Subject = ThemeStore

	nonisolated static let name = Notification.Name("Glasstual.themeWasModified")

	let subject: ThemeStore
}

/// The immutable theme values message rendering may read away from the main
/// actor. The controller republishes the whole value after each edit.
nonisolated struct ThemeSnapshot: Sendable, Equatable {
	let transcript: TranscriptTheme
	let isDarkAppearance: Bool
	/// Whether the reader has asked the system for increased contrast, which
	/// picks the stronger half of every colour role.
	let increasesContrast: Bool
	/// The system colours resolved for this appearance, which the roles that
	/// follow a system colour draw.
	var systemColors: TranscriptSystemColors = .unresolved

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

	/// Publishes `snapshot` for the next render away from the main actor.
	static func publish(_ snapshot: ThemeSnapshot) {
		published.withLock { $0 = snapshot }
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

	/// The theme with the appearance and contrast its colours resolve
	/// against. It is the store's one observed value: a view that reads a
	/// resolved colour redraws when the theme, the appearance or the contrast
	/// moves, and only then.
	private(set) var snapshot = ThemeSnapshot(
		transcript: .lines,
		isDarkAppearance: false,
		increasesContrast: false
	)

	private let stores: SettingsStores
	private let readAppearance: @MainActor () -> ThemeAppearance
	private let notifications = NotificationSubscriptions()

	var theme: TranscriptTheme {
		snapshot.transcript
	}

	var name: String {
		theme.name
	}

	var font: NSFont {
		resolvedFont(size: theme.fontSize)
	}

	/// The theme's font at `scale` times its point size.
	func scaledFont(scale: CGFloat) -> NSFont {
		resolvedFont(size: theme.fontSize * scale)
	}

	/// Resolving a font by name is a lookup in the system's font catalogue, and
	/// every attribute run of every line asks for one. The cache is keyed by
	/// name and size, so a theme or scale change reaches a new key and the old
	/// entries only age out when the table is cleared at its small bound.
	private func resolvedFont(size: CGFloat) -> NSFont {
		let key = FontKey(name: theme.fontName, size: size)
		if let cached = fontCache[key] {
			return cached
		}
		let font = NSFont(name: key.name, size: size) ?? NSFont.systemFont(ofSize: size)
		if fontCache.count >= Self.fontCacheLimit {
			fontCache.removeAll(keepingCapacity: true)
		}
		fontCache[key] = font
		return font
	}

	private struct FontKey: Hashable {
		let name: String
		let size: CGFloat
	}

	private static let fontCacheLimit = 16

	@ObservationIgnored private var fontCache: [FontKey: NSFont] = [:]

	var backgroundColor: NSColor {
		resolved(theme.palette.background)
	}

	/// The ground behind the sidebar and the member list. The columns are
	/// opaque by design and keep the system's label colours for their rows,
	/// which is what the chrome contrast tests hold this ground to.
	var chromeBackground: NSColor {
		resolved(theme.palette.chromeBackground)
	}

	convenience init() {
		self.init(stores: .live)
	}

	init(
		stores: SettingsStores,
		readAppearance: @escaping @MainActor () -> ThemeAppearance = ThemeAppearance.current
	) {
		self.stores = stores
		self.readAppearance = readAppearance

		/* The snapshot carries the appearance the colours off the main actor are
		 resolved against, and the system's own light/dark switch never passes
		 through a setting change, so the appearance notifications are the
		 only thing that says the snapshot has gone stale. */
		notifications.observe(ApplicationAppearanceChanged.self) { [weak self] _ in
			self?.appearanceDidChange()
		}
		notifications.observe(SystemAppearanceChanged.self) { [weak self] _ in
			self?.appearanceDidChange()
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

		/* Choosing another accent or highlight colour in System Settings changes
		 what the system colours resolve to without any appearance switch. */
		notifications.observe(NSColor.systemColorsDidChangeNotification) { [weak self] _ in
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

		ThemeAppearanceChanged(subject: self).post()
	}

	/// Resolves `color` against the published appearance, so a colour drawn
	/// on the main actor agrees with one drawn off it.
	func resolved(_ color: AdaptiveTranscriptColor) -> NSColor {
		color.resolved(
			isDark: snapshot.isDarkAppearance,
			increasesContrast: snapshot.increasesContrast,
			systemColors: snapshot.systemColors
		)
	}

	private func publish(_ newTheme: TranscriptTheme, persist: Bool) {
		publishSnapshot(transcript: newTheme)

		if persist {
			do {
				try stores.set(.data(exportTheme()), for: SettingsKeys.Theme.transcriptTheme)
			} catch {
				Self.logger.error(
					"Failed to store transcript theme: \(error.localizedDescription, privacy: .public)"
				)
			}
		}

		ThemeWasModified(subject: self).post()
	}

	/// Reports whether the snapshot moved, so a caller can skip announcing a
	/// change that is not one.
	@discardableResult
	private func publishSnapshot(transcript: TranscriptTheme? = nil) -> Bool {
		let appearance = readAppearance()
		let next = ThemeSnapshot(
			transcript: transcript ?? theme,
			isDarkAppearance: appearance.isDark,
			increasesContrast: appearance.increasesContrast,
			systemColors: appearance.systemColors
		)

		LiveThemeSnapshot.publish(next)
		/* Compared before it is written: an unchanged write still invalidates
		 every view that reads a resolved colour. */
		guard snapshot != next else {
			return false
		}

		snapshot = next
		return true
	}
}

/// What a theme's colours resolve against besides the theme itself.
struct ThemeAppearance: Equatable, Sendable {
	var isDark: Bool
	var increasesContrast: Bool
	var systemColors: TranscriptSystemColors = .unresolved

	/// The application's resolved appearance, the system's contrast setting
	/// and the system colours they resolve to.
	static func current() -> ThemeAppearance {
		let isDark = AppServices.appearance.properties.isDarkAppearance
		let increasesContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
		return ThemeAppearance(
			isDark: isDark,
			increasesContrast: increasesContrast,
			systemColors: .current(isDark: isDark, increasesContrast: increasesContrast)
		)
	}
}
