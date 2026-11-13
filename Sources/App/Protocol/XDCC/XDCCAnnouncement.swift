// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/// A pack an XDCC bot offers, as one line of text described it.
nonisolated struct XDCCPackReference: Hashable, Sendable {
	/// The bot to ask for the pack.
	let bot: String
	let pack: Int
	/// The file name, when the line gave one. Display only until compared
	/// after sanitizing.
	let filename: String?
	/// The size as the bot wrote it, such as `1.2G`. Never compared.
	let sizeText: String?
	/// How many times the pack has been downloaded, when the line said.
	let gets: Int?
}

/// What a line of chat says about XDCC, if anything.
nonisolated enum XDCCLine: Equatable, Sendable {
	/// One pack: a line of a bot's listing, or an announcement telling people
	/// how to request it.
	case pack(XDCCPackReference)
	/// The summary at the top of a bot's listing.
	case listingHeader(packs: Int?, slotsOpen: Int?, slotsTotal: Int?)
	/// Instructions naming a bot but no particular pack, such as
	/// `/msg Bot xdcc send #n`.
	case instruction(bot: String)
}

/** Recognises XDCC listings and announcements in formatting-stripped text.

 Three shapes are recognised, which between them cover iroffer and
 iroffer-dinoex listings and the announcers channels run:

 - A listing line, `#12  5x [1.2G] Some.File.mkv`, whose bot is the line's
   sender.
 - An instruction anywhere in the line, `/msg Bot xdcc send #12`, whose bot is
   the nickname it names. A double-quoted name elsewhere in the line is taken
   as the file name.
 - A listing header, `** 12 packs **` or `1 of 2 slots open`.

 Nothing is ever acted on here: a recognised pack only becomes something the
 user can choose to request. Lines longer than ``maximumLength`` are not
 read, pack numbers outside ``packRange`` are not packs, and a bot name has to
 be a plausible nickname. */
