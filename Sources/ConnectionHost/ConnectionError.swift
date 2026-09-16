/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2018 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *  * Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *  * Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *  * Neither the name of Textual, "Codeux Software, LLC", nor the
 *    names of its contributors may be used to endorse or promote products
 *    derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 *********************************************************************** */

import CocoaExtensions
import Foundation

/// Why a connection ended.
enum ConnectionError: Error, Sendable {
	/// Errors returned by the connection library. For example: Network.framework.
	case socket(error: NSError)

	/// Errors the transport itself raised.
	case other(message: String)

	/// The connection could not be secured because of a problem with the
	/// server's certificate.
	case badCertificate(failureReason: String)

	/// The connection could not be secured for some other reason, such as a
	/// handshake failure.
	case unableToSecure(failureReason: String)
}

extension ConnectionError {
	init?(tlsError error: Error) {
		let nsError = error as NSError
		if SecureTransportSupport.isTLSError(nsError) == false {
			return nil
		}

		self.init(tlsError: nsError.code)
	}

	/// init(tlsError:) returns .unableToSecure("Unknown") for out of range error codes
	init(tlsError errorCode: Int) {
		if let certError = SecureTransportSupport.description(forBadCertificateErrorCode: errorCode) {
			self = .badCertificate(failureReason: certError)

			return
		}

		let tlsError = SecureTransportSupport.description(forErrorCode: errorCode)

		self = .unableToSecure(failureReason: tlsError)
	}
}

extension ConnectionError: CustomNSError {
	/** Error domain and codes are shared with the app across the XPC boundary. */
	static let errorDomain = connectionErrorDomain

	var errorCode: Int {
		let errorCode: ConnectionErrorCode = switch self {
		case .socket:
			.socket
		case .other:
			.other
		case .badCertificate:
			.badCertificate
		case .unableToSecure:
			.unableToSecure
		}

		return Int(errorCode.rawValue)
	}

	var errorUserInfo: [String: Any] {
		var userInfo: [String: Any] = [:]

		if let errorDescription {
			userInfo[NSLocalizedDescriptionKey] = errorDescription
		}

		// While we don't make use of it right now, pass the original
		// error inside the user info dictionary because at a later
		// time, we may be interested in its contents. Only the
		// domain, code, and description are kept so that the error
		// is guaranteed to survive secure coding across XPC.
		if case let .socket(error) = self {
			userInfo["UnderlyingSocketError"] = NSError(
				domain: error.domain,
				code: error.code,
				userInfo: [NSLocalizedDescriptionKey: error.localizedDescription]
			)
		}

		return userInfo
	}
}

extension ConnectionError: LocalizedError {
	var errorDescription: String? {
		switch self {
		case let .socket(error):
			/* The underlying socket error is almost always an NSError
			 which means we can just ask for its localized description. */
			error.localizedDescription
		case let .other(message),
		     let .badCertificate(message),
		     let .unableToSecure(message):
			message
		}
	}
}
