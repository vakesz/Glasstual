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
import Network
import Security
import Synchronization

/// The Network.framework transport, as an actor.
///
/// Every `NWConnection` callback is `@Sendable` in the SDK, so each one does
/// nothing but hand its value to this actor, which owns the connection, the
/// read buffer and the state flags. What the host needs to know comes back out
/// through `events`, in the order it happened.
actor ConnectionSocket {
	/// Maximum bytes requested from the transport in a single read.
	private static let maximumDataLength = 1000 * 1000 * 100 // 100 megabytes

	/// Maximum bytes buffered while waiting for a newline. A peer that never
	/// sends one is disconnected instead of growing memory forever.
	private static let maximumBufferedLineLength = 1024 * 1024 // 1 MiB

	/// Seconds allowed for the transport to reach the ready state.
	private static let connectTimeout: TimeInterval = 30

	private static let torProxyAddress = "127.0.0.1"
	private static let torProxyPort: UInt16 = 9150

	nonisolated let config: IRCConnectionConfig // nonisolated: let
	nonisolated let uniqueIdentifier: String // nonisolated: let

	/// The application, for the one question the transport has to ask mid
	/// handshake. `RemoteConnectionClientProtocol` refines `Sendable`, so the
	/// proxy is as usable from the TLS verify block as it is from the actor.
	private nonisolated let client: any RemoteConnectionClientProtocol // nonisolated: let

	/// What the verify block learned about the peer's chain. The block runs
	/// outside the actor, so this is the one piece of state the two share.
	private nonisolated let trustExport = Locked(TLSTrustExport()) // nonisolated: let

	private let events: AsyncStream<SocketEvent>.Continuation

	private var connection: NWConnection?
	private var readInBuffer = Data()
	private var connectTimeoutTask: Task<Void, Never>?

	private var connecting = false
	private var connected = false
	private var disconnecting = false
	private var secured = false
	private(set) var sending = false

	private var alternateDisconnectError: ConnectionError?

	var disconnected: Bool {
		connecting == false && connected == false
	}

	init(
		config: IRCConnectionConfig,
		client: any RemoteConnectionClientProtocol,
		events: AsyncStream<SocketEvent>.Continuation
	) {
		self.config = config
		self.client = client
		self.events = events

		uniqueIdentifier = UUID().uuidString
	}

	// MARK: - Open/Close

	func open() {
		guard disconnected, disconnecting == false else { return }

		let parameters: NWParameters

		do {
			parameters = try constructedParameters()
		} catch let error as ConnectionError {
			return finish(with: error)
		} catch {
			return finish(with: ConnectionError(socketError: error))
		}

		let connection = NWConnection(
			host: NWEndpoint.Host(config.serverAddress),
			port: NWEndpoint.Port(integerLiteral: config.serverPort),
			using: parameters
		)

		connection.stateUpdateHandler = { [weak self] state in
			Task { await self?.handle(state) }
		}

		self.connection = connection

		if let proxyEndpoint {
			events.yield(.willConnectToProxy(host: proxyEndpoint.host, port: proxyEndpoint.port))
		}

		connecting = true

		scheduleConnectTimeout()

		connection.start(queue: .global(qos: .userInitiated))
	}

	func close() {
		guard disconnected == false, disconnecting == false else { return }

		disconnecting = true

		cancelConnectTimeout()

		connection?.cancel()
	}

	func close(with error: ConnectionError) {
		guard disconnected == false, disconnecting == false else { return }

		alternateDisconnectError = error

		close()
	}

	func close(with message: String) {
		close(with: ConnectionError.other(message: message))
	}

	private func resetState() {
		connecting = false
		connected = false
		disconnecting = false
		secured = false
		sending = false

		alternateDisconnectError = nil

		cancelConnectTimeout()

		connection = nil

		readInBuffer.removeAll()
	}

	// MARK: - Connect Timeout

	private func scheduleConnectTimeout() {
		cancelConnectTimeout()

		connectTimeoutTask = Task { [weak self] in
			try? await Task.sleep(for: .seconds(Self.connectTimeout), clock: .continuous)

			guard Task.isCancelled == false, let self else { return }

			await onConnectTimeout()
		}
	}

	private func cancelConnectTimeout() {
		connectTimeoutTask?.cancel()
		connectTimeoutTask = nil
	}

	private func onConnectTimeout() {
		connectTimeoutTask = nil

		guard connecting, connected == false else { return }

		let identifier = uniqueIdentifier
		let timeout = Self.connectTimeout

		RCMLog.connection.error(
			"Connection \(identifier, privacy: .public) timed out after \(timeout, privacy: .public) seconds"
		)

		close(with: String(localized: .ConnectionErrors.connectionTimedOut))
	}

	// MARK: - State

	private func handle(_ state: NWConnection.State) {
		switch state {
		case .setup, .preparing:
			break
		case let .waiting(error):
			/* Waiting is not fatal. The path may become viable (network comes
			 back, proxy starts answering); the connect timeout bounds how long
			 we are willing to wait. */
			let identifier = uniqueIdentifier
			let reason = error.localizedDescription

			RCMLog.connection.notice(
				"Connection \(identifier, privacy: .public) waiting: \(reason, privacy: .public)"
			)
		case .ready:
			onConnect()
		case .cancelled:
			onDisconnect(with: nil)
		case let .failed(error):
			onDisconnect(with: error)
		@unknown default:
			break
		}
	}

	private func onConnect() {
		cancelConnectTimeout()

		connecting = false
		connected = true

		read()

		/* When a proxy is in use the remote endpoint is the proxy, not the
		 server, so report nil as the host contract asks. */
		events.yield(.connected(host: proxyEndpoint == nil ? connectedHost : nil))

		onSecured()
	}

	private func onSecured() {
		/* Only mark ourselves secured once there is protocol information. */
		guard let protocolVersion = tlsNegotiatedProtocol, let cipherSuite = tlsNegotiatedCipherSuite else {
			return
		}

		secured = true

		events.yield(.secured(protocolVersion: protocolVersion, cipherSuite: cipherSuite))
	}

	private func onDisconnect(with error: Error?) {
		var payload: ConnectionError?

		if let alternateDisconnectError {
			payload = alternateDisconnectError
		} else if let nwError = error as? NWError {
			payload = translateError(nwError)
		} else if let error {
			payload = ConnectionError(socketError: error)
		}

		resetState()

		events.yield(.disconnected(payload))
	}

	/// The failure paths that never reached a connection at all.
	private func finish(with error: ConnectionError) {
		resetState()

		events.yield(.disconnected(error))
	}

	// MARK: - Read & Write

	private func read() {
		guard connected, disconnecting == false else { return }

		/* A minimum of one lets the receive complete with neither content nor
		 error, which the handler treats as a fatal condition. */
		connection?.receive(
			minimumIncompleteLength: 1,
			maximumLength: Self.maximumDataLength,
			completion: { [weak self] content, context, isComplete, error in
				Task { await self?.didRead(content, context?.isFinal == true, isComplete, error) }
			}
		)
	}

	private func didRead(_ content: Data?, _ isFinalContext: Bool, _ isComplete: Bool, _ error: NWError?) {
		guard disconnecting == false else { return }

		if let error {
			return close(with: translateError(error))
		}

		if isFinalContext, isComplete {
			/* The final bytes (typically an ERROR line with the reason for the
			 disconnect) can arrive together with the EOF. */
			if let content, content.isEmpty == false {
				readIn(content)
			}

			events.yield(.closedReadStream)

			return
		}

		guard let content else {
			return close(with: "Unexpected condition: There is no data when there is no error")
		}

		readIn(content)

		read()
	}

	private func readIn(_ data: Data) {
		guard disconnected == false, disconnecting == false else { return }

		readInBuffer.append(data)

		guard let (lines, remainingData) = readInBuffer.splitNetworkLines() else {
			return
		}

		for line in lines {
			events.yield(.received(line))
		}

		if let remainder = remainingData {
			/* The remainder is a slice of the old buffer. Copying it into a
			 fresh Data rebases indices to zero and releases the storage holding
			 the lines already delivered. */
			readInBuffer = Data(remainder)
		} else {
			readInBuffer.removeAll(keepingCapacity: true)
		}

		if readInBuffer.count > Self.maximumBufferedLineLength {
			let identifier = uniqueIdentifier
			let bufferedByteCount = readInBuffer.count

			RCMLog.connection.error(
				"Connection \(identifier, privacy: .public) buffered \(bufferedByteCount, privacy: .public) bytes without a newline"
			)

			close(with: String(localized: .ConnectionErrors.peerLineTooLong))
		}
	}

	func write(_ data: Data) {
		guard connected, disconnecting == false else { return }

		/* We only allow one write at a time. */
		guard sending == false else { return }

		sending = true

		events.yield(.willSend(data))

		connection?.send(content: data, completion: .contentProcessed { [weak self] error in
			Task { await self?.didWrite(error) }
		})
	}

	private func didWrite(_ error: NWError?) {
		guard disconnecting == false else { return }

		sending = false

		if let error {
			return close(with: translateError(error))
		}

		events.yield(.didSend)
	}

	// MARK: - Secure Connection Information

	/// What the application shows in its certificate panels. The `SecTrust` the
	/// chain came from stayed in the verify block; this is all values.
	func secureConnectionInformation() -> SecureConnectionInformation {
		let export = trustExport.value

		return SecureConnectionInformation(
			policyName: export.policyName ?? (config.serverAddress.isIPAddress ? config.serverAddress : nil),
			protocolVersion: tlsNegotiatedProtocol ?? tlsProtocolVersionUnknown,
			cipherSuite: tlsNegotiatedCipherSuite ?? tlsCipherSuiteUnknown,
			certificateChain: export.certificateChain,
			trustFailureDescription: export.failureDescription
		)
	}

	private var tlsNegotiatedProtocol: tls_protocol_version_t? {
		tlsMetadata.map(sec_protocol_metadata_get_negotiated_tls_protocol_version)
	}

	private var tlsNegotiatedCipherSuite: tls_ciphersuite_t? {
		tlsMetadata.map(sec_protocol_metadata_get_negotiated_tls_ciphersuite)
	}

	private var tlsMetadata: sec_protocol_metadata_t? {
		guard let metadata = connection?.metadata(definition: NWProtocolTLS.definition) as? NWProtocolTLS.Metadata
		else {
			return nil
		}

		return metadata.securityProtocolMetadata
	}

	private var connectedHost: String? {
		guard case let .hostPort(host, _)? = connection?.currentPath?.remoteEndpoint else { return nil }

		switch host {
		case let .name(address, _):
			return address
		case let .ipv4(address):
			return address.rawValue.IPv4Address
		case let .ipv6(address):
			return address.rawValue.IPv6Address
		@unknown default:
			return nil
		}
	}
}

