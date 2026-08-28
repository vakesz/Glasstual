/* *********************************************************************
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation

/// Compatibility keys whose historical length modifiers are not supported by
/// Xcode's generated String Catalog symbols. Callers expose typed parameters;
/// only this catalog boundary performs C-style formatting.
nonisolated enum IRCLegacyFormat: String {
	case fileTransferAttempt = "ags-s8"
	case directChatConnect = "dcc-c7"
	case directChatWait = "dcc-cb"
	case socksProxy = "ni5-cy"
	case serverConnection = "o77-ls"
	case httpProxy = "oby-av"
	case fileTransferRequest = "snf-45"
	case enforcedStrictTransportSecurity = "sts-p1"
	case offeredStrictTransportSecurity = "sts-p2"
	case storedStrictTransportSecurity = "sts-p3"

	func format(_ arguments: CVarArg...) -> String {
		let format = Bundle.main.localizedString(forKey: rawValue, value: nil, table: "IRC")

		return String(format: format, arguments: arguments)
	}
}
