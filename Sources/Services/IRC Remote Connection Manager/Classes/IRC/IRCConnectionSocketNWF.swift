/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2018, 2019 Codeux Software, LLC & respective contributors.
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

/** ConnectionSocketNWF is the Network.framework transport.
 See ConnectionSocket for the queue confinement rules; every method
 here runs on `queue`, including the NWConnection callbacks. */
final class ConnectionSocketNWF: ConnectionSocket, ConnectionSocketProtocol, @unchecked Sendable {
	fileprivate var readInBuffer = Data()

	fileprivate var connection: NWConnection?

	fileprivate var connectTimeoutTask: Task<Void, Never>?

	fileprivate var trustRef: SecTrust?
	/** Security.framework's completion is a C block, so it is not `Sendable`.
	 It stays here, on the queue-confined socket, and the sendable callback the
	 trust decision travels through refers to this socket instead: the block
	 itself never crosses an isolation boundary. */
	private var pendingTLSVerifyCompletion: sec_protocol_verify_complete_t?

	// MARK: - Open/Close Socket

	fileprivate func constructedParameters() throws -> NWParameters {
		let parameters: NWParameters = if config.connectionPrefersSecuredConnection {
			NWParameters(tls: constructedTLSOptions)
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

	fileprivate var constructedTLSOptions: NWProtocolTLS.Options {
		let tlsOptions = NWProtocolTLS.Options()

		let secOptions = tlsOptions.securityProtocolOptions

		if let localIdentity = tlsLocalIdentity {
			sec_protocol_options_set_local_identity(secOptions, localIdentity)
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

		sec_protocol_options_set_verify_block(
			secOptions,
			{ [weak self] _, trust, completionBlock in
				self?.tlsVerifySecProtocol(trust, response: completionBlock)
			}, queue
		)

		return tlsOptions
	}

	func open() {
		if disconnected == false || disconnecting {
			return
		}

		let serverAddress = config.serverAddress
		let serverPort = config.serverPort

		let parameters: NWParameters

		do {
			parameters = try constructedParameters()
		} catch let error as ConnectionError {
			delegate?.connection(self, disconnectedWith: error)

			return
		} catch {
			delegate?.connection(self, disconnectedWith: ConnectionError(socketError: error))

			return
		}

		let connection = NWConnection(
			host: NWEndpoint.Host(serverAddress),
			port: NWEndpoint.Port(integerLiteral: serverPort),
			using: parameters
		)

		connection.stateUpdateHandler = { [weak self] state in
			self?.statusUpdateHandler(state)
		}

		self.connection = connection

		if let proxyEndpoint {
			delegate?.connection(self, willConnectToProxy: proxyEndpoint.host, on: proxyEndpoint.port)
		} else {
			delegate?.connection(self, willConnectTo: serverAddress, on: serverPort)
		}

		connect()
	}

	fileprivate func connect() {
		connecting = true

		scheduleConnectTimeout()

		connection?.start(queue: queue)
	}

	func close() {
		if disconnected || disconnecting {
			return
		}

		disconnecting = true

		cancelConnectTimeout()

		connection?.cancel()
	}

	fileprivate func close(with error: NWError) {
		close(with: translateError(error))
	}

	override func resetState() {
		super.resetState()

		cancelConnectTimeout()

		connection = nil

		readInBuffer.removeAll()

		trustRef = nil
	}

	// MARK: - Connect Timeout

	fileprivate func scheduleConnectTimeout() {
		cancelConnectTimeout()

		let timeout = Duration.seconds(connectTimeout)
		let queue = queue

		connectTimeoutTask = Task { [weak self] in
			try? await Task.sleep(for: timeout, clock: .continuous)

			guard Task.isCancelled == false, let self else {
				return
			}

			/* Back onto the socket's queue: everything the timeout inspects and
			 closes is confined to it. */
			queue.async {
				self.onConnectTimeout()
			}
		}
	}

	fileprivate func cancelConnectTimeout() {
		connectTimeoutTask?.cancel()

		connectTimeoutTask = nil
	}

	fileprivate func onConnectTimeout() {
		connectTimeoutTask = nil
		let connectionIdentifier = uniqueIdentifier
		let timeout = connectTimeout

		if connecting == false || connected {
			return
		}

		RCMLog.connection.error(
			"Connection \(connectionIdentifier, privacy: .public) timed out after \(timeout, privacy: .public) seconds"
		)

		let errorMessage = String(localized: .ConnectionErrors.connectionTimedOut)

		close(with: errorMessage)
	}

	// MARK: - Proxy

	/// The proxy the transport will connect through, after resolving
	/// the Tor shortcut. nil when no explicit proxy is configured.
	fileprivate var proxyEndpoint: (host: String, port: UInt16)? {
		switch config.proxyType {
		case .socks5, .HTTP:
			guard let host = config.proxyAddress, host.isEmpty == false else {
				return nil
			}

			return (host: host, port: config.proxyPort)
		case .tor:
			return (host: torProxyTypeAddress, port: torProxyTypePort)
		case .none, .automatic:
			return nil
		@unknown default:
			return nil
		}
	}

	fileprivate func applyProxy(to parameters: NWParameters) throws {
		switch config.proxyType {
		case .none:
			parameters.preferNoProxies = true
		case .automatic:
			/* The default privacy context consults the system proxy
			 settings (including PAC) so there is nothing to configure. */
			parameters.preferNoProxies = false
		case .socks5, .HTTP, .tor:
			guard let endpoint = proxyEndpoint else {
				throw ConnectionError.other(
					message: String(localized: .ConnectionErrors.proxyAddressMissing)
				)
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

			/* A proxy the user asked for must be used; never fall back to a direct connection. */
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
			throw ConnectionError.other(
				message: String(localized: .ConnectionErrors.unsupportedProxyType)
			)
		}
	}

	// MARK: - Socket Read & Write

	func read() {
		if connected == false || disconnecting {
			return
		}

		/* A minimum of zero lets the receive complete with neither content nor error,
		 which the completion handler treats as a fatal condition. */
		connection?.receive(
			minimumIncompleteLength: 1,
			maximumLength: maximumDataLength,
			completion: { [weak self] content, contentContext, isComplete, error in
				self?.readCompletionHandler(content, contentContext, isComplete, error)
			}
		)
	}

	func readIn(_ data: Data) {
		if disconnected || disconnecting {
			return
		}

		readInBuffer.append(data)

		guard let (lines, remainingData) = readInBuffer.splitNetworkLines() else {
			return
		}

		for line in lines {
			delegate?.connection(self, received: line)
		}

		if let remainder = remainingData {
			/* The remainder is a slice of the old buffer. Copying it into
			 a fresh Data rebases indices to zero and releases the storage
			 holding the lines already delivered. */
			readInBuffer = Data(remainder)
		} else {
			readInBuffer.removeAll(keepingCapacity: true)
		}

		if readInBuffer.count > maximumBufferedLineLength {
			let connectionIdentifier = uniqueIdentifier
			let bufferedByteCount = readInBuffer.count

			RCMLog.connection.error(
				"Connection \(connectionIdentifier, privacy: .public) buffered \(bufferedByteCount, privacy: .public) bytes without a newline"
			)

			let errorMessage = String(localized: .ConnectionErrors.peerLineTooLong)

			close(with: errorMessage)
		}
	}

	func write(_ data: Data) {
		if connected == false || disconnecting {
			return
		}

		/* We only allow one write a time */
		if sending {
			return
		}

		sending = true

		delegate?.connection(self, willSend: data)

		connection?.send(
			content: data,
			completion: .contentProcessed { [weak self] error in
				self?.writeCompletionHandler(error)
			}
		)
	}

	// MARK: - Properties

	fileprivate var connectedHost: String? {
		guard let endpoint = connection?.currentPath?.remoteEndpoint else {
			return nil
		}

		if case let .hostPort(host, _) = endpoint {
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

		return nil
	}

	fileprivate func onConnect() {
		cancelConnectTimeout()

		connecting = false
		connected = true

		read()

		/* When a proxy is in use the remote endpoint is the proxy,
		 not the server, so report nil as the delegate contract asks. */
		let host = (proxyEndpoint == nil) ? connectedHost : nil

		delegate?.connection(self, didConnectTo: host)

		onSecured()
	}

	fileprivate func onSecured() {
		/* We call onSecured() regardless of other preconditions then
		 only mark ourselves as secured if we have protocol information. */
		guard let protocolType = tlsNegotiatedProtocol,
		      let cipherSuite = tlsNegotiatedCipherSuite
		else {
			return
		}

		secured = true

		delegate?.connection(self, securedWith: protocolType, cipherSuite: cipherSuite)
	}

	fileprivate func onDisconnect(with error: Error?) {
		defer {
			resetState()
		}

		var errorPayload: ConnectionError?

		if let alternateError = alternateDisconnectError {
			errorPayload = alternateError
		} else if let nwError = error as? NWError {
			errorPayload = translateError(nwError)
		} else if let error {
			errorPayload = ConnectionError(socketError: error)
		}

		if let errorPayload {
			delegate?.connection(self, disconnectedWith: errorPayload)
		} else {
			delegate?.connectionDisconnected(self)
		}
	}

	// NWConnection Delegate

	final func readCompletionHandler(
		_ content: Data?, _ contentContext: NWConnection.ContentContext?, _ isComplete: Bool, _ error: NWError?
	) {
		if disconnecting {
			return
		}

		if let error {
			close(with: error)

			return
		}

		if contentContext?.isFinal == true, isComplete {
			/* The final bytes (typically an ERROR line with the reason
			 for the disconnect) can arrive together with the EOF. */
			if let content, content.isEmpty == false {
				readIn(content)
			}

			delegate?.connectionClosedReadStream(self)

			return
		}

		guard let content else {
			close(with: "Unexpected condition: There is no data when there is no error")

			return
		}

		readIn(content)

		read()
	}

	final func writeCompletionHandler(_ error: NWError?) {
		if disconnecting {
			return
		}

		sending = false

		if let error {
			close(with: error)

			return
		}

		delegate?.connectionDidSend(self)
	}

	final func statusUpdateHandler(_ status: NWConnection.State) {
		switch status {
		case .setup, .preparing:
			break
		case let .waiting(error):
			/* Waiting is not fatal. The path may become viable (network
			 comes back, proxy starts answering); the connect timeout
			 bounds how long we are willing to wait. */
			let connectionIdentifier = uniqueIdentifier
			let errorDescription = error.localizedDescription

			RCMLog.connection
				.notice(
					"Connection \(connectionIdentifier, privacy: .public) waiting: \(errorDescription, privacy: .public)"
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

	// MARK: - Security

	final func tlsVerifySecProtocol(_ trust: sec_trust_t, response: @escaping sec_protocol_verify_complete_t) {
		/* sec_trust_copy_ref() follows the Create Rule; the result is +1. */
		let trustRef = sec_trust_copy_ref(trust).takeRetainedValue()

		self.trustRef = trustRef

		pendingTLSVerifyCompletion = response

		tlsVerify(trustRef) { [self] underlyingResponse in
			completePendingTLSVerify(with: underlyingResponse)
		}
	}

	private func completePendingTLSVerify(with trusted: Bool) {
		guard let completion = pendingTLSVerifyCompletion else {
			return
		}

		pendingTLSVerifyCompletion = nil
		completion(trusted)
	}

	var tlsNegotiatedProtocol: tls_protocol_version_t? {
		var protocolType: tls_protocol_version_t?

		accessTLSMetadata { metadata in
			protocolType = sec_protocol_metadata_get_negotiated_tls_protocol_version(metadata)
		}

		return protocolType
	}

	var tlsNegotiatedCipherSuite: tls_ciphersuite_t? {
		var cipherSuite: tls_ciphersuite_t?

		accessTLSMetadata { metadata in
			cipherSuite = sec_protocol_metadata_get_negotiated_tls_ciphersuite(metadata)
		}

		return cipherSuite
	}

	var tlsCertificateChainData: [Data]? {
		var certificateChain: [Data]?

		accessTLSTrustRef { trustRef in
			certificateChain = SecureTransportSupport.certificates(in: trustRef)
		}

		return certificateChain
	}

	var tlsPolicyName: String? {
		var policyName: String?

		accessTLSTrustRef { trustRef in
			policyName = SecureTransportSupport.policyName(in: trustRef)

			if policyName == nil {
				/*
				 June 09, 2019 with 10.15 Beta (19A471t):

				 Despite us having a trustRef, we do not have a policy name
				 when connecting with modern sockets to an IP address.
				 The IP address itself is what is being matched against the
				 certificate name anyways so let's just return it from config.

				 This can be revisited after the next stable release.
				 */

				let serverAddress = config.serverAddress

				if serverAddress.isIPAddress {
					policyName = serverAddress
				}
			} // policyName
		}

		return policyName
	}

	fileprivate func accessTLSMetadata(with closure: (sec_protocol_metadata_t) -> Void) {
		guard let genericMetadata = connection?.metadata(definition: NWProtocolTLS.definition) else {
			return
		}

		guard let tlsMetadata = genericMetadata as? NWProtocolTLS.Metadata else {
			return
		}

		closure(tlsMetadata.securityProtocolMetadata)
	}

	fileprivate func accessTLSTrustRef(with closure: (SecTrust) -> Void) {
		if let trustRef {
			closure(trustRef)
		}
	}

	var tlsLocalIdentity: sec_identity_t? {
		guard let clientCertificate = clientSideCertificate else {
			return nil
		}

		/* And I thought I wrote verbose names... */
		return sec_identity_create_with_certificates(
			clientCertificate.identity,
			[clientCertificate.certificate] as CFArray
		)
	}

	// MARK: - Error Handling

	fileprivate func translateError(_ error: NWError) -> ConnectionError {
		switch error {
		case let .dns(errorCode):
			return ConnectionError(nwDNSError: errorCode)
		case let .posix(errorCode):
			return ConnectionError(nwPOSIXError: errorCode.rawValue)
		case let .tls(errorCode):
			return ConnectionError(nwTLSError: errorCode)
		case .wifiAware:
			return ConnectionError(otherError: "Wi-Fi Aware error")
		@unknown default:
			return ConnectionError(otherError: error.localizedDescription)
		}
	}
}

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
		let errorCode = Int(nwTLSError)

		self.init(tlsError: errorCode)
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
