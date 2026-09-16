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
		String(localized: .ServerEndpointList.windowTitle)
	}

	static var explanation: String {
		String(localized: .ServerEndpointList.explanation)
	}

	static var serverAddress: String {
		String(localized: .ServerEndpointList.serverAddress)
	}

	static var port: String {
		String(localized: .ServerEndpointList.port)
	}

	static var connectSecurely: String {
		String(localized: .ServerEndpointList.connectSecurely)
	}

	static var serverPassword: String {
		String(localized: .ServerEndpointList.serverPassword)
	}

	static var serverPasswordHelp: String {
		String(localized: .ServerEndpointList.serverPasswordHelp)
	}

	static var serverList: String {
		String(localized: .ServerEndpointList.serverList)
	}

	static var addServer: String {
		String(localized: .ServerEndpointList.addServer)
	}

	static var removeServer: String {
		String(localized: .ServerEndpointList.removeServer)
	}

	static var moveUp: String {
		String(localized: .ServerEndpointList.moveUp)
	}

	static var moveDown: String {
		String(localized: .ServerEndpointList.moveDown)
	}

	static var invalidAddress: String {
		String(localized: .ServerEndpointList.valueYouEnteredIsNot)
	}

	static var invalidPort: String {
		String(localized: .ServerEndpointList.enterAWholeNumberBetween1)
	}
}
