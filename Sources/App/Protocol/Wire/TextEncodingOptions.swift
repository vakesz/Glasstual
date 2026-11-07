// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
import os

struct TextEncodingOptions {
	let primary: String.Encoding
	let fallback: String.Encoding

	init(primary: String.Encoding, fallback: String.Encoding, requiresUTF8: Bool) {
		if requiresUTF8 {
			self.primary = .utf8
			self.fallback = .utf8
		} else {
			self.primary = primary
			self.fallback = fallback
		}
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
