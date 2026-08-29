/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
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
import SecurityInterface

private nonisolated let connectionLogger = Logger(
	subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
	category: "IRCConnection"
)

/** Everything the connection host reports. NSXPC delivers these on its own
 queue; they are drained on the main actor in arrival order so that the client
 sees them in wire order. */
private enum ConnectionEvent: Sendable {
	case willConnectToProxy(host: String, port: UInt16)
	case didConnect(host: String?)
	case didSecure(protocolType: tls_protocol_version_t, cipherSuite: tls_ciphersuite_t)
	case didCloseReadStream
	case didDisconnect(error: Error?)
	case didReceive(Data)
	case requestInsecureCertificateTrust(TrustDecisionHandler)
	case willSend(Data)
	case didSendData
	case serviceInterrupted
	case serviceInvalidated
}

public protocol ConnectionDelegate: AnyObject {
	func ircConnection(_ sender: Connection, willConnectToProxy proxyHost: String, port proxyPort: UInt16)

	func ircConnectionDidConnect(_ sender: Connection)

	func ircConnectionDidSecureConnection(
		_ sender: Connection,
		withProtocolType protocolType: tls_protocol_version_t,
		cipherSuite: tls_ciphersuite_t
	)

	func ircConnectionDidCloseReadStream(_ sender: Connection)

	func ircConnection(_ sender: Connection, didDisconnectWithError disconnectError: Error?)

	func ircConnection(_ sender: Connection, didReceiveData data: String)

	func ircConnection(_ sender: Connection, willSendData data: String)
}

/** Owned by `IRCClient` on the main actor. The connection host's callbacks
 arrive on an NSXPC queue and are forwarded through `events`, which the main
 actor drains in order; nothing else on this type is touched off-main. */
@objc(IRCConnection)
public final class Connection: NSObject, RemoteConnectionClientProtocol {
	@objc public private(set) weak var client: IRCClient!
	public private(set) var config: IRCConnectionConfig
	@objc public private(set) var isConnected = false
	@objc public private(set) var isConnectedWithClientSideCertificate = false
	@objc public private(set) var isConnecting = false
	@objc public private(set) var isDisconnecting = false
	@objc public private(set) var isSecured = false
	@objc public private(set) var certificateTrustWasOverridden = false

	/// Whether TLS is established *and* the server's chain validated on its own.
	///
	/// Distinct from ``isSecured``, which is also true when the user clicked
	/// through the trust panel or the connection is configured to skip chain
	/// validation. Anything that outlives the connection — an STS policy, for
	/// instance — has to key on this instead.
	@objc public var isSecuredWithValidatedCertificate: Bool {
		isSecured
			&& certificateTrustWasOverridden == false
			&& config.connectionShouldValidateCertificateChain
	}

	@objc public private(set) var isSending = false
	@objc public private(set) var EOFReceived = false
	@objc public private(set) var connectedAddress: String?
	@objc public private(set) var uniqueIdentifier: String

	/// The host's callbacks, in arrival order, on their way to the main actor.
	private nonisolated let events: AsyncStream<ConnectionEvent>
	private nonisolated let eventContinuation: AsyncStream<ConnectionEvent>.Continuation
	private var eventTask: Task<Void, Never>?

	private var serviceConnection: NSXPCConnection?
	private var trustPanel: SFCertificateTrustPanel?
	/** `trustPanel` is only assigned once the asynchronous certificate export lands, so it
	 cannot gate re-entry on its own. This latch is set synchronously on the main queue. */
	private var trustPanelIsPresenting = false
	private var trustPanelDoNotInvokeCompletionBlock = false
	private var connectionInvalidatedVoluntarily = false

	@available(*, unavailable)
	override public init() {
		fatalError("init() is unavailable; use init(config:onClient:)")
	}

	public init(config: IRCConnectionConfig, onClient client: IRCClient) {
		self.client = client
		self.config = config
		uniqueIdentifier = UUID().uuidString
		(events, eventContinuation) = AsyncStream.makeStream()
		super.init()
		startDeliveringEvents()
	}

	isolated deinit {
		eventContinuation.finish()
		eventTask?.cancel()
	}

