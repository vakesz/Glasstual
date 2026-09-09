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

private nonisolated let connectionLogger = Logger( // nonisolated: let
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
	case serviceFailed(Error)
	case serviceInterrupted
	case serviceInvalidated
	case inputOverload
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

/*  Owned by `IRCClient` on the main actor. The connection host's callbacks
 arrive on an NSXPC queue and are forwarded through `events`, which the main
 actor drains in order; nothing else on this type is touched off-main. */
/** The object NSXPC exports for the host's callbacks.

 `RemoteConnectionClientProtocol` refines `Sendable` so the connection host can
 push through the proxy from inside its actor. That makes every conformer
 `Sendable`, which `Connection` — main-actor state, and plenty of it — cannot
 be, so the conformance lives on this instead. It holds nothing but the event
 continuation and hands every callback straight to it. */
private final class ConnectionClientShim: NSObject, RemoteConnectionClientProtocol {
	private let events: AsyncStream<ConnectionEvent>.Continuation
	let inputBudget = ConnectionInputBudget()

	init(events: AsyncStream<ConnectionEvent>.Continuation) {
		self.events = events

		super.init()
	}

	/* Every callback below arrives on the NSXPC queue. They only hand the value
	 to `events`; the main actor does the work, in the order the host sent it. */

	func ircConnectionWillConnect(toProxy proxyHost: String, port proxyPort: UInt16) {
		events.yield(.willConnectToProxy(host: proxyHost, port: proxyPort))
	}

	func ircConnectionDidConnect(toHost host: String?) {
		events.yield(.didConnect(host: host))
	}

	func ircConnectionDidSecureConnection(
		withProtocolType protocolType: tls_protocol_version_t,
		cipherSuite: tls_ciphersuite_t
	) {
		events.yield(.didSecure(protocolType: protocolType, cipherSuite: cipherSuite))
	}

	func ircConnectionDidCloseReadStream() {
		events.yield(.didCloseReadStream)
	}

	func ircConnectionDidDisconnectWithError(_ disconnectError: Error?) {
		events.yield(.didDisconnect(error: disconnectError))
	}

	func ircConnectionDidReceive(_ data: Data) {
		switch inputBudget.admit(bytes: data.count) {
		case .accepted: events.yield(.didReceive(data))
		case .overflow: events.yield(.inputOverload)
		case .closed: break
		}
	}

	func ircConnectionRequestInsecureCertificateTrust(_ trustBlock: @escaping TrustDecisionHandler) {
		events.yield(.requestInsecureCertificateTrust(trustBlock))
	}

	func ircConnectionWillSend(_ data: Data) {
		events.yield(.willSend(data))
	}

	func ircConnectionDidSendData() {
		events.yield(.didSendData)
	}
}

public final class Connection: NSObject {
	public private(set) weak var client: IRCClient?
	public private(set) var config: IRCConnectionConfig
	public private(set) var isConnected = false
	public private(set) var isConnectedWithClientSideCertificate = false
	public private(set) var isConnecting = false
	public private(set) var isDisconnecting = false
	public private(set) var isSecured = false
	public private(set) var certificateTrustWasOverridden = false

	/// Whether TLS is established *and* the server's chain validated on its own.
	///
	/// Distinct from ``isSecured``, which is also true when the user clicked
	/// through the trust panel or the connection is configured to skip chain
	/// validation. Anything that outlives the connection — an STS policy, for
	/// instance — has to key on this instead.
	public var isSecuredWithValidatedCertificate: Bool {
		isSecured
			&& certificateTrustWasOverridden == false
			&& config.connectionShouldValidateCertificateChain
	}

	/// Whether a line has been handed to the host and its write has not yet
	/// been reported back. It is this side's view of the last send, not the
	/// host writer's admission or flood-control state.
	private(set) var isSending = false
	public private(set) var EOFReceived = false
	public private(set) var connectedAddress: String?
	public private(set) var uniqueIdentifier: String

	/// The host's callbacks, in arrival order, on their way to the main actor.
	private nonisolated let events: AsyncStream<ConnectionEvent> // nonisolated: let
	private nonisolated let eventContinuation: AsyncStream<ConnectionEvent>.Continuation // nonisolated: let
	private nonisolated let clientShim: ConnectionClientShim // nonisolated: let
	private var eventTask: Task<Void, Never>?
	private let closeClock: TimerClock
	private let makeService: () -> NSXPCConnection
	private var closeDeadlineTask: Task<Void, Never>?
	private var terminal = false
	private var pendingStartupEvent: ConnectionDiagnostics.Event?
	private var recordedFirstJoin = false

	private var serviceConnection: NSXPCConnection?
	/// The same receiver exported to XPC, also usable by in-process transports.
	var callbackReceiver: any RemoteConnectionClientProtocol {
		clientShim
	}

	private var trustPanel: SFCertificateTrustPanel?
	/** `trustPanel` is only assigned once the asynchronous certificate export lands, so it
	 cannot gate re-entry on its own. This latch is set synchronously on the main queue. */
	private var trustPanelIsPresenting = false
	private var trustResponse: TrustDecisionHandler?

	@available(*, unavailable)
	override public init() {
		fatalError("init() is unavailable; use init(config:onClient:)")
	}

	public convenience init(config: IRCConnectionConfig, onClient client: IRCClient) {
		self.init(config: config, onClient: client, closeClock: .continuous)
	}

	init(
		config: IRCConnectionConfig,
		onClient client: IRCClient,
		closeClock: TimerClock,
		makeService: @escaping () -> NSXPCConnection = {
			NSXPCConnection(serviceName: "com.vakesz.glasstual.IRCConnectionHost")
		}
	) {
		self.closeClock = closeClock
		self.makeService = makeService
		self.client = client
		self.config = config
		uniqueIdentifier = UUID().uuidString
		(events, eventContinuation) = AsyncStream.makeStream()
		clientShim = ConnectionClientShim(events: eventContinuation)
		super.init()
		startDeliveringEvents()
	}

	isolated deinit {
		closeDeadlineTask?.cancel()
		serviceConnection?.invalidate()
		eventContinuation.finish()
		eventTask?.cancel()
	}

	/// Drains the host's callbacks on the main actor in the order they arrived.
	private func startDeliveringEvents() {
		eventTask = Task { [weak self, events] in
			var handled = 0
			for await event in events {
				guard let self else { return }
				if case let .didReceive(data) = event {
					clientShim.inputBudget.consumed(bytes: data.count)
				}
				handle(event)
				handled += 1
				if handled.isMultiple(of: 64) {
					await Task.yield()
				}
			}
		}
	}

	private func handle(_ event: ConnectionEvent) {
		guard terminal == false, client?.socket === self else {
			if case let .requestInsecureCertificateTrust(response) = event {
				response(false)
			}
			return
		}
		switch event {
		case let .willConnectToProxy(host, port):
			client?.ircConnection(self, willConnectToProxy: host, port: port)
		case let .didConnect(host):
			guard isDisconnecting == false else { return }
			connectedAddress = host
			isConnecting = false
			isConnected = true
			client?.ircConnectionDidConnect(self)
		case let .didSecure(protocolType, cipherSuite):
			guard isDisconnecting == false else { return }
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
			didDisconnect(with: error)
		case let .didReceive(data):
			guard let string = convertFromCommonEncoding(data) else { return }
			client?.ircConnection(self, didReceiveData: string)
		case let .requestInsecureCertificateTrust(response):
			openInsecureCertificateTrustPanel(response)
		case let .willSend(data):
			willWrite(data)
		case .didSendData:
			didWrite()
		case let .serviceFailed(error):
			didDisconnect(with: error)
		case .serviceInterrupted:
			handleServiceInvalidation()
		case .serviceInvalidated:
			handleServiceInvalidation()
		case .inputOverload:
			connectionLogger
				.error(
					"IRC input exceeded the bounded application queue; disconnecting without claiming complete delivery"
				)
			invalidateProcess()
			didDisconnect(with: NSError(domain: NSPOSIXErrorDomain, code: Int(ENOBUFS)))
		}
	}

	private func willWrite(_ data: Data) {
		guard let string = convertFromCommonEncoding(data) else { return }
		pendingStartupEvent = if IRCStartupCommandPolicy.identifiesNickServOnWire(string) {
			.identificationWritten
		} else if !recordedFirstJoin, Message(line: string, on: nil)?.command == "JOIN" {
			.firstJoin
		} else {
			nil
		}
		client?.ircConnection(self, willSendData: string)
	}

	private func didWrite() {
		isSending = false
		if let event = pendingStartupEvent {
			config.diagnostics?.record(event)
			if event == .identificationWritten {
				client?.noteNickServIdentificationWritten()
			}
			if event == .firstJoin {
				recordedFirstJoin = true
			}
		}
		pendingStartupEvent = nil
	}

	private func handleServiceInvalidation() {
		if isDisconnecting {
			didDisconnect(with: nil)
		} else {
			let error = NSError(
				domain: connectionErrorDomain,
				code: Int(ConnectionErrorCode.other.rawValue),
				userInfo: [NSLocalizedDescriptionKey: IRCConnectionStrings.serviceClosedUnexpectedly]
			)
			didDisconnect(with: error)
		}
	}

	func resetState() {
		isConnecting = false
		isConnected = false
		isConnectedWithClientSideCertificate = false
		isDisconnecting = false
		EOFReceived = false
		isSecured = false
		certificateTrustWasOverridden = false
		isSending = false
		connectedAddress = nil
	}

	private func invalidateProcess() {
		guard let serviceConnection else { return }
		connectionLogger.debug("Invalidating IRC connection service")
		serviceConnection.invalidate()
		self.serviceConnection = nil
	}

	private func warmProcessIfNeeded() {
		guard serviceConnection == nil else { return }
		warmProcess()
	}

	private func warmProcess() {
		connectionLogger.debug("Warming IRC connection service")
		let connection = makeService()
		connection.remoteObjectInterface = NSXPCInterface(with: RemoteConnectionServerProtocol.self)
		connection.exportedInterface = NSXPCInterface(with: RemoteConnectionClientProtocol.self)
		connection.exportedObject = callbackReceiver
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

	public func open() {
		guard terminal == false, client?.isTerminating == false,
		      isConnecting == false, isConnected == false, isDisconnecting == false else { return }
		config.diagnostics?.record(.serviceRequested)
		warmProcessIfNeeded()
		isConnecting = true
		let events = eventContinuation
		guard let proxy = remoteObjectProxy(errorHandler: { events.yield(.serviceFailed($0)) }) else {
			handleServiceInvalidation()
			return
		}
		proxy.open(with: ConnectionConfigEnvelope(config: config))

		if TextualPreferences.appNapEnabled() == false {
			remoteObjectProxy()?.disableAppNap()
		}

		remoteObjectProxy()?.disableSuddenTermination()
	}

	public func close() {
		guard terminal == false, isDisconnecting == false else { return }
		beginCloseDeadline()
		closeInsecureCertificateTrustPanel()

		if isConnecting || isConnected {
			isDisconnecting = true
			remoteObjectProxy()?.close()
		} else {
			didDisconnect(with: nil)
		}
	}

	/// QUIT starts this before its two-second grace period, keeping the total at five seconds.
	func beginCloseDeadline() {
		guard terminal == false, closeDeadlineTask == nil else { return }
		closeDeadlineTask = Task { [weak self, closeClock] in
			await closeClock.wait(5)
			guard Task.isCancelled == false, let self else { return }
			connectionLogger.error("IRC connection did not close within five seconds; invalidating service")
			didDisconnect(with: nil)
		}
	}

	public func enforceFloodControl() {
		guard isConnected else { return }
		remoteObjectProxy()?.enforceFloodControl()
	}

	public func openSecuredConnectionCertificateModal() {
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
		guard terminal == false, isDisconnecting == false, client?.isTerminating == false,
		      trustPanelIsPresenting == false
		else {
			/* The connection host blocks its handshake until this reply arrives. */
			response(false)
			return
		}
		trustPanelIsPresenting = true
		trustResponse = response

		/* Reaching this panel means the chain did not validate. Whatever the
		 user answers, this connection is no longer one whose certificate the
		 system vouched for, and policies that outlive it must not be taken
		 from it. */
		certificateTrustWasOverridden = true

		exportSecureConnectionInformation { [weak self] information in
			Task { @MainActor [weak self] in
				/* The host blocks its handshake on this reply, so every path out
				 of here answers. Only a deallocated connection cannot, and that
				 has already invalidated the service the handshake belongs to. */
				guard let self else { return }

				guard terminal == false, isDisconnecting == false, client?.socket === self else {
					trustPanelIsPresenting = false
					resolveTrust(false)
					return
				}

				guard trustResponse != nil else {
					trustPanelIsPresenting = false
					return
				}

				presentInsecureCertificateTrustPanel(for: information)
			}
		}
	}

	/// Builds the `SecTrust` from the chain the service exported and puts it in
	/// front of the user.
	///
	/// The rebuild happens here rather than in the export callback so that no
	/// Security.framework object ever leaves the main actor.
	private func presentInsecureCertificateTrustPanel(
		for information: SecureConnectionInformation
	) {
		guard
			let policyName = information.policyName,
			let trust = SecureTransportSupport.trust(
				fromCertificateChain: information.certificateChain,
				policyName: policyName
			)
		else {
			trustPanelIsPresenting = false
			resolveTrust(false)
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
					guard let self else { return }

					trustPanel = nil
					trustPanelIsPresenting = false

					resolveTrust(trusted && terminal == false && isDisconnecting == false)
				}
			},
			context: nil
		)
	}

	private func closeInsecureCertificateTrustPanel() {
		resolveTrust(false)
		trustPanelIsPresenting = false
		guard let trustPanel else { return }
		self.trustPanel = nil

		if let parent = trustPanel.sheetParent {
			parent.endSheet(trustPanel, returnCode: .cancel)
			return
		}

		if NSApp.modalWindow === trustPanel {
			NSApp.stopModal(withCode: .cancel)
			return
		}

		trustPanel.orderOut(nil)
	}

	private func resolveTrust(_ trusted: Bool) {
		let response = trustResponse
		trustResponse = nil
		response?(trusted)
	}

	private func exportSecureConnectionInformation(_ receiver: @escaping SecureConnectionInformationReceiver) {
		remoteObjectProxy()?.exportSecureConnectionInformation(receiver)
	}

	private func convertFromCommonEncoding(_ data: Data) -> String? {
		guard let client else { return nil }

		return client.convert(fromCommonEncoding: data)
	}

	private func convertToCommonEncoding(_ string: String) -> Data? {
		guard let client else { return nil }

		return client.convert(toCommonEncoding: string)
	}

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

	public func clearSendQueue() {
		remoteObjectProxy()?.clearSendQueue()
	}

	private func didDisconnect(with error: Error?) {
		guard terminal == false else { return }
		terminal = true
		config.diagnostics?.record(.disconnected)
		closeDeadlineTask?.cancel()
		closeDeadlineTask = nil
		invalidateProcess()
		closeInsecureCertificateTrustPanel()
		resetState()
		if client?.socket === self {
			client?.ircConnection(self, didDisconnectWithError: error)
		}
		eventContinuation.finish()
		eventTask?.cancel()
	}
}
