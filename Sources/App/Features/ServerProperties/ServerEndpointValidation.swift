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

/// Why an endpoint the person typed cannot become a `Server`. The sheet shows
/// one message per kind of fault, which is all a caller ever did with the
/// `NSError`s this used to throw: nobody read their domain, code, description
/// or recovery suggestion.
nonisolated enum ServerEndpointFault: Error, Hashable { // nonisolated: value
	case address
	case port

	var message: String {
		switch self {
		case .address: ServerEndpointStrings.invalidAddress
		case .port: ServerEndpointStrings.invalidPort
		}
	}
}

nonisolated enum ServerEndpointValidation { // nonisolated: value
	static let plainTextPort: UInt16 = 6667
	static let securedPort: UInt16 = 6697

	/// The address, or `nil` when it is not one. An empty address is not one
	/// either: a row nobody typed a host into cannot be connected to.
	static func validatedAddress(_ address: String) -> String? {
		(address as NSString).isValidInternetAddress ? address : nil
	}

	static func validatedPort(_ port: String) -> UInt16? {
		guard (port as NSString).isValidInternetPort else { return nil }

		return UInt16(port)
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
