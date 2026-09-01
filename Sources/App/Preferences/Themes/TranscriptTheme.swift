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

/// A portable sRGB colour. Theme files use components rather than archived
/// `NSColor` objects so they remain readable and stable across macOS releases.
public nonisolated struct TranscriptThemeColor: Codable, Equatable, Sendable { // nonisolated: value
	public var red: Double
	public var green: Double
	public var blue: Double
	public var alpha: Double

	public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
		self.red = red
		self.green = green
		self.blue = blue
		self.alpha = alpha
	}

	public init?(_ color: NSColor) {
		guard let color = color.usingColorSpace(.sRGB) else {
			return nil
		}
		self.init(
			red: color.redComponent,
			green: color.greenComponent,
			blue: color.blueComponent,
			alpha: color.alphaComponent
		)
	}

	public var color: NSColor {
		NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
	}

	var isValid: Bool {
		[red, green, blue, alpha].allSatisfy { $0.isFinite && (0 ... 1).contains($0) }
	}
}

/// Light and dark variants for one semantic role in a transcript.
public nonisolated struct AdaptiveTranscriptColor: Codable, Equatable, Sendable { // nonisolated: value
	public var light: TranscriptThemeColor
	public var dark: TranscriptThemeColor

	public init(light: TranscriptThemeColor, dark: TranscriptThemeColor) {
		self.light = light
		self.dark = dark
	}

	public func resolved(isDark: Bool) -> NSColor {
		(isDark ? dark : light).color
	}

	var isValid: Bool {
		light.isValid && dark.isValid
	}
}

public nonisolated enum TranscriptThemeLayout: String, Codable, CaseIterable, Sendable { // nonisolated: value
	case lines
	case bubbles
}

/// Every colour the native transcript draws, named by purpose rather than by
/// where a former stylesheet happened to use it.
public nonisolated struct TranscriptThemePalette: Codable, Equatable, Sendable { // nonisolated: value
	public var background: AdaptiveTranscriptColor
	public var primaryText: AdaptiveTranscriptColor
	public var secondaryText: AdaptiveTranscriptColor
	public var eventText: AdaptiveTranscriptColor
	public var link: AdaptiveTranscriptColor
	public var localNickname: AdaptiveTranscriptColor
	public var remoteNickname: AdaptiveTranscriptColor
	public var highlightBackground: AdaptiveTranscriptColor
	public var highlightText: AdaptiveTranscriptColor
	public var bubbleIncoming: AdaptiveTranscriptColor
	public var bubbleOutgoing: AdaptiveTranscriptColor
	public var unreadMarker: AdaptiveTranscriptColor
	public var failure: AdaptiveTranscriptColor

	var isValid: Bool {
		[
			background, primaryText, secondaryText, eventText, link,
			localNickname, remoteNickname, highlightBackground, highlightText,
			bubbleIncoming, bubbleOutgoing, unreadMarker, failure,
		].allSatisfy(\.isValid)
	}
}

/// The one native transcript theme format. It is both the runtime model and
/// the payload written by Export Theme, avoiding adapters between preference,
/// file, and rendering representations.
public nonisolated struct TranscriptTheme: Codable, Equatable, Sendable { // nonisolated: value
	public static let currentFormatVersion = 1

	public var formatVersion = currentFormatVersion
	public var name: String
	public var layout: TranscriptThemeLayout
	public var fontName: String
	public var fontSize: Double
	public var timestampFormat: String
	public var nicknameFormat: String
	public var lineSpacing: Double
	public var messageSpacing: Double
	public var horizontalPadding: Double
	public var palette: TranscriptThemePalette

	public init(
		name: String,
		layout: TranscriptThemeLayout,
		fontName: String = ".AppleSystemUIFont",
		fontSize: Double = 13,
		timestampFormat: String = "%H:%M:%S",
		nicknameFormat: String = "<%@%n>",
		lineSpacing: Double = 2,
		messageSpacing: Double = 3,
		horizontalPadding: Double = 10,
		palette: TranscriptThemePalette
	) {
		self.name = name
		self.layout = layout
		self.fontName = fontName
		self.fontSize = fontSize
		self.timestampFormat = timestampFormat
		self.nicknameFormat = nicknameFormat
		self.lineSpacing = lineSpacing
		self.messageSpacing = messageSpacing
		self.horizontalPadding = horizontalPadding
		self.palette = palette
	}

	public static let lines = TranscriptTheme(
		name: "Lines",
		layout: .lines,
		palette: defaultPalette
	)

	public static let bubbles = TranscriptTheme(
		name: "Bubbles",
		layout: .bubbles,
		messageSpacing: 7,
		horizontalPadding: 12,
		palette: defaultPalette
	)

	public static let defaultPalette = TranscriptThemePalette(
		background: pair(light: 0xFFFFFF, dark: 0x1E1E1E),
		primaryText: pair(light: 0x202124, dark: 0xF2F2F2),
		secondaryText: pair(light: 0x6E6E73, dark: 0xA1A1A6),
		eventText: pair(light: 0x65656A, dark: 0xAEAEB2),
		link: pair(light: 0x0068D9, dark: 0x64A8FF),
		localNickname: pair(light: 0x006B3C, dark: 0x67D99A),
		remoteNickname: pair(light: 0x5B42A6, dark: 0xB7A3FF),
		highlightBackground: pair(light: 0xFFF1B8, dark: 0x5C4710),
		highlightText: pair(light: 0x202124, dark: 0xFFFFFF),
		bubbleIncoming: pair(light: 0xE9E9EB, dark: 0x363638),
		bubbleOutgoing: pair(light: 0xD8ECFF, dark: 0x164A73),
		unreadMarker: pair(light: 0xD70015, dark: 0xFF6961),
		failure: pair(light: 0xB00020, dark: 0xFF8A80)
	)

	private static func pair(light: UInt32, dark: UInt32) -> AdaptiveTranscriptColor {
		AdaptiveTranscriptColor(light: color(light), dark: color(dark))
	}

	private static func color(_ value: UInt32) -> TranscriptThemeColor {
		TranscriptThemeColor(
			red: Double((value >> 16) & 0xFF) / 255,
			green: Double((value >> 8) & 0xFF) / 255,
			blue: Double(value & 0xFF) / 255
		)
	}

	var isValid: Bool {
		formatVersion == Self.currentFormatVersion &&
			name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false &&
			fontSize.isFinite && (9 ... 36).contains(fontSize) &&
			lineSpacing.isFinite && (0 ... 16).contains(lineSpacing) &&
			messageSpacing.isFinite && (0 ... 32).contains(messageSpacing) &&
			horizontalPadding.isFinite && (0 ... 48).contains(horizontalPadding) &&
			palette.isValid
	}
}
