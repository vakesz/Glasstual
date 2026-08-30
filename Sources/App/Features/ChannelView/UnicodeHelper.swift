/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \\/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import Foundation

public nonisolated enum UnicodeHelper { // nonisolated: value
	/// Whether `codePoint` is a letter, used to find the word boundaries
	/// around a nickname or a link in a rendered message.
	///
	/// This used to binary-search seven hand-written range tables. They were
	/// generated around 2007 and stopped at U+1D7CB, so every script added
	/// since -- Adlam, Osage, the Cherokee lowercase block -- was classified
	/// as non-alphabetic and boundary detection was wrong for those users.
	/// `Unicode.Scalar.Properties` carries the current tables.
	public static func isAlphabeticalCodePoint(_ codePoint: Int) -> Bool {
		guard let value = UInt32(exactly: codePoint), let scalar = Unicode.Scalar(value) else {
			return false
		}

		return scalar.properties.isAlphabetic
	}
}
