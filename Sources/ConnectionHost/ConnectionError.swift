// Copyright (c) 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

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
