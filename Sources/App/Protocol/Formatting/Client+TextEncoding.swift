// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
import os

private let clientTextEncodingLogger = Logger(
	subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
	category: "IRCTextEncoding"
)

struct TextEncodingPolicy {
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

extension Client {
	private var textEncodingPolicy: TextEncodingPolicy {
		/* The configuration persists the encodings as their raw values, which
		 is what the on-disk format has always held; they become the type here
		 and stay typed from here on. */
		TextEncodingPolicy(
			primary: String.Encoding(rawValue: config.primaryEncoding),
			fallback: String.Encoding(rawValue: config.fallbackEncoding),
			requiresUTF8: supportInfo.utf8Only
		)
	}

	var effectivePrimaryEncoding: String.Encoding {
		textEncodingPolicy.primary
	}

	var effectiveFallbackEncoding: String.Encoding {
		textEncodingPolicy.fallback
	}

	func convert(toCommonEncoding string: String) -> Data? {
		let data = textEncodingPolicy.encode(string)
		if data == nil {
			clientTextEncodingLogger.error("NSData encode failure")
		}
		return data
	}

	func convert(fromCommonEncoding data: Data) -> String? {
		let string = textEncodingPolicy.decode(data)
		if string == nil {
			clientTextEncodingLogger.error("NSData decode failure")
		}
		return string
	}
}
