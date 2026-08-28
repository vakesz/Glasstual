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
		String(localized: .TDCServerEndpointListSheet.valueYouEnteredIsNot)
	}

	static var invalidAddressRecoverySuggestion: String {
		String(localized: .TDCServerEndpointListSheet.intentionallyEmptyRecoverySuggestion)
	}

	static var invalidPortDescription: String {
		String(localized: .TDCServerEndpointListSheet.valueYouEnteredIsNotAProperlyFormattedServer)
	}

	static var invalidPortRecoverySuggestion: String {
		String(localized: .TDCServerEndpointListSheet.enterAWholeNumberBetween1)
	}
}
