// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** One `MODE` command's arguments after the channel name.

 A mode change is a mode string and the parameters that pair with it, and the
 two are separate tokens on the wire. Carrying them as one space-joined string
 meant the compiler built `"+ooo alice bob carol"` and `sendModes` took it apart
 again with the wire tokeniser — a round trip through text whose only job was to
 be undone, and one that could not carry a parameter containing a space. */
nonisolated struct ModeChangeGroup: Sendable, Equatable {
	/// The mode string, signs included: `+ooo`, `-k+l`, `+nt`.
	var symbols: String
	/// The parameters the mode string's letters pair with, in order.
	var parameters: [String]

	init(symbols: String, parameters: [String] = []) {
		self.symbols = symbols
		self.parameters = parameters
	}

	/// The group as the wire arguments that follow the channel name.
	var wireArguments: [String] {
		[symbols] + parameters
	}
}

extension Client {
	func compileListOfModeChanges(
		forModeSymbol modeSymbol: String,
		modeIsSet: Bool,
		parameterString: String
	) -> [ModeChangeGroup] {
		compileListOfModeChanges(
			forModeSymbol: modeSymbol,
			modeIsSet: modeIsSet,
			parameterString: parameterString,
			characterSet: .whitespaces
		)
	}

	func compileListOfModeChanges(
		forModeSymbol modeSymbol: String,
		modeIsSet: Bool,
		parameterString: String,
		characterSet: CharacterSet
	) -> [ModeChangeGroup] {
		compileListOfModeChanges(
			forModeSymbol: modeSymbol,
			modeIsSet: modeIsSet,
			modeParameters: parameterString.components(separatedBy: characterSet)
		)
	}

	func compileListOfModeChanges(
		forModeSymbol modeSymbol: String,
		modeIsSet: Bool,
		modeParameters: [String]
	) -> [ModeChangeGroup] {
		ModeParser.compileModeChanges(
			symbol: modeSymbol,
			isSet: modeIsSet,
			parameters: modeParameters,
			maximumModes: supportInfo.maximumModeCount
		)
	}
}
