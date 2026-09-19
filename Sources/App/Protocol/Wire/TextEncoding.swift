// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
import os

private let sessionTextEncodingLogger = Logger(
	subsystem: LogSubsystem.current,
	category: "TextEncoding"
)

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

extension ServerSession {
	private var textEncodingOptions: TextEncodingOptions {
		/* The configuration persists the encodings as their raw values, which
		 is what the on-disk format has always held; they become the type here
		 and stay typed from here on. */
		TextEncodingOptions(
			primary: String.Encoding(rawValue: config.primaryEncoding),
			fallback: String.Encoding(rawValue: config.fallbackEncoding),
			requiresUTF8: supportInfo.utf8Only
		)
	}

	var effectivePrimaryEncoding: String.Encoding {
		textEncodingOptions.primary
	}

	var effectiveFallbackEncoding: String.Encoding {
		textEncodingOptions.fallback
	}

	func convert(toCommonEncoding string: String) -> Data? {
		let data = textEncodingOptions.encode(string)
		if data == nil {
			sessionTextEncodingLogger.error("NSData encode failure")
		}
		return data
	}

	func convert(fromCommonEncoding data: Data) -> String? {
		let string = textEncodingOptions.decode(data)
		if string == nil {
			sessionTextEncodingLogger.error("NSData decode failure")
		}
		return string
	}
}
