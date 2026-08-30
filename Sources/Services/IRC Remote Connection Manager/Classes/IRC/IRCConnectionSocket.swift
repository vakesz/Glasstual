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
import os
import Security
import Synchronization

/// One value, shared by two isolation domains.
///
/// `Mutex` is non-copyable, so it cannot be captured by the escaping closures
/// Network.framework hands its callbacks to; a reference that holds one can be.
/// `Value` is always a value type here — the point is to share a fact, never an
/// object.
final class Locked<Value: Sendable>: Sendable {
	private let storage: Mutex<Value>

	init(_ value: Value) {
		storage = Mutex(value)
	}

	var value: Value {
		storage.withLock { $0 }
	}

	func set(_ value: Value) {
		storage.withLock { $0 = value }
	}
}

/** Logging for the connection classes. */
enum RCMLog {
	static let connection = Logger(
		subsystem: Bundle.main.bundleIdentifier ?? "com.vakesz.glasstual.IRCConnectionHost", category: "Connection"
	)
}

/// Everything the transport reports, in the order it happened.
///
/// The socket turns Network.framework's callbacks into these and the host reads
/// them off one `AsyncStream`. Every case is `Sendable`, which is what lets the
/// callbacks — all of them `@Sendable` in the SDK — hand work to the actor.
enum SocketEvent: Sendable {
	case willConnectToProxy(host: String, port: UInt16)
	case connected(host: String?)
	case secured(protocolVersion: tls_protocol_version_t, cipherSuite: tls_ciphersuite_t)
	case received(Data)
	case willSend(Data)
	case didSend
	case closedReadStream
	case disconnected(ConnectionError?)
}

/// What the service learned about the peer's certificate chain.
///
/// Written by the TLS verify block, which runs outside the socket's actor, and
/// read by the actor when the application asks for it. A value, so it can live
/// in a `Mutex` rather than in one domain or the other — and so the `SecTrust`
/// it came from never leaves the verify block.
struct TLSTrustExport: Sendable {
	var policyName: String?
	var certificateChain: [Data] = []

	/// Why the system did not trust the chain. nil when it did, or when the
	/// chain has not been evaluated yet.
	var failureDescription: String?
}

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
	init(socketError: Error) {
		self = .socket(error: socketError as NSError)
	}

	init(otherError message: String) {
		self = .other(message: message)
	}

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

/// The client side identity a connection presents, when one is configured.
///
/// A pure function of the configuration: the keychain lookup depends on nothing
/// else, so it is done where it is needed rather than cached on an object.
enum ClientSideCertificate {
	static func load(from config: IRCConnectionConfig) -> (identity: SecIdentity, certificate: SecCertificate)? {
		guard let certificateDataIn = config.identityClientSideCertificate else {
			return nil
		}

		var certificateObject: CFTypeRef?

		var status = SecItemCopyMatching(
			[
				kSecClass: kSecClassCertificate,
				kSecValuePersistentRef: certificateDataIn,
				kSecReturnRef: true,
			] as CFDictionary, &certificateObject
		)

		if status != errSecSuccess {
			RCMLog.connection.error("Client certificate lookup failed: \(status, privacy: .public)")

			return nil
		}

		guard let certificateObject,
		      CFGetTypeID(certificateObject) == SecCertificateGetTypeID()
		else {
			return nil
		}
		// Security exposes the typed certificate through a CFTypeRef result.
		let certificateRef = unsafeDowncast(certificateObject, to: SecCertificate.self)

		var identityRef: SecIdentity?

		status = SecIdentityCreateWithCertificate(nil, certificateRef, &identityRef)

		guard status == noErr, let identityRef else {
			RCMLog.connection.error("Client identity lookup failed: \(status, privacy: .public)")

			return nil
		}

		return (identity: identityRef, certificate: certificateRef)
	}
}
