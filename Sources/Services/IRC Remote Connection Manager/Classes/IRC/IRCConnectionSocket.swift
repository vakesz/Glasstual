/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
 *
 *    Copyright (c) 2018 Codeux Software, LLC & respective contributors.
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
import Network
import os
import Security

/** Logging for the connection classes. `Logger` is Sendable which keeps
 these usable from queue-confined code under strict concurrency. */
enum RCMLog {
	static let connection = Logger(
		subsystem: Bundle.main.bundleIdentifier ?? "com.vakesz.glasstual.IRCConnectionHost", category: "Connection"
	)
}

/** ConnectionSocket holds the state and helpers shared by the transport
 layer. ConnectionSocketNWF is the only transport; it subclasses this to
 talk to Network.framework.

 Concurrency model:
 Every stored property below, and in the subclass, is confined to `queue`.
 The owner (Connection) creates the queue, hands it in, and hops onto it
 before calling any method. Network.framework delivers all callbacks on
 that same queue because it is the queue passed to NWConnection.start(queue:).
 Because of this confinement the class is `@unchecked Sendable`; the
 compiler cannot verify queue confinement but the invariant is simple:
 do not touch state off `queue`. */
class ConnectionSocket: @unchecked Sendable {
	weak var delegate: ConnectionSocketDelegate?

	final let config: IRCConnectionConfig

	final let uniqueIdentifier: String

	/// The serial queue all state is confined to.
	final let queue: DispatchQueue

	var connecting = false
	var connected = false
	var disconnecting = false
	var disconnected: Bool {
		connecting == false && connected == false
	}

	var secured = false
	var sending = false

	var alternateDisconnectError: ConnectionError?

	/// Why the system did not trust the server's certificate chain.
	/// nil when the chain was trusted or has not been evaluated yet.
	var tlsTrustFailureDescription: String?

	final let torProxyTypeAddress = "127.0.0.1"
	final let torProxyTypePort: UInt16 = 9150

	/// Maximum bytes requested from the transport in a single read.
	final let maximumDataLength = (1000 * 1000 * 100) // 100 megabytes

	/// Maximum bytes buffered while waiting for a newline. A peer that
	/// never sends one is disconnected instead of growing memory forever.
	final let maximumBufferedLineLength = (1024 * 1024) // 1 MiB

	/// Seconds allowed for the transport to reach the ready state.
	final let connectTimeout: TimeInterval = 30

	init(with config: IRCConnectionConfig, on queue: DispatchQueue) {
		self.config = config

		self.queue = queue

		uniqueIdentifier = UUID().uuidString
	}

	func resetState() {
		connecting = false
		connected = false
		disconnecting = false
		secured = false

		sending = false

		alternateDisconnectError = nil
	}

	func tlsVerify(_ trust: SecTrust, response: @escaping TrustDecisionHandler) {
		var error: CFError?

		/* The evaluation always runs, even when the connection is configured
		 to ignore certificate errors, so that the failure reason can be
		 logged and reported to the client. */
		if SecTrustEvaluateWithError(trust, &error) {
			tlsTrustFailureDescription = nil

			response(true)

			return
		}

		let failureDescription = (error as Error?)?.localizedDescription ?? "Unknown error"
		let serverAddress = config.serverAddress

		tlsTrustFailureDescription = failureDescription

		if config.connectionShouldValidateCertificateChain == false {
			RCMLog.connection.error(
				"Certificate chain for '\(serverAddress, privacy: .public)' failed validation but the connection is configured to ignore that: \(failureDescription, privacy: .public)"
			)

			response(true)

			return
		}

		RCMLog.connection.error(
			"Certificate chain for '\(serverAddress, privacy: .public)' failed validation: \(failureDescription, privacy: .public)"
		)

		var evaluationResult: SecTrustResultType = .invalid

		SecTrustGetTrustResult(trust, &evaluationResult)

		if evaluationResult == .recoverableTrustFailure {
			delegate?.connection(self, requiresTrust: response)

			return
		}

		response(false)
	}

