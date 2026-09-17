// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
import os
import Security

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
	/// One read's lines, and the reply that lets the host read the next.
	case didReceive([Data], acknowledge: @Sendable () -> Void)
	case requestInsecureCertificateTrust(TrustDecisionHandler)
	case willSend(Data)
	case didSendData
	case serviceFailed(Error)
	case serviceInterrupted
	case serviceInvalidated
}

/** The object NSXPC exports for the host's callbacks.

 `RemoteConnectionClientProtocol` refines `Sendable` so the connection host can
 push through the proxy from inside its actor. That makes every conformer
 `Sendable`, which `Connection` — main-actor state, and plenty of it — cannot
 be, so the conformance lives on this instead. It holds nothing but the event
 continuation and hands every callback straight to it. */
private final class ConnectionClientShim: NSObject, RemoteConnectionClientProtocol {
	private let events: AsyncStream<ConnectionEvent>.Continuation

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

	func ircConnectionDidReceive(_ lines: [Data], acknowledge: @escaping @Sendable () -> Void) {
		events.yield(.didReceive(lines, acknowledge: acknowledge))
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

/** Owned by `Client` on the main actor. The connection host's callbacks
 arrive on an NSXPC queue and are forwarded through `events`, which the main
 actor drains in order; nothing else on this type is touched off-main. */
final class Connection {
	private(set) weak var client: Client?
	private(set) var config: ConnectionConfig
	private(set) var isConnected = false
	private(set) var isConnectedWithClientSideCertificate = false
	private(set) var isConnecting = false
	private(set) var isDisconnecting = false
	private(set) var isSecured = false
	private(set) var certificateTrustWasOverridden = false

	/// Whether TLS is established *and* the server's chain validated on its own.
	///
	/// Distinct from ``isSecured``, which is also true when the user clicked
	/// through the trust panel or the connection is configured to skip chain
	/// validation. Anything that outlives the connection — an STS policy, for
	/// instance — has to key on this instead.
	var isSecuredWithValidatedCertificate: Bool {
		isSecured
			&& certificateTrustWasOverridden == false
			&& config.connectionShouldValidateCertificateChain
	}

	private(set) var EOFReceived = false
	private(set) var connectedAddress: String?
	private(set) var uniqueIdentifier: String

	/** The longest line this server carries, CR LF included.

	 `LINELEN` as 005 advertised it, and the RFC's 512 until one does — which is
	 also what a reconnect goes back to, because the next server has not said
	 anything yet. Everything upstream already sizes its text from the same
	 figure; this is where the assembled line is measured against it. */
	var maximumLineLength = ProtocolLimits.maximumBodyLength + ProtocolLimits.lineTerminatorLength

	/// The host's callbacks, in arrival order, on their way to the main actor.
	private nonisolated let events: AsyncStream<ConnectionEvent>
	private nonisolated let eventContinuation: AsyncStream<ConnectionEvent>.Continuation
	private nonisolated let clientShim: ConnectionClientShim
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

	/// What answers a pending trust request once the user has decided.
	private var trustResponse: TrustDecisionHandler?

	/// Where the user is asked about a certificate. Reached through the
	/// environment so that nothing here presents AppKit itself.
	private var trustPanel: CertificateTrustPanel? {
		client?.environment.services.certificateTrust
	}

	convenience init(config: ConnectionConfig, onClient client: Client) {
		self.init(config: config, onClient: client, closeClock: .continuous)
	}

	init(
		config: ConnectionConfig,
		onClient client: Client,
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
			for await event in events {
				guard let self else { return }
				if case let .didReceive(lines, acknowledge) = event {
					await receive(lines)
					/* Answered once the lines are handled, whatever became of
					 the connection meanwhile: the host is waiting on this reply
					 before it reads again. */
					acknowledge()
				} else {
					handle(event)
				}
			}
		}
	}

	/** Hands one read's lines to the client, in order.

	 The main actor is given back between every few lines so that a long burst —
	 a `/LIST`, a bouncer's playback — does not hold up drawing. Nothing arrives
	 behind the burst meanwhile: the host reads the next one only after the
	 acknowledgement. */
	private func receive(_ lines: [Data]) async {
		for (index, line) in lines.enumerated() {
			guard let client else { return }
			await client.renderAdmission.waitForCapacity()
			guard !Task.isCancelled, terminal == false, client.socket === self else { return }
			if let string = convertFromCommonEncoding(line) {
				client.connectionDidReceive(string)
			}
			if (index + 1).isMultiple(of: Self.linesPerTurn) {
				await Task.yield()
			}
		}
		await client?.renderAdmission.waitForCapacity()
	}

	/// How many lines are handled before the main actor is offered to other work.
	private static let linesPerTurn = 64

	private func handle(_ event: ConnectionEvent) {
		guard terminal == false, client?.socket === self else {
			if case let .requestInsecureCertificateTrust(response) = event {
				response(false)
			}
			return
		}
		switch event {
		case let .willConnectToProxy(host, port):
			client?.connectionWillConnect(toProxy: host, port: port)
		case let .didConnect(host):
			guard isDisconnecting == false else { return }
			connectedAddress = host
			isConnecting = false
			isConnected = true
			client?.connectionDidConnect()
		case let .didSecure(protocolType, cipherSuite):
			guard isDisconnecting == false else { return }
			isSecured = true
			isConnectedWithClientSideCertificate = config.identityClientSideCertificate != nil
			client?.connectionDidSecure(protocolType: protocolType, cipherSuite: cipherSuite)
		case .didCloseReadStream:
			EOFReceived = true
			client?.connectionDidCloseReadStream()
		case let .didDisconnect(error):
			didDisconnect(with: error)
		case .didReceive:
			/* Delivered by `receive(_:)`, which the event loop awaits so that
			 the acknowledgement follows the last line. */
			break
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
		}
	}

	private func willWrite(_ data: Data) {
		guard let string = convertFromCommonEncoding(data) else { return }
		pendingStartupEvent = if StartupCommandPolicy.identifiesNickServOnWire(string) {
			.identificationWritten
		} else if !recordedFirstJoin, Message(line: string, on: nil)?.command == "JOIN" {
			.firstJoin
		} else {
			nil
		}
		client?.connectionWillSend(string)
	}

	private func didWrite() {
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
				userInfo: [NSLocalizedDescriptionKey: String(localized: .IRC.connectionServiceClosedUnexpectedly)]
			)
			didDisconnect(with: error)
		}
	}

	func resetState() {
		/* The next server advertises its own `LINELEN`, or none at all. */
		maximumLineLength = ProtocolLimits.maximumBodyLength + ProtocolLimits.lineTerminatorLength
		isConnecting = false
		isConnected = false
		isConnectedWithClientSideCertificate = false
		isDisconnecting = false
		EOFReceived = false
		isSecured = false
		certificateTrustWasOverridden = false
		connectedAddress = nil
	}

	private func invalidateProcess() {
		guard let serviceConnection else { return }
		connectionLogger.debug("Invalidating IRC connection service")
		serviceConnection.invalidate()
		self.serviceConnection = nil
	}

	/// Starts the connection service, unless one is already running.
	private func warmProcessIfNeeded() {
		guard serviceConnection == nil else { return }

		connectionLogger.debug("Warming IRC connection service")
		let connection = makeService()
		connection.remoteObjectInterface = RemoteConnectionInterface.server()
		connection.exportedInterface = RemoteConnectionInterface.client()
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

	func open() {
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

		if Preferences.Internals.appSleepDisabled.value {
			remoteObjectProxy()?.disableAppNap()
		}

		remoteObjectProxy()?.disableSuddenTermination()
	}

	func close() {
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

	func enforceFloodControl() {
		guard isConnected else { return }
		remoteObjectProxy()?.enforceFloodControl()
	}

	func openSecuredConnectionCertificateModal() {
		exportSecureConnectionInformation { information in
			/* The hop comes first, and the `SecTrust` is rebuilt on the other
			 side of it. What crosses is `SecureConnectionInformation`, which is
			 `Sendable` and already carries the DER chain. */
			Task { @MainActor in
				CertificateTrustPanel.presentSummary(for: information)
			}
		}
	}

	/** Puts a certificate the system would not vouch for in front of the user.

	 The connection host blocks its handshake on the answer, so every path out
	 of here answers exactly once. */
	private func openInsecureCertificateTrustPanel(_ response: @escaping TrustDecisionHandler) {
		guard terminal == false, isDisconnecting == false, client?.isTerminating == false,
		      let trustPanel, trustPanel.reserve()
		else {
			response(false)
			return
		}

		trustResponse = response

		/* Reaching this panel means the chain did not validate. Whatever the
		 user answers, this connection is no longer one whose certificate the
		 system vouched for, and policies that outlive it must not be taken
		 from it. */
		certificateTrustWasOverridden = true

		exportSecureConnectionInformation { [weak self] information in
			Task { @MainActor [weak self] in
				/* Only a deallocated connection cannot answer, and that has
				 already invalidated the service the handshake belongs to. */
				guard let self else { return }

				guard terminal == false, isDisconnecting == false, client?.socket === self else {
					trustPanel.cancelReservation()
					resolveTrust(false)
					return
				}

				guard trustResponse != nil else {
					trustPanel.cancelReservation()
					return
				}

				let presented = trustPanel.present(for: information) { [weak self] trusted in
					guard let self else { return }

					resolveTrust(trusted && terminal == false && isDisconnecting == false)
				}

				if presented == false {
					resolveTrust(false)
				}
			}
		}
	}

	/// Answers whatever was waiting on the panel with a refusal and takes it
	/// down: the connection is going away, and the host is still blocked.
	private func closeInsecureCertificateTrustPanel() {
		resolveTrust(false)
		trustPanel?.close()
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

	func sendLine(_ line: String) {
		let body = line
			.replacingOccurrences(of: "\r", with: "")
			.replacingOccurrences(of: "\n", with: "")
		/* Last stop before the socket: everything upstream budgets its own text,
		 but nothing measured the assembled line, so a long enough command went
		 out over what the protocol carries and the server cut it where it
		 landed — mid-character for anything but ASCII. */
		let bodyLimit = ProtocolLimits.bodyLimit(forAdvertisedLineLength: maximumLineLength)
		let enforcedBody = ProtocolLimits.enforcedWireLine(body, bodyLimit: bodyLimit)

		if enforcedBody != body {
			connectionLogger.error(
				"Truncated an outgoing line from \(body.utf8.count, privacy: .public) to \(enforcedBody.utf8.count, privacy: .public) bytes"
			)
			/* The log is not where the user is looking. Text they typed is gone
			 from what the server saw, so the transcript has to say so. */
			client?.printDebugInformation(
				toConsole: ConnectionSafetyStrings.Wire.lineTruncated(
					sentByteCount: body.utf8.count,
					limit: enforcedBody.utf8.count
				)
			)
		}

		let cleanLine = enforcedBody + "\r\n"

		guard let data = convertToCommonEncoding(cleanLine) else { return }

		if Self.bypassesFloodControl(cleanLine) {
			remoteObjectProxy()?.send(data, bypassQueue: true)
		} else {
			remoteObjectProxy()?.send(data)
		}
	}

	/** Whether `line` goes out ahead of the flood-control queue.

	 A PONG answers the server's liveness probe, which a backed-up queue would
	 otherwise make it miss. A QUIT is the last line a closing connection sends:
	 the disconnect that follows it clears the queue, so a QUIT waiting behind
	 flood control was thrown away and the user's quit message never reached
	 anyone. */
	static func bypassesFloodControl(_ line: String) -> Bool {
		line.hasPrefix("PONG") || line.hasPrefix("QUIT")
	}

	func clearSendQueue() {
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
			client?.connectionDidDisconnect(error: error)
		}
		eventContinuation.finish()
		eventTask?.cancel()
	}
}
