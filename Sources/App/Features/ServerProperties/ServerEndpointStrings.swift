/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import Foundation

nonisolated enum ServerEndpointStrings { // nonisolated: value
	static var windowTitle: String {
		String(localized: .TDCServerEndpointListSheet.windowTitle)
	}

	static var explanation: String {
		String(localized: .TDCServerEndpointListSheet.explanation)
	}

	static var serverAddress: String {
		String(localized: .TDCServerEndpointListSheet.serverAddress)
	}

	static var port: String {
		String(localized: .TDCServerEndpointListSheet.port)
	}

	static var connectSecurely: String {
		String(localized: .TDCServerEndpointListSheet.connectSecurely)
	}

	static var serverPassword: String {
		String(localized: .TDCServerEndpointListSheet.serverPassword)
	}

	static var serverPasswordHelp: String {
		String(localized: .TDCServerEndpointListSheet.serverPasswordHelp)
	}

	static var serverList: String {
		String(localized: .TDCServerEndpointListSheet.serverList)
	}

	static var addServer: String {
		String(localized: .TDCServerEndpointListSheet.addServer)
	}

	static var removeServer: String {
		String(localized: .TDCServerEndpointListSheet.removeServer)
	}

	static var moveUp: String {
		String(localized: .TDCServerEndpointListSheet.moveUp)
	}

	static var moveDown: String {
		String(localized: .TDCServerEndpointListSheet.moveDown)
	}

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