// MARK: - Parameters

extension ConnectionSocket {
	private var proxyEndpoint: (host: String, port: UInt16)? {
		switch config.proxyType {
		case .socks5, .HTTP:
			guard let host = config.proxyAddress, host.isEmpty == false else {
				return nil
			}

			return (host: host, port: config.proxyPort)
		case .tor:
			return (host: Self.torProxyAddress, port: Self.torProxyPort)
		case .none, .automatic:
			return nil
		@unknown default:
			return nil
		}
	}

	private func constructedParameters() throws -> NWParameters {
		let parameters: NWParameters = if config.connectionPrefersSecuredConnection {
			NWParameters(tls: constructedTLSOptions())
		} else {
			.tcp
		}

		try applyProxy(to: parameters)

		if let internetProtocol = parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
			switch config.addressType {
			case .v4:
				internetProtocol.version = .v4
			case .v6:
				internetProtocol.version = .v6
			default:
				break
			}
		}

		return parameters
	}

	private func constructedTLSOptions() -> NWProtocolTLS.Options {
		let tlsOptions = NWProtocolTLS.Options()
		let secOptions = tlsOptions.securityProtocolOptions

		if let clientCertificate = ClientSideCertificate.load(from: config) {
			let identity = sec_identity_create_with_certificates(
				clientCertificate.identity,
				[clientCertificate.certificate] as CFArray
			)

			if let identity {
				sec_protocol_options_set_local_identity(secOptions, identity)
			}
		}

		if config.cipherSuites == .none {
			sec_protocol_options_append_tls_ciphersuite_group(secOptions, .default)
		} else {
			SecureTransportSupport.appendCipherSuites(
				inCollection: config.cipherSuites,
				includeDeprecated: config.connectionPrefersModernCiphersOnly == false,
				to: secOptions
			)
		}

		sec_protocol_options_set_min_tls_protocol_version(secOptions, SecureTransportSupport.minimumProtocolType)

		installVerifyBlock(on: secOptions)

		return tlsOptions
	}

	private func applyProxy(to parameters: NWParameters) throws {
		switch config.proxyType {
		case .none:
			parameters.preferNoProxies = true
		case .automatic:
			/* The default privacy context consults the system proxy settings
			 (including PAC) so there is nothing to configure. */
			parameters.preferNoProxies = false
		case .socks5, .HTTP, .tor:
			guard let endpoint = proxyEndpoint else {
				throw ConnectionError.other(message: String(localized: .ConnectionErrors.proxyAddressMissing))
			}

			let nwEndpoint = NWEndpoint.hostPort(
				host: NWEndpoint.Host(endpoint.host),
				port: NWEndpoint.Port(integerLiteral: endpoint.port)
			)

			var proxyConfiguration = if config.proxyType == .HTTP {
				ProxyConfiguration(httpCONNECTProxy: nwEndpoint)
			} else {
				ProxyConfiguration(socksv5Proxy: nwEndpoint)
			}

			/* A proxy the user asked for must be used; never fall back to a
			 direct connection. */
			proxyConfiguration.allowFailover = false

			if config.proxyType != .tor,
			   let username = config.proxyUsername, username.isEmpty == false,
			   let password = config.proxyPassword, password.isEmpty == false
			{
				proxyConfiguration.applyCredential(username: username, password: password)
			}

			let privacyContext = NWParameters.PrivacyContext(description: "Glasstual.IRCConnection.\(uniqueIdentifier)")

			privacyContext.proxyConfigurations = [proxyConfiguration]

			parameters.setPrivacyContext(privacyContext)

			parameters.preferNoProxies = false
		@unknown default:
			throw ConnectionError.other(message: String(localized: .ConnectionErrors.unsupportedProxyType))
		}
	}

	private func translateError(_ error: NWError) -> ConnectionError {
		switch error {
		case let .dns(errorCode):
			ConnectionError(nwDNSError: errorCode)
		case let .posix(errorCode):
			ConnectionError(nwPOSIXError: errorCode.rawValue)
		case let .tls(errorCode):
			ConnectionError(nwTLSError: errorCode)
		case .wifiAware:
			ConnectionError(otherError: "Wi-Fi Aware error")
		@unknown default:
			ConnectionError(otherError: error.localizedDescription)
		}
	}
}

