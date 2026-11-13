// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
import os

struct TextEncodingOptions {
	let primary: String.Encoding
	let fallback: String.Encoding

	/// An encoding the wire cannot carry is replaced by the default for its
	/// place, so a configuration saved with one keeps working.
	init(primary: String.Encoding, fallback: String.Encoding, requiresUTF8: Bool) {
		if requiresUTF8 {
			self.primary = .utf8
			self.fallback = .utf8
		} else {
			self.primary = Self.wireCompatible(primary, otherwise: .utf8)
			self.fallback = Self.wireCompatible(fallback, otherwise: .isoLatin1)
		}
	}

	/// Every byte IRC gives a meaning to: the line terminator, the separators
	/// and prefix markers, and the letters and digits of commands.
	private nonisolated static let wireProbe = "\r\n :!@#;=,0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"

	/** Whether `encoding` writes ASCII as ASCII, which a byte-oriented protocol
	 needs. UTF-16 and UTF-32, in any byte order, put a NUL beside every ASCII
	 byte and can produce a CR or LF from an ordinary character; EBCDIC moves
	 the terminator. UTF-8, the ISO and Windows Latin sets, Shift_JIS, EUC and
	 ISO-2022-JP all keep ASCII as it is. */
	nonisolated static func isWireCompatible(_ encoding: String.Encoding) -> Bool { // nonisolated: pure
		wireProbe.data(using: encoding, allowLossyConversion: false) == Data(wireProbe.utf8)
	}

	nonisolated static func wireCompatible( // nonisolated: pure
		_ encoding: String.Encoding,
		otherwise replacement: String.Encoding
	) -> String.Encoding {
		isWireCompatible(encoding) ? encoding : replacement
	}

	/// Whether `data` is exactly one IRC line: it ends in CR LF, and no NUL, CR
	/// or LF comes before that.
	nonisolated static func isSafeWireLine(_ data: Data) -> Bool { // nonisolated: pure
		guard data.count >= 2, data.suffix(2).elementsEqual([0x0D, 0x0A]) else { return false }
		return data.dropLast(2).contains { $0 == 0x00 || $0 == 0x0A || $0 == 0x0D } == false
	}

	/// IRCv3 tags use UTF-8 independently of the encoding selected for message text.
	func encodeIRCLine(_ line: String) -> Data? {
		guard line.hasPrefix("@"), let separator = line.firstIndex(of: " ") else {
			return encode(line)
		}
		guard let body = encode(String(line[line.index(after: separator)...])) else { return nil }
		return Data(line[...separator].utf8) + body
	}

	func decodeIRCLine(_ data: Data) -> String? {
		guard data.first == 0x40, let separator = data.firstIndex(of: 0x20) else {
			return decode(data)
		}
		guard let body = decode(Data(data[data.index(after: separator)...])) else { return nil }
		let section = data[data.index(after: data.startIndex) ..< separator]
		let tags = section.split(separator: 0x3B).compactMap { tag -> String? in
			if let valid = String(data: tag, encoding: .utf8) {
				return valid
			}
			// An invalid value is omitted, preserving the key and last-occurrence
			// semantics. Replacement characters could merge distinct identifiers.
			guard let equals = tag.firstIndex(of: 0x3D) else { return nil }
			return String(data: tag[..<equals], encoding: .utf8)
		}
		return tags.isEmpty ? body : "@" + tags.joined(separator: ";") + " " + body
	}

	func encode(_ string: String) -> Data? {
		string.data(using: primary, allowLossyConversion: false)
			?? string.data(using: fallback, allowLossyConversion: false)
			?? string.data(using: .ascii, allowLossyConversion: true)
	}

	func decode(_ data: Data) -> String? {
		String(data: data, encoding: primary)
			?? String(data: data, encoding: fallback)
			?? String(data: data, encoding: .isoLatin1)
	}
}
