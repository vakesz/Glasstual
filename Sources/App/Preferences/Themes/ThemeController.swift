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
public nonisolated struct ThemeSnapshot: Sendable { // nonisolated: value
	public let transcript: TranscriptTheme
	public let isDarkAppearance: Bool

	public var timestampFormat: String {
		transcript.timestampFormat
	}
}

public nonisolated enum TranscriptThemeCodingError: LocalizedError, Equatable, Sendable { // nonisolated: value
	case invalidDocument
	case unsupportedVersion(Int)

	public var errorDescription: String? {
		switch self {
		case .invalidDocument:
			TranscriptThemeStrings.invalidDocument
		case let .unsupportedVersion(version):
			TranscriptThemeStrings.unsupportedVersion(version)
		}
	}
}

/// Owns the native transcript theme. A single Codable value is used for live
/// rendering, preferences, and plist import/export.
@MainActor
@Observable
public final class ThemeController: NSObject {
	private nonisolated static let publishedSnapshot = Mutex(ThemeSnapshot( // nonisolated: let
		transcript: .lines,
		isDarkAppearance: false
	))
	private static let logger = Logger(
		subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
		category: "TranscriptTheme"
	)

	public nonisolated static var activeSnapshot: ThemeSnapshot? { // nonisolated: pure
		publishedSnapshot.withLock { $0 }
	}

	public private(set) var theme = TranscriptTheme.lines

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

	override public init() {
		super.init()
	}

	public func reload() {
		let stored = Preferences.Theme.transcriptTheme.value
		guard stored.isEmpty == false else {
			publish(.lines, persist: false)
			return
		}

		do {
			try publish(Self.decode(stored), persist: false)
		} catch {
			Self.logger.error(
				"Discarding invalid stored transcript theme: \(error.localizedDescription, privacy: .public)"
			)
			Preferences.Theme.transcriptTheme.reset()
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
		/* `decode` rejects anything `isValid` would, so `apply` cannot fail
		 here. */
		try apply(Self.decode(data))
	}

	public func exportTheme() throws -> Data {
		let encoder = PropertyListEncoder()
		encoder.outputFormat = .xml
		return try encoder.encode(theme)
	}

	public func appearanceDidChange() {
		publishSnapshot()
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
				Preferences.Theme.transcriptTheme.value = try exportTheme()
			} catch {
				Self.logger.error(
					"Failed to store transcript theme: \(error.localizedDescription, privacy: .public)"
				)
			}
		}

		NotificationCenter.default.post(name: .themeWasModified, object: self)
	}

	private func publishSnapshot() {
		let snapshot = ThemeSnapshot(
			transcript: theme,
			isDarkAppearance: SharedApplication.sharedAppearance().properties.isDarkAppearance
		)
		Self.publishedSnapshot.withLock { $0 = snapshot }
	}

	private nonisolated static func decode(_ data: Data) throws -> TranscriptTheme { // nonisolated: pure
		let decoded: TranscriptTheme
		do {
			decoded = try PropertyListDecoder().decode(TranscriptTheme.self, from: data)
		} catch {
			throw TranscriptThemeCodingError.invalidDocument
		}

		guard decoded.formatVersion == TranscriptTheme.currentFormatVersion else {
			throw TranscriptThemeCodingError.unsupportedVersion(decoded.formatVersion)
		}
		guard decoded.isValid else {
			throw TranscriptThemeCodingError.invalidDocument
		}
		return decoded
	}
}