// MARK: - Trust

private extension ConnectionSocket {
	/// Installs the block Network.framework calls with the peer's chain.
	///
	/// The block runs outside the actor, on a queue of its own, and everything
	/// it touches is `Sendable`: the configuration, the client proxy, and the
	/// `Mutex` it records the exported chain in. The `SecTrust` is created,
	/// evaluated and released inside one call and reaches nothing else.
	nonisolated func installVerifyBlock(on options: sec_protocol_options_t) { // nonisolated: pure
		let config = config
		let client = client
		let trustExport = trustExport

		sec_protocol_options_set_verify_block(
			options,
			{ _, trust, complete in
				/* sec_trust_copy_ref() follows the Create Rule; the result is +1. */
				let trustRef = sec_trust_copy_ref(trust).takeRetainedValue()

				var evaluationError: CFError?
				let trusted = SecTrustEvaluateWithError(trustRef, &evaluationError)
				let failureDescription = trusted
					? nil
					: ((evaluationError as Error?)?.localizedDescription ?? "Unknown error")

				/* Export what the application will need before answering, so
				 that a trust panel asking for it is never told "nothing yet". */
				trustExport.set(
					TLSTrustExport(
						policyName: SecureTransportSupport.policyName(in: trustRef),
						certificateChain: SecureTransportSupport.certificates(in: trustRef) ?? [],
						failureDescription: failureDescription
					)
				)

				guard let failureDescription else {
					return complete(true)
				}

				let serverAddress = config.serverAddress

				guard config.connectionShouldValidateCertificateChain else {
					RCMLog.connection.error(
						"Certificate chain for '\(serverAddress, privacy: .public)' failed validation but the connection is configured to ignore that: \(failureDescription, privacy: .public)"
					)

					return complete(true)
				}

				RCMLog.connection.error(
					"Certificate chain for '\(serverAddress, privacy: .public)' failed validation: \(failureDescription, privacy: .public)"
				)

				var evaluationResult: SecTrustResultType = .invalid
				SecTrustGetTrustResult(trustRef, &evaluationResult)

				guard evaluationResult == .recoverableTrustFailure else {
					return complete(false)
				}

				complete(Self.askClientAboutTrust(client))
			},
			DispatchQueue.global(qos: .userInitiated)
		)
	}

