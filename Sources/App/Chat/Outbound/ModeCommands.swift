// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

extension ServerSession {
	func compileListOfModeChanges(
		forModeSymbol modeSymbol: String,
		modeIsSet: Bool,
		parameterString: String
	) -> [ModeChangeGroup] {
		compileListOfModeChanges(
			forModeSymbol: modeSymbol,
			modeIsSet: modeIsSet,
			modeParameters: parameterString.components(separatedBy: .whitespaces)
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
