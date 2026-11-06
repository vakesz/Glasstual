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

	func encodeIRCLine(_ line: String) -> Data? {
		textEncodingOptions.encodeIRCLine(line)
	}

	func decodeIRCLine(_ data: Data) -> String? {
		textEncodingOptions.decodeIRCLine(data)
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