	/// Drains the host's callbacks on the main actor in the order they arrived.
	private func startDeliveringEvents() {
		eventTask = Task { [weak self, events] in
			for await event in events {
				guard let self else { return }
				handle(event)
			}
		}
	}

	private func handle(_ event: ConnectionEvent) {
		switch event {
		case let .willConnectToProxy(host, port):
			client?.ircConnection(self, willConnectToProxy: host, port: port)
		case let .didConnect(host):
			connectedAddress = host
			isConnecting = false
			isConnected = true
			client?.ircConnectionDidConnect(self)
		case let .didSecure(protocolType, cipherSuite):
			isSecured = true
			isConnectedWithClientSideCertificate = config.identityClientSideCertificate != nil
			client?.ircConnectionDidSecureConnection(
				self,
				withProtocolType: protocolType,
				cipherSuite: cipherSuite
			)
		case .didCloseReadStream:
			EOFReceived = true
			client?.ircConnectionDidCloseReadStream(self)
		case let .didDisconnect(error):
			connectionInvalidatedVoluntarily = true
			invalidateProcess()
			didDisconnect(with: error)
		case let .didReceive(data):
			guard let string = convertFromCommonEncoding(data) else { return }
			client?.ircConnection(self, didReceiveData: string)
		case let .requestInsecureCertificateTrust(response):
			openInsecureCertificateTrustPanel(response)
		case let .willSend(data):
			guard let string = convertFromCommonEncoding(data) else { return }
			client?.ircConnection(self, willSendData: string)
		case .didSendData:
			isSending = false
		case .serviceInterrupted:
			invalidateProcess()
		case .serviceInvalidated:
			handleServiceInvalidation()
		}
	}

	private func handleServiceInvalidation() {
		serviceConnection = nil

		if isConnecting || isConnected, connectionInvalidatedVoluntarily == false {
			let error = NSError(
				domain: connectionErrorDomain,
				code: Int(ConnectionErrorCode.other.rawValue),
				userInfo: [NSLocalizedDescriptionKey: IRCConnectionStrings.serviceClosedUnexpectedly]
			)
			didDisconnect(with: error)
		}

		resetState()
	}

	@objc public func resetState() {
		isConnecting = false
		isConnected = false
		isConnectedWithClientSideCertificate = false
		isDisconnecting = false
		EOFReceived = false
		isSecured = false
		certificateTrustWasOverridden = false
		isSending = false
		connectedAddress = nil
		connectionInvalidatedVoluntarily = false
	}

	private func invalidateProcess() {
		guard let serviceConnection else { return }
		connectionLogger.debug("Invalidating IRC connection service")
		serviceConnection.invalidate()
	}

	private func warmProcessIfNeeded() {
		guard serviceConnection == nil else { return }
		warmProcess()
	}

	private func warmProcess() {
		connectionLogger.debug("Warming IRC connection service")
		let connection = NSXPCConnection(serviceName: "com.vakesz.glasstual.IRCConnectionHost")
		connection.remoteObjectInterface = NSXPCInterface(with: RemoteConnectionServerProtocol.self)
		connection.exportedInterface = NSXPCInterface(with: RemoteConnectionClientProtocol.self)
		connection.exportedObject = self
		connection.interruptionHandler = { [weak self] in
			self?.eventContinuation.yield(.serviceInterrupted)
			connectionLogger.info("IRC connection service interrupted")
		}
		connection.invalidationHandler = { [weak self] in
			self?.eventContinuation.yield(.serviceInvalidated)
			connectionLogger.info("IRC connection service invalidated")
		}
		connection.resume()
		serviceConnection = connection
	}

	private func remoteObjectProxy(
		errorHandler: ((Error) -> Void)? = nil
	) -> RemoteConnectionServerProtocol? {
		serviceConnection?.remoteObjectProxyWithErrorHandler { error in
			connectionLogger.error("IRC connection service error: \(error.localizedDescription, privacy: .public)")
			errorHandler?(error)
		} as? RemoteConnectionServerProtocol
	}

