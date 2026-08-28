/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\\_\\__|\\__,_|\\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import Foundation

nonisolated enum ServerEndpointStrings {
	static var invalidAddressDescription: String {
		String(localized: .TDCServerEndpointListSheet.iisGr)
	}

	static var invalidAddressRecoverySuggestion: String {
		String(localized: .TDCServerEndpointListSheet.k0C3U)
	}

	static var invalidPortDescription: String {
		String(localized: .TDCServerEndpointListSheet.qebIp)
	}

	static var invalidPortRecoverySuggestion: String {
		String(localized: .TDCServerEndpointListSheet.ox2Od)
	}
}
