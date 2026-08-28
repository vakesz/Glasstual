/* *********************************************************************
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation

nonisolated enum IRCDiagnosticStrings {
	static var rawTrafficNotice: String {
		String(localized: .IRC.ik6Dl)
	}

	static var hiddenCommandResponsesNotice: String {
		String(localized: .IRC.yemTd)
	}

	static func scriptFailure(filename: String, input: String, description: String) -> String {
		String(localized: .IRC._2McH0(filename, input, description))
	}

	static func scriptFailure(_ description: String) -> String {
		String(localized: .IRC.ax0Mt(description))
	}

	static func malformedMessage(numeric: UInt, sequence: String) -> String {
		// The numeric is server-controlled; an out-of-range one is reported
		// as 0 rather than trapping the conversion.
		String(localized: .IRC._3YoGw(Int32(exactly: numeric) ?? 0, sequence))
	}
}

nonisolated enum IRCLogStrings {
	static func sessionMarker(startsSession: Bool) -> String {
		startsSession ? String(localized: .IRC.qrgUa) : String(localized: .IRC.d5DUy)
	}
}
