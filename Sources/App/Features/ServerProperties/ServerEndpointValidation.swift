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

nonisolated enum ServerEndpointValidation { // nonisolated: value
	static let errorDomain = "GlasstualErrorDomain"
	static let invalidAddressCode = 71013
	static let invalidPortCode = 71014

	static let plainTextPort: UInt16 = 6667
	static let securedPort: UInt16 = 6697

	static func validatedAddress(_ address: String) throws -> String {
		guard (address as NSString).isValidInternetAddress else {
			throw NSError(
				domain: errorDomain,
				code: invalidAddressCode,
				userInfo: [
					NSLocalizedDescriptionKey: ServerEndpointStrings.invalidAddressDescription,
					NSLocalizedRecoverySuggestionErrorKey: ServerEndpointStrings.invalidAddressRecoverySuggestion,
				]
			)
		}

		return address
	}

	static func validatedPort(_ port: String) throws -> UInt16 {
		guard (port as NSString).isValidInternetPort, let value = UInt16(port) else {
			throw NSError(
				domain: errorDomain,
				code: invalidPortCode,
				userInfo: [
					NSLocalizedDescriptionKey: ServerEndpointStrings.invalidPortDescription,
					NSLocalizedRecoverySuggestionErrorKey: ServerEndpointStrings.invalidPortRecoverySuggestion,
				]
			)
		}

		return value
	}

	static func server(_ server: Server, preferringSecuredConnection prefers: Bool) -> Server {
		var updated = server
		updated.prefersSecuredConnection = prefers

		if prefers, server.serverPort == plainTextPort {
			updated.serverPort = securedPort
		} else if prefers == false, server.serverPort == securedPort {
			updated.serverPort = plainTextPort
		}

		return updated
	}
}