nonisolated enum XDCCAnnouncementParser {
	static let maximumLength = 512
	static let packRange = 1 ... 999_999

	static func parse(_ plainText: String, sender: String?) -> XDCCLine? {
		guard plainText.unicodeScalars.count <= maximumLength else { return nil }
		let scalars = Array(plainText.unicodeScalars)

		if let sender, isPlausibleBotName(sender), let pack = listingLine(scalars, bot: sender) {
			return .pack(pack)
		}
		if let instruction = instruction(in: scalars) {
			return instruction
		}
		return listingHeader(in: scalars)
	}

	/** Whether `name` could be a bot to message.

	 It must be a nickname in RFC 2812's ASCII grammar: a letter or one of
	 `[]\\`_^{|}` first, then those, digits and `-`. That keeps `/msg -flag`
	 and `/msg #channel` from being read as bots, and keeps a name in someone's
	 line from passing for a bot it only looks like: `Ваbot` with a Cyrillic
	 `В` and `а` is another nickname, and a pack request would go to it. */
	static func isPlausibleBotName(_ name: String) -> Bool {
		guard let first = name.unicodeScalars.first,
		      Hostmask.isValidNickname(name),
		      name.unicodeScalars.count <= 64,
		      isNicknameLead(first)
		else { return false }
		return name.unicodeScalars.allSatisfy { isNicknameLead($0) || $0.isASCIIDigitScalar || $0 == "-" }
	}

	private static func isNicknameLead(_ scalar: Unicode.Scalar) -> Bool {
		("a" ... "z").contains(scalar) || ("A" ... "Z").contains(scalar) || "[]\\`_^{|}".unicodeScalars.contains(scalar)
	}

	// MARK: - Listing lines

	private static func listingLine(_ scalars: [Unicode.Scalar], bot: String) -> XDCCPackReference? {
		var cursor = XDCCScanner(scalars)
		cursor.skipWhitespace()
		guard cursor.take("#"), let pack = cursor.number(maximumDigits: 6), packRange.contains(pack),
		      cursor.skipWhitespace() > 0,
		      let gets = cursor.number(maximumDigits: 9), cursor.takeCaseInsensitive("x"),
		      cursor.skipWhitespace() > 0,
		      cursor.take("["), let size = sizeText(&cursor), cursor.take("]"),
		      cursor.skipWhitespace() > 0
		else { return nil }

		let filename = cursor.rest.trimmingCharacters(in: .whitespaces)
		guard filename.isEmpty == false else { return nil }
		return XDCCPackReference(bot: bot, pack: pack, filename: filename, sizeText: size, gets: gets)
	}

	/// `1.2G`, `700M`, `<1K`, `1,024 KiB` and the like, with the spaces a bot
	/// pads the brackets with.
	private static func sizeText(_ cursor: inout XDCCScanner) -> String? {
		cursor.skipWhitespace()
		var text = cursor.take("<") ? "<" : ""
		let digits = cursor.span { $0.isASCIIDigitScalar || $0 == "." || $0 == "," }
		guard let first = digits.unicodeScalars.first, first.isASCIIDigitScalar else {
			return nil
		}
		text += digits
		cursor.skipWhitespace()
		let unit = cursor.span { "KMGTkmgtiIbB".unicodeScalars.contains($0) }
		guard unit.count <= 3 else { return nil }
		text += unit
		cursor.skipWhitespace()
		return text
	}

	// MARK: - Instructions

	private static func instruction(in scalars: [Unicode.Scalar]) -> XDCCLine? {
		let lowered = scalars.map { $0.isASCII ? Unicode.Scalar(UInt8(ascii: $0).lowercasedASCII) : $0 }
		var start = 0
		while let found = find(Array("/msg".unicodeScalars), in: lowered, from: start) {
			start = found + 1
			var cursor = XDCCScanner(scalars, at: found + 4)
			guard cursor.skipWhitespace() > 0 else { continue }
			let bot = cursor.span { $0.properties.isWhitespace == false }
			guard isPlausibleBotName(bot), cursor.skipWhitespace() > 0,
			      cursor.takeCaseInsensitive("xdcc"), cursor.skipWhitespace() > 0,
			      cursor.takeCaseInsensitive("send") || cursor.takeCaseInsensitive("get"),
			      cursor.atWordEnd
			else { continue }

			cursor.skipWhitespace()
			_ = cursor.take("#")
			guard cursor.nextIsASCIIDigit else {
				return .instruction(bot: bot)
			}
			/* A number that is not a pack number, or runs into letters, is not a
			 pack; it is not an instruction to fill one in either. */
			guard let pack = cursor.number(maximumDigits: 6), cursor.atWordEnd, packRange.contains(pack) else {
				continue
			}
			return .pack(XDCCPackReference(
				bot: bot, pack: pack, filename: quotedName(in: scalars), sizeText: nil, gets: nil
			))
		}
		return nil
	}

	private static func quotedName(in scalars: [Unicode.Scalar]) -> String? {
		let openers: [Unicode.Scalar: Unicode.Scalar] = ["\"": "\"", "\u{201C}": "\u{201D}"]
		guard let open = scalars.firstIndex(where: { openers[$0] != nil }),
		      let closer = openers[scalars[open]],
		      let close = scalars[(open + 1)...].firstIndex(of: closer)
		else { return nil }
		let name = String(String.UnicodeScalarView(scalars[(open + 1) ..< close])).trimmingCharacters(in: .whitespaces)
		return name.isEmpty ? nil : name
	}

	// MARK: - Listing headers

	private static func listingHeader(in scalars: [Unicode.Scalar]) -> XDCCLine? {
		let lowered = scalars.map { $0.isASCII ? Unicode.Scalar(UInt8(ascii: $0).lowercasedASCII) : $0 }
		var packs: Int?
		var open: Int?
		var total: Int?

		var start = 0
		while packs == nil, let found = find(Array("**".unicodeScalars), in: lowered, from: start) {
			start = found + 2
			var cursor = XDCCScanner(lowered, at: found + 2)
			cursor.skipWhitespace()
			guard let count = cursor.number(maximumDigits: 7), cursor.skipWhitespace() > 0,
			      cursor.takeCaseInsensitive("pack")
			else { continue }
			_ = cursor.take("s")
			cursor.skipWhitespace()
			if cursor.take("*"), cursor.take("*") {
				packs = count
			}
		}

		start = 0
		while open == nil, let found = find(Array(" of ".unicodeScalars), in: lowered, from: start) {
			start = found + 1
			var before = found
			while before > 0, lowered[before - 1].isASCIIDigitScalar {
				before -= 1
			}
			var cursor = XDCCScanner(lowered, at: found + 4)
			guard before < found, let free = Int(String(String.UnicodeScalarView(lowered[before ..< found]))),
			      let all = cursor.number(maximumDigits: 7), cursor.skipWhitespace() > 0,
			      cursor.takeCaseInsensitive("slot")
			else { continue }
			_ = cursor.take("s")
			guard cursor.skipWhitespace() > 0, cursor.takeCaseInsensitive("open"), free <= all else { continue }
			open = free
			total = all
		}

		guard packs != nil || open != nil else { return nil }
		return .listingHeader(packs: packs, slotsOpen: open, slotsTotal: total)
	}

	private static func find(_ needle: [Unicode.Scalar], in haystack: [Unicode.Scalar], from start: Int) -> Int? {
		guard needle.isEmpty == false, haystack.count >= needle.count, start <= haystack.count - needle.count else {
			return nil
		}
		return (start ... haystack.count - needle.count).first { offset in
			haystack[offset ..< offset + needle.count].elementsEqual(needle)
		}
	}
}