	/// Asks the application whether to trust a chain the system would not, and
	/// waits for the answer.
	///
	/// Network.framework's verify block is synchronous and its completion is
	/// not `Sendable`, so the answer cannot be carried into a task and handed
	/// back later: the block has to still be on the stack when it arrives. The
	/// wait happens on the verify block's own global-queue thread, never on the
	/// socket's actor or on the connection's own queue, and it only ever
	/// happens while a certificate panel is in front of the user.
	nonisolated static func askClientAboutTrust( // nonisolated: pure
		_ client: any RemoteConnectionClientProtocol
	) -> Bool {
		let answer = Locked(false)
		let arrived = DispatchSemaphore(value: 0)

		client.ircConnectionRequestInsecureCertificateTrust { trusted in
			answer.set(trusted)

			arrived.signal()
		}

		arrived.wait()

		return answer.value
	}
}

// MARK: - Error Translation

private extension ConnectionError {
	static let dnsErrorReasons: [Int: String] = [
		kDNSServiceErr_NoError: "No error",
		kDNSServiceErr_NoSuchName: "No such name",
		kDNSServiceErr_NoMemory: "No memory",
		kDNSServiceErr_BadParam: "Bad parameter",
		kDNSServiceErr_BadReference: "Bad reference",
		kDNSServiceErr_BadState: "Bad state",
		kDNSServiceErr_BadFlags: "Bad flags",
		kDNSServiceErr_Unsupported: "Unsupported",
		kDNSServiceErr_NotInitialized: "Not initialized",
		kDNSServiceErr_AlreadyRegistered: "Already registered",
		kDNSServiceErr_NameConflict: "Name conflict",
		kDNSServiceErr_Invalid: "Invalid",
		kDNSServiceErr_Firewall: "Firewall",
		kDNSServiceErr_Incompatible: "Incompatible",
		kDNSServiceErr_BadInterfaceIndex: "Bad interface index",
		kDNSServiceErr_Refused: "Refused",
		kDNSServiceErr_NoSuchRecord: "No such record",
		kDNSServiceErr_NoAuth: "No authentication",
		kDNSServiceErr_NoSuchKey: "No such key",
		kDNSServiceErr_NATTraversal: "NAT traversal",
		kDNSServiceErr_DoubleNAT: "Double NAT",
		kDNSServiceErr_BadTime: "Bad time",
		kDNSServiceErr_BadSig: "Bad signature",
		kDNSServiceErr_BadKey: "Bad key",
		kDNSServiceErr_Transient: "Transient",
		kDNSServiceErr_ServiceNotRunning: "Service not running",
		kDNSServiceErr_NATPortMappingUnsupported: "NAT port mapping unsupported",
		kDNSServiceErr_NATPortMappingDisabled: "NAT port mapping disabled",
		kDNSServiceErr_NoRouter: "No router",
		kDNSServiceErr_PollingMode: "Polling mode",
		kDNSServiceErr_Timeout: "Timeout",
	]

