// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

/** A name someone set on the server, made safe to draw beside their nickname.

 The value comes from another user, so it is held to one short, visible line
 at construction: IRC formatting, control and bidirectional characters,
 invisible and tag characters, stacked combining marks and runs of spaces go,
 and the result is cut to a length that cannot crowd out the nickname. A value
 with nothing visible left is no name at all. */
nonisolated struct ProfileDisplayName: Sendable, Hashable {
	/// The raw value above this is dropped rather than cut.
	static let maximumWireBytes = 1024
	/// Grapheme clusters kept before the name is cut with an ellipsis.
	static let maximumLength = 32
	/// Combining marks kept on one grapheme cluster.
	static let maximumCombiningMarks = 3

	let text: String

	init?(wireValue: String) {
		guard wireValue.utf8.count <= Self.maximumWireBytes else { return nil }

		let line = ControlCharacterDisposition.singleLine((wireValue as NSString).stripIRCEffects)
		var characters: [Character] = []
		var previousWasSpace = true

		for character in line {
			guard let visible = Self.visible(character) else { continue }

			let isSpace = visible.isWhitespace
			if isSpace, previousWasSpace {
				continue
			}
			characters.append(isSpace ? " " : visible)
			previousWasSpace = isSpace
		}

		while characters.last?.isWhitespace == true {
			characters.removeLast()
		}

		guard characters.isEmpty == false else { return nil }

		if characters.count > Self.maximumLength {
			characters = Array(characters.prefix(Self.maximumLength - 1))
			while characters.last?.isWhitespace == true {
				characters.removeLast()
			}
			characters.append("…")
		}

		text = String(characters)
	}

	/// `character` without the scalars a display name never draws, or `nil`
	/// when nothing visible is left of it.
	private static func visible(_ character: Character) -> Character? {
		var scalars = String.UnicodeScalarView()
		var marks = 0
		var hasBase = false

		for scalar in character.unicodeScalars {
			if ControlCharacterDisposition.isInvisibleInDisplayName(scalar) {
				continue
			}

			switch scalar.properties.generalCategory {
			case .nonspacingMark, .enclosingMark, .spacingMark:
				guard hasBase, marks < maximumCombiningMarks else { continue }
				marks += 1
			default:
				if scalar.properties.isVariationSelector, hasBase == false {
					continue
				}
				if scalar.properties.isVariationSelector == false {
					hasBase = true
				}
			}

			scalars.append(scalar)
		}

		guard hasBase else { return nil }

		return Character(String(scalars))
	}
}

/// A profile picture someone set: an address with an optional `{size}` the
/// client fills in with the pixel size it wants.
nonisolated struct ProfileAvatar: Sendable, Hashable {
	static let maximumWireBytes = 2048
	static let sizePlaceholder = "{size}"

	let template: String

	init?(wireValue: String) {
		guard wireValue.utf8.count <= Self.maximumWireBytes else { return nil }

		template = wireValue

		guard url(pixelSize: 64) != nil else { return nil }
	}

	/// The address for an image `pixelSize` pixels across, or `nil` unless it
	/// is an HTTP or HTTPS address with a host.
	func url(pixelSize: Int) -> URL? {
		let address = template.replacingOccurrences(of: Self.sizePlaceholder, with: String(pixelSize))

		guard let url = URL(string: address), LinkSchemeRules.isWebURL(url),
		      url.host(percentEncoded: false)?.isEmpty == false
		else { return nil }

		return url
	}
}

/// A colour someone chose for their name: HTML-style six hexadecimal digits.
nonisolated struct ProfileColor: Sendable, Hashable {
	let red: UInt8
	let green: UInt8
	let blue: UInt8

	init(red: UInt8, green: UInt8, blue: UInt8) {
		self.red = red
		self.green = green
		self.blue = blue
	}

	/// Reads `#RRGGBB` or `RRGGBB`.
	init?(wireValue: String) {
		let digits = wireValue.hasPrefix("#") ? wireValue.dropFirst() : Substring(wireValue)

		guard digits.count == 6, digits.allSatisfy(\.isHexDigit), let value = UInt32(digits, radix: 16) else {
			return nil
		}

		red = UInt8((value >> 16) & 0xFF)
		green = UInt8((value >> 8) & 0xFF)
		blue = UInt8(value & 0xFF)
	}

	/// `#RRGGBB`, as `METADATA SET` sends it.
	var hexString: String {
		String(format: "#%02X%02X%02X", red, green, blue)
	}
}

/// What someone set about themselves, or a channel about itself, through
/// `draft/metadata-2`. Presentation only: none of it names anyone.
nonisolated struct UserProfile: Sendable, Hashable {
	var displayName: ProfileDisplayName?
	var avatar: ProfileAvatar?
	var color: ProfileColor?

	var isEmpty: Bool {
		displayName == nil && avatar == nil && color == nil
	}

	/// The wire values, by key, of what is set.
	var wireValues: [String: String] {
		var values: [String: String] = [:]
		values[MetadataKey.displayName] = displayName?.text
		values[MetadataKey.avatar] = avatar?.template
		values[MetadataKey.color] = color?.hexString

		return values
	}

	/** Applies one key's value, or its removal for `nil`. Reports whether the
	 profile changed. A key this profile does not hold is ignored, and a value
	 that does not parse removes the key. */
	@discardableResult
	mutating func apply(key: String, value: String?) -> Bool {
		let before = self

		switch key {
		case MetadataKey.displayName: displayName = value.flatMap(ProfileDisplayName.init(wireValue:))
		case MetadataKey.avatar: avatar = value.flatMap(ProfileAvatar.init(wireValue:))
		case MetadataKey.color: color = value.flatMap(ProfileColor.init(wireValue:))
		default: return false
		}

		return self != before
	}
}

/** The profile the user chose for themselves on one server.

 It is remembered in the server's configuration and set again on connect when
 the server's copy differs, for networks that forget metadata between
 sessions. It is not a secret. A key with no value means "not set". */
nonisolated struct ServerProfilePreference: Codable, Sendable, Hashable {
	var displayName: String?
	var avatar: String?
	var color: String?

	init(displayName: String? = nil, avatar: String? = nil, color: String? = nil) {
		self.displayName = displayName
		self.avatar = avatar
		self.color = color
	}

	/// The value for one profile key.
	subscript(key: String) -> String? {
		get {
			switch key {
			case MetadataKey.displayName: displayName
			case MetadataKey.avatar: avatar
			case MetadataKey.color: color
			default: nil
			}
		}
		set {
			switch key {
			case MetadataKey.displayName: displayName = newValue
			case MetadataKey.avatar: avatar = newValue
			case MetadataKey.color: color = newValue
			default: break
			}
		}
	}
}