/// A forward-only reader over a line's scalars, shared by the XDCC parsers.
nonisolated struct XDCCScanner {
	private let scalars: [Unicode.Scalar]
	private(set) var position: Int

	init(_ scalars: [Unicode.Scalar], at position: Int = 0) {
		self.scalars = scalars
		self.position = min(position, scalars.count)
	}

	init(_ text: String) {
		self.init(Array(text.unicodeScalars))
	}

	var isAtEnd: Bool {
		position >= scalars.count
	}

	/// Whether the next scalar, if any, ends a word.
	var atWordEnd: Bool {
		isAtEnd || scalars[position].properties.isAlphabetic == false && scalars[position].isASCIIDigitScalar == false
	}

	var nextIsASCIIDigit: Bool {
		isAtEnd == false && scalars[position].isASCIIDigitScalar
	}

	var rest: String {
		String(String.UnicodeScalarView(scalars[position...]))
	}

	/// Skips whitespace and says how much there was.
	@discardableResult
	mutating func skipWhitespace() -> Int {
		let start = position
		while isAtEnd == false, scalars[position].properties.isWhitespace {
			position += 1
		}
		return position - start
	}

	mutating func take(_ scalar: Unicode.Scalar) -> Bool {
		guard isAtEnd == false, scalars[position] == scalar else { return false }
		position += 1
		return true
	}

	/// Takes `word` in any ASCII case.
	mutating func takeCaseInsensitive(_ word: String) -> Bool {
		let wanted = Array(word.lowercased().unicodeScalars)
		guard scalars.count - position >= wanted.count else { return false }
		for (offset, scalar) in wanted.enumerated() {
			let candidate = scalars[position + offset]
			guard candidate.isASCII, UInt8(ascii: candidate).lowercasedASCII == UInt8(ascii: scalar) else {
				return false
			}
		}
		position += wanted.count
		return true
	}

	/// A run of ASCII digits no longer than `maximumDigits`. A longer run is
	/// not a number at all, rather than a prefix of one.
	mutating func number(maximumDigits: Int) -> Int? {
		let start = position
		while isAtEnd == false, scalars[position].isASCIIDigitScalar {
			position += 1
		}
		let count = position - start
		guard count > 0, count <= maximumDigits else {
			position = start
			return nil
		}
		return Int(String(String.UnicodeScalarView(scalars[start ..< position])))
	}

	/// The longest run of scalars `belongs` accepts.
	mutating func span(while belongs: (Unicode.Scalar) -> Bool) -> String {
		let start = position
		while isAtEnd == false, belongs(scalars[position]) {
			position += 1
		}
		return String(String.UnicodeScalarView(scalars[start ..< position]))
	}
}

private nonisolated extension Unicode.Scalar {
	var isASCIIDigitScalar: Bool {
		value >= 0x30 && value <= 0x39
	}
}

private nonisolated extension UInt8 {
	var lowercasedASCII: UInt8 {
		self >= 0x41 && self <= 0x5A ? self + 0x20 : self
	}
}
