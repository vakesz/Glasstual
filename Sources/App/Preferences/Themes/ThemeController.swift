/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import AppKit
import CocoaExtensions
import Foundation
import Observation
import os
import Synchronization

public extension Notification.Name {
	static let themeAppearanceChanged = Notification.Name("NativeTranscriptThemeAppearanceChanged")
	static let themeWasModified = Notification.Name("NativeTranscriptThemeWasModified")
}

/// The immutable theme values message rendering may read away from the main
/// actor. The controller republishes the whole value after each edit.
public nonisolated struct ThemeSnapshot: Sendable, Equatable { // nonisolated: value
	public let transcript: TranscriptTheme
	public let isDarkAppearance: Bool

	public var timestampFormat: String {
		transcript.timestampFormat
	}
}

/** The theme as the paths that draw a line off the main actor see it, kept
 current by `ThemeController`.

 It is a namespace of its own rather than a pair of members on the controller
 because the controller is a main-actor class with main-actor state, and a
 `nonisolated` accessor on it says nothing true about that class. An `enum`
 around a `let Mutex` of a value is a value, which is all this is. */
public nonisolated enum ThemeSnapshotStore { // nonisolated: value
	private static let published = Mutex(ThemeSnapshot(
		transcript: .lines,
		isDarkAppearance: false
	))

	/// The theme and appearance a render should use right now.
	public static var current: ThemeSnapshot {
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
/// rendering, preferences, and plist import/export.
@MainActor
@Observable
public final class ThemeController: NSObject {
	private static let logger = Logger(
		subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
		category: "TranscriptTheme"
	)

	public private(set) var theme = TranscriptTheme.lines
	private let stores: PreferencesTransferStores
	private let notifications = NotificationSubscriptions()

	public var name: String {
		theme.name
	}

	public var font: NSFont {
		NSFont(name: theme.fontName, size: theme.fontSize)
			?? NSFont.systemFont(ofSize: theme.fontSize)
	}

	public var backgroundColor: NSColor {
		resolved(theme.palette.background)
	}

	override public convenience init() {
		self.init(stores: .live)
	}

	init(stores: PreferencesTransferStores) {
		self.stores = stores
		super.init()

		/* The snapshot carries the appearance the colours off the main actor are
		 resolved against, and the system's own light/dark switch never passes
		 through a preference change, so the appearance notifications are the
		 only thing that says the snapshot has gone stale. */
		for name in [Notification.Name.applicationAppearanceChanged, .systemAppearanceChanged] {
			notifications.observe(name) { [weak self] _ in
				self?.appearanceDidChange()
			}
		}
	}

	public func reload() {
		let key = Preferences.Theme.transcriptTheme
		let stored = stores.store(for: key).data(forKey: key.name) ?? Data()
		guard stored.isEmpty == false else {
			publish(.lines, persist: false)
			return
		}

		do {
			let document = try TranscriptTheme.decoded(from: stored)
			/* Written back exactly when the stored document was older than what
			 was decoded from it. Publishing the migration without storing it
			 left the file at its old version for good: every launch migrated it
			 again, and every export carried the old version out. */
			publish(document.theme, persist: document.wasMigrated)
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
	public func apply(_ newTheme: TranscriptTheme) -> Bool {
		guard newTheme.isValid else {
			Self.logger.error("Rejected a transcript theme with values outside the supported ranges")
			return false
		}

		publish(newTheme, persist: true)
		return true
	}

	public func reset(layout: TranscriptThemeLayout? = nil) {
		let layout = layout ?? theme.layout
		apply(layout == .bubbles ? .bubbles : .lines)
	}

	public func importTheme(from data: Data) throws {
		/* `decoded(from:)` rejects anything `isValid` would, so `apply` cannot
		 fail here. */
		try apply(TranscriptTheme.decoded(from: data).theme)
	}

	public func exportTheme() throws -> Data {
		let encoder = PropertyListEncoder()
		encoder.outputFormat = .xml
		return try encoder.encode(theme)
	}

	/// Republishes the snapshot for the appearance now in effect, and says so.
	///
	/// The preference path and the system's own switch both arrive here, and the
	/// second of them is not news: a snapshot that already says what this one
	/// would say leaves the transcript alone rather than redrawing it twice.
	public func appearanceDidChange() {
		guard publishSnapshot() else {
			return
		}

		NotificationCenter.default.post(name: .themeAppearanceChanged, object: self)
	}

	public func resolved(_ color: AdaptiveTranscriptColor) -> NSColor {
		color.resolved(isDark: SharedApplication.sharedAppearance().properties.isDarkAppearance)
	}

	private func publish(_ newTheme: TranscriptTheme, persist: Bool) {
		theme = newTheme
		publishSnapshot()

		if persist {
			do {
				try stores.set(.data(exportTheme()), for: Preferences.Theme.transcriptTheme)
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
			isDarkAppearance: SharedApplication.sharedAppearance().properties.isDarkAppearance
		)

		return ThemeSnapshotStore.publish(snapshot)
	}
}