	@objc public func open() {
		guard isConnecting == false, isConnected == false, isDisconnecting == false else { return }
		warmProcessIfNeeded()
		isConnecting = true
		remoteObjectProxy()?.open(with: ConnectionConfigEnvelope(config: config))

		if TextualPreferences.appNapEnabled() == false {
			remoteObjectProxy()?.disableAppNap()
		}

		remoteObjectProxy()?.disableSuddenTermination()
	}

	@objc public func close() {
		guard isDisconnecting == false else { return }

		if isConnecting || isConnected {
			isDisconnecting = true
			remoteObjectProxy()?.close()
		} else {
			invalidateProcess()
		}
	}

	@objc public func enforceFloodControl() {
		guard isConnected else { return }
		remoteObjectProxy()?.enforceFloodControl()
	}

	@objc public func openSecuredConnectionCertificateModal() {
		exportSecureConnectionInformation { information in
			/* The hop comes first, and the `SecTrust` is rebuilt on the other
			 side of it. What crosses is `SecureConnectionInformation`, which is
			 `Sendable` and already carries the DER chain. */
			Task { @MainActor in
				Self.presentCertificateModal(for: information)
			}
		}
	}

	@MainActor
	private static func presentCertificateModal(for information: SecureConnectionInformation) {
		let cipherSuite = information.cipherSuite

		guard
			let policyName = information.policyName,
			let trust = SecureTransportSupport.trust(
				fromCertificateChain: information.certificateChain,
				policyName: policyName
			),
			let protocolDescription = SecureTransportSupport
			.description(forProtocolType: information.protocolVersion),
			let cipherDescription = SecureTransportSupport.description(forCipherSuite: cipherSuite)
		else { return }

		let cipherStatus: PromptCipherStatus = SecureTransportSupport.isCipherSuiteDeprecated(cipherSuite)
			? .deprecated
			: .current
		let summary = PromptStrings.TransportSecurity.cipherSummary(
			policyName: protocolDescription,
			cipherSuite: cipherDescription,
			status: cipherStatus
		)
		var body = PromptStrings.TransportSecurity.certificateSummary(
			policyName: policyName,
			cipherSummary: summary
		)

		if let failure = information.trustFailureDescription {
			body += PromptStrings.TransportSecurity.trustFailure(failure)
		}

		_ = TrustPanelPresenter.present(
			in: NSApp.keyWindow,
			body: body,
			title: PromptStrings.TransportSecurity.encryptedConnectionTitle(policyName: policyName),
			defaultButton: PromptStrings.Action.close,
			alternateButton: nil,
			trust: trust
		) { _, _, _ in }
	}

	private func openInsecureCertificateTrustPanel(_ response: @escaping TrustDecisionHandler) {
		guard trustPanelIsPresenting == false else {
			/* The connection host blocks its handshake until this reply arrives. */
			response(false)
			return
		}
		trustPanelIsPresenting = true

		/* Reaching this panel means the chain did not validate. Whatever the
		 user answers, this connection is no longer one whose certificate the
		 system vouched for, and policies that outlive it must not be taken
		 from it. */
		certificateTrustWasOverridden = true

		exportSecureConnectionInformation { [weak self] information in
			Task { @MainActor [weak self] in
				guard let self else {
					response(false)
					return
				}

				presentInsecureCertificateTrustPanel(for: information, response: response)
			}
		}
	}

	/// Builds the `SecTrust` from the chain the service exported and puts it in
	/// front of the user.
	///
	/// The rebuild happens here rather than in the export callback so that no
	/// Security.framework object ever leaves the main actor.
	private func presentInsecureCertificateTrustPanel(
		for information: SecureConnectionInformation,
		response: @escaping TrustDecisionHandler
	) {
		guard
			let policyName = information.policyName,
			let trust = SecureTransportSupport.trust(
				fromCertificateChain: information.certificateChain,
				policyName: policyName
			)
		else {
			trustPanelIsPresenting = false
			response(false)
			return
		}

		trustPanel = TrustPanelPresenter.present(
			in: nil,
			body: PromptStrings.TransportSecurity.certificateFailureBody(serverName: policyName),
			title: PromptStrings.TransportSecurity.certificateFailureTitle(serverName: policyName),
			defaultButton: PromptStrings.TransportSecurity.invalidCertificateContinueButtonTitle,
			alternateButton: PromptStrings.Action.cancel,
			trust: trust,
			completion: { [weak self] _, trusted, _ in
				Task { @MainActor [weak self] in
					guard let self else {
						response(false)
						return
					}

					trustPanel = nil
					trustPanelIsPresenting = false

					if trustPanelDoNotInvokeCompletionBlock {
						trustPanelDoNotInvokeCompletionBlock = false
						return
					}

					response(trusted)
				}
			},
			context: nil
		)
	}

