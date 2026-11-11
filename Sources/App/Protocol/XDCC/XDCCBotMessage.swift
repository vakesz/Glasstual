// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** What an XDCC bot's notice says about a request, as far as it can be read.

 The wording is iroffer's and iroffer-dinoex's, which most bots run. Reading it
 is best effort: it refreshes and labels a pending request, and nothing is
 matched or downloaded on the strength of it. */
nonisolated enum XDCCBotMessage: Equatable, Sendable {
	/// `** Sending you pack #5 ("file.mkv"), which is 700MB. (resume supported)`
	case sending(pack: Int, filename: String, sizeText: String?)
	/// `** All Slots Full, Added you to the main queue for pack 5 ("file.mkv")
	/// in position 3. …`
	case queued(pack: Int, filename: String?, position: Int?)
	/// `** You already requested that pack`, or the queued-already variant.
	case alreadyRequested
	/// `** Invalid Pack Number, Try Again`
	case invalidPack
	/// `** XDCC SEND denied, …`, with the reason the bot gave.
	case denied(String)

	/// Bot notices are short; anything longer is not one of these.
	static let maximumLength = 512

	static func parse(_ plainText: String) -> XDCCBotMessage? {
		guard plainText.unicodeScalars.count <= maximumLength else { return nil }
		var text = Substring(plainText.trimmingCharacters(in: .whitespaces))
		while text.hasPrefix("*") {
			text = text.dropFirst()
		}
		let message = text.trimmingCharacters(in: .whitespaces)

		if let range = find("sending you pack", in: message, anchored: true) {
			return sending(String(message[range.upperBound...]))
		}
		if find("added you to the", in: message) != nil, let range = find("queue for pack", in: message) {
			return queued(String(message[range.upperBound...]))
		}
		if find("already requested that pack", in: message) != nil
			|| find("already have that item queued", in: message) != nil
		{
			return .alreadyRequested
		}
		if find("invalid pack number", in: message, anchored: true) != nil {
			return .invalidPack
		}
		if let range = find("denied", in: message) {
			let reason = message[range.upperBound...].drop { $0 == "," || $0 == ":" || $0.isWhitespace }
			return .denied(String(reason).trimmingCharacters(in: .whitespaces))
		}
		return nil
	}

	/** Where `needle` is in `text`, ignoring case.

	 The range is found in `text` itself. Lowercasing a copy and searching that
	 would give positions in a different string: some characters change
	 length when lowercased, so the positions need not even exist in `text`. */
	private static func find(_ needle: String, in text: String, anchored: Bool = false) -> Range<String.Index>? {
		text.range(of: needle, options: anchored ? [.caseInsensitive, .anchored] : [.caseInsensitive])
	}

	private static func sending(_ afterMarker: String) -> XDCCBotMessage? {
		var scanner = XDCCScanner(afterMarker)
		scanner.skipWhitespace()
		_ = scanner.take("#")
		guard let pack = scanner.number(maximumDigits: 6), XDCCAnnouncementParser.packRange.contains(pack) else {
			return nil
		}
		let rest = scanner.rest
		guard let filename = quoted(in: rest) else { return nil }
		return .sending(pack: pack, filename: filename, sizeText: size(after: "which is", in: rest))
	}

	private static func queued(_ afterPack: String) -> XDCCBotMessage? {
		var scanner = XDCCScanner(afterPack)
		scanner.skipWhitespace()
		_ = scanner.take("#")
		guard let pack = scanner.number(maximumDigits: 6), XDCCAnnouncementParser.packRange.contains(pack) else {
			return nil
		}
		var position: Int?
		if let range = find("in position", in: afterPack) {
			var positionScanner = XDCCScanner(String(afterPack[range.upperBound...]))
			positionScanner.skipWhitespace()
			position = positionScanner.number(maximumDigits: 6)
		}
		return .queued(pack: pack, filename: quoted(in: afterPack), position: position)
	}

	/// The first double-quoted run in `text`.
	private static func quoted(in text: String) -> String? {
		guard let open = text.firstIndex(of: "\""),
		      let close = text[text.index(after: open)...].firstIndex(of: "\"")
		else { return nil }
		let name = text[text.index(after: open) ..< close].trimmingCharacters(in: .whitespaces)
		return name.isEmpty ? nil : name
	}

	/// The size text following `marker`, up to the sentence's end.
	private static func size(after marker: String, in text: String) -> String? {
		guard let range = find(marker, in: text) else { return nil }
		let tail = text[range.upperBound...].trimmingCharacters(in: .whitespaces)
		let size = tail.prefix { $0.isWhitespace == false && $0 != ")" }
		let trimmed = size.hasSuffix(".") ? size.dropLast() : size
		return trimmed.isEmpty ? nil : String(trimmed)
	}
}