	init(nwDNSError: DNSServiceErrorType) {
		let errorCode = Int(nwDNSError)
		let errorReason = Self.dnsErrorReasons[errorCode] ?? "Unknown"

		let errorMessage = ConnectionErrorLocalization.formatted(
			.ConnectionErrors.dnsError(errorReason, errorCode),
			errorReason,
			errorCode
		)

		let nsError = NSError(
			domain: "NWErrorDomainDNS",
			code: errorCode,
			userInfo: [NSLocalizedDescriptionKey: errorMessage]
		)

		self.init(socketError: nsError)
	}

	init(nwPOSIXError: Int32) {
		let errorCode = Int(nwPOSIXError)

		let errorReason = if let errorReasonC = strerror(nwPOSIXError) {
			String(cString: errorReasonC)
		} else {
			"Unknown"
		}

		let errorMessage = ConnectionErrorLocalization.formatted(
			.ConnectionErrors.posixError(errorReason, errorCode),
			errorReason,
			errorCode
		)

		let nsError = NSError(
			domain: "NWErrorDomainPOSIX",
			code: errorCode,
			userInfo: [NSLocalizedDescriptionKey: errorMessage]
		)

		self.init(socketError: nsError)
	}

	init(nwTLSError: OSStatus) {
		self.init(tlsError: Int(nwTLSError))
	}
}

private enum ConnectionErrorLocalization {
	static func formatted(_ resource: LocalizedStringResource, _ arguments: CVarArg...) -> String {
		let bundle = Bundle(for: ConnectionErrorLocalizationBundleToken.self)
		let format = bundle.localizedString(forKey: resource.key, value: nil, table: resource.table)
		return String(format: format, arguments: arguments)
	}
}

private final class ConnectionErrorLocalizationBundleToken {}