	/// The client side identity, if one is configured.
	/// The keychain is consulted once; the result is cached for the
	/// life of the socket because a handshake asks for it more than once.
	private(set) final lazy var clientSideCertificate: (identity: SecIdentity, certificate: SecCertificate)? =
		loadClientSideCertificate()

	private func loadClientSideCertificate() -> (identity: SecIdentity, certificate: SecCertificate)? {
		guard let certificateDataIn = config.identityClientSideCertificate else {
			return nil
		}

		/* ====================================== */

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

		/* ====================================== */

		var identityRef: SecIdentity?

		status = SecIdentityCreateWithCertificate(nil, certificateRef, &identityRef)

		guard status == noErr, let identityRef else {
			RCMLog.connection.error("Client identity lookup failed: \(status, privacy: .public)")

			return nil
		}

		/* ====================================== */

		return (identity: identityRef, certificate: certificateRef)
	}
}

extension ConnectionError {
	init(socketError: Error) {
		self = .socket(error: socketError)
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

/** All delegate methods are invoked on the socket's queue. */
protocol ConnectionSocketDelegate: AnyObject {
	func connection(_ connection: ConnectionSocket, willConnectToProxy address: String, on port: UInt16)
	func connection(_ connection: ConnectionSocket, willConnectTo address: String, on port: UInt16)
	// The address is nil when connecting to a proxy.
	func connection(_ connection: ConnectionSocket, didConnectTo address: String?)
	func connection(
		_ connection: ConnectionSocket, securedWith protocol: tls_protocol_version_t, cipherSuite: tls_ciphersuite_t
	)
	func connection(_ connection: ConnectionSocket, requiresTrust response: @escaping (Bool) -> Void)
	func connectionClosedReadStream(_ connection: ConnectionSocket)
	func connectionDisconnected(_ connection: ConnectionSocket)
	func connection(_ connection: ConnectionSocket, disconnectedWith error: ConnectionError)
	func connection(_ connection: ConnectionSocket, received data: Data)
	func connection(_ connection: ConnectionSocket, willSend data: Data)
	func connectionDidSend(_ connection: ConnectionSocket)
}

protocol ConnectionSocketProtocol {
	/// Logic for opening socket
	func open()

	/// Logic for closing socket
	func close()
	func close(with error: String)
	func close(with error: ConnectionError)

	/// Logic for writing data (sending)
	func write(_ data: Data)

	/// Logic for waiting for data (receiving)
	func read()

	/// Logic for reading data from socket (receiving)
	func readIn(_ data: Data)

	/// Logic for providing upstream with information
	/// about the secured connection including policy name,
	/// protocol version, cipher suite, and certificates.
	func exportSecureConnectionInformation(to receiver: SecureConnectionInformationReceiver) throws

	/// TLS Information
	var tlsNegotiatedProtocol: tls_protocol_version_t? { get }
	var tlsNegotiatedCipherSuite: tls_ciphersuite_t? { get }
	var tlsCertificateChainData: [Data]? { get }
	var tlsPolicyName: String? { get }
}

extension ConnectionSocketProtocol where Self: ConnectionSocket {
	func close(with error: String) {
		let errorEnum = ConnectionError.other(message: error)

		close(with: errorEnum)
	}

	func close(with error: ConnectionError) {
		if disconnected || disconnecting {
			return
		}

		alternateDisconnectError = error

		close()
	}

	func exportSecureConnectionInformation(to receiver: SecureConnectionInformationReceiver) throws {
		let policyName = tlsPolicyName

		let protocolType = tlsNegotiatedProtocol ?? tlsProtocolVersionUnknown

		let cipherSuite = tlsNegotiatedCipherSuite ?? tlsCipherSuiteUnknown

		let certificateChain = tlsCertificateChainData ?? []

		receiver(policyName, protocolType, cipherSuite, certificateChain, tlsTrustFailureDescription)
	}
}