	private func closeInsecureCertificateTrustPanel() {
		guard let trustPanel else { return }
		trustPanelDoNotInvokeCompletionBlock = true

		if let parent = trustPanel.sheetParent {
			parent.endSheet(trustPanel, returnCode: .cancel)
			return
		}

		if NSApp.modalWindow === trustPanel {
			NSApp.stopModal(withCode: .cancel)
			return
		}

		trustPanel.orderOut(nil)
		trustPanelDoNotInvokeCompletionBlock = false
		trustPanelIsPresenting = false
		self.trustPanel = nil
	}

	private func exportSecureConnectionInformation(_ receiver: @escaping SecureConnectionInformationReceiver) {
		remoteObjectProxy()?.exportSecureConnectionInformation(receiver)
	}

	private func convertFromCommonEncoding(_ data: Data) -> String? {
		client.convert(fromCommonEncoding: data)
	}

	private func convertToCommonEncoding(_ string: String) -> Data? {
		client.convert(toCommonEncoding: string)
	}

	@objc(sendLine:)
	public func sendLine(_ line: String) {
		let cleanLine = line
			.replacingOccurrences(of: "\r", with: "")
			.replacingOccurrences(of: "\n", with: "") + "\r\n"

		guard let data = convertToCommonEncoding(cleanLine) else { return }
		isSending = true

		if cleanLine.hasPrefix("PONG") {
			remoteObjectProxy()?.send(data, bypassQueue: true)
		} else {
			remoteObjectProxy()?.send(data)
		}
	}

	@objc public func clearSendQueue() {
		remoteObjectProxy()?.clearSendQueue()
	}

	/* Every callback below arrives on the NSXPC queue. They only hand the value
	 to `events`; the main actor does the work, in the order the host sent it. */

	public nonisolated func ircConnectionWillConnect(toProxy proxyHost: String, port proxyPort: UInt16) {
		eventContinuation.yield(.willConnectToProxy(host: proxyHost, port: proxyPort))
	}

	public nonisolated func ircConnectionDidConnect(toHost host: String?) {
		eventContinuation.yield(.didConnect(host: host))
	}

	public nonisolated func ircConnectionDidSecureConnection(
		withProtocolType protocolType: tls_protocol_version_t,
		cipherSuite: tls_ciphersuite_t
	) {
		eventContinuation.yield(.didSecure(protocolType: protocolType, cipherSuite: cipherSuite))
	}

	public nonisolated func ircConnectionDidCloseReadStream() {
		eventContinuation.yield(.didCloseReadStream)
	}

	public nonisolated func ircConnectionDidDisconnectWithError(_ disconnectError: Error?) {
		eventContinuation.yield(.didDisconnect(error: disconnectError))
	}

	private func didDisconnect(with error: Error?) {
		closeInsecureCertificateTrustPanel()
		client?.ircConnection(self, didDisconnectWithError: error)
	}

	public nonisolated func ircConnectionDidReceive(_ data: Data) {
		eventContinuation.yield(.didReceive(data))
	}

	public nonisolated func ircConnectionRequestInsecureCertificateTrust(
		_ trustBlock: @escaping TrustDecisionHandler
	) {
		eventContinuation.yield(.requestInsecureCertificateTrust(trustBlock))
	}

	public nonisolated func ircConnectionWillSend(_ data: Data) {
		eventContinuation.yield(.willSend(data))
	}

	public nonisolated func ircConnectionDidSendData() {
		eventContinuation.yield(.didSendData)
	}
}
