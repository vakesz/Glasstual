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
 *********************************************************************** */

import CocoaExtensions
import Foundation
import os

private let connectTimeout: Duration = .seconds(30)
/** A listener whose peer never dials in would otherwise hold a mapped router port for
 the lifetime of the application. */
private let listenTimeout: Duration = .seconds(300)
private let writeTimeout: Duration = .seconds(30)
private let maximumLineLength = 1024 * 16

private let directChatLogger = Logger(
	subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
	category: "DirectChat"
)

enum DirectChatSessionState: UInt {
	case idle = 0
	case listening
	case connecting
	case connected
	case closed
}

/** A DCC CHAT session. One instance is one TCP connection to one peer.

 The socket itself belongs to a ``DirectChatSocket`` actor, which does the
 framing and hands whole lines back through its event stream. Everything here —
 the state machine, the port mapping and the encoding — belongs to
 the main actor, and the event loop below is the one seam between the two. */
final class DirectChatSession {
	private(set) weak var client: Client?
	private(set) var peerNickname: String
	/** Only the connecting variant has an address; the listening variant learns its
	 port from the socket. Modelling it this way removes the unreachable dead-end
	 `openConnection()` used to hit when the address was nil. */
	private enum Role {
		/// `expectedPeerAddress` is the only address the listener takes a
		/// connection from; empty takes the first to arrive.
		case listening(expectedPeerAddress: String)
		case connecting(address: String)
	}

	var hostAddress: String? {
		guard case let .connecting(address) = role else { return nil }
		return address
	}

	private(set) var hostPort: UInt16 = 0
	private(set) var transferToken: String?
	private(set) var state: DirectChatSessionState = .idle

	private let role: Role
	private var chat: DirectChatSocket?
	private var eventTask: Task<Void, Never>?
	private var listenTimeoutTask: Task<Void, Never>?
	/** Sends are chained rather than each getting its own task: two `Task`s
	 started in the same turn reach the actor in whatever order the scheduler
	 picks, and a chat that reorders the user's lines is a bug. */
	private var outboundTask: Task<Void, Never>?
	private var portMapping: PortMapper?
	private let portMappingNotifications = NotificationSubscriptions()

	var isConnected: Bool {
		state == .connected
	}

	/// The owning client's preference snapshot, or the declared defaults once
	/// that client has gone.
	private var preferences: ClientPreferences {
		client?.environment.preferences ?? ClientPreferences()
	}

	private init(peer nickname: String, role: Role, onClient client: Client) {
		peerNickname = nickname
		self.role = role
		self.client = client
	}

	isolated deinit {
		tearDown()
	}

	static func connection(
		toPeer nickname: String,
		address hostAddress: String,
		port hostPort: UInt16,
		onClient client: Client
	) -> DirectChatSession {
		precondition(hostPort != 0)

		let object = DirectChatSession(
			peer: nickname,
			role: .connecting(address: hostAddress),
			onClient: client
		)
		object.hostPort = hostPort
		return object
	}

	/** A chat this side listens for.

	 `offeredAddress` is the address a passive offer named for the peer. It is
	 the one address the listener accepts, as a reverse DCC SEND's is, when it is
	 one the peer could actually connect from. A chat this user started has no
	 such address: the peer's hostmask says where they reached the server from —
	 a bouncer, a VPN, the other address family — not where they will dial out
	 from, so pinning to it would refuse the very peer the offer was sent to. */
	static func listeningConnection(
		forPeer nickname: String,
		token transferToken: String?,
		offeredAddress: String? = nil,
		onClient client: Client
	) -> DirectChatSession {
		let expectedPeerAddress = offeredAddress.flatMap { DCCWireFormat.isDialableAddress($0) ? $0 : nil } ?? ""
		let object = DirectChatSession(
			peer: nickname,
			role: .listening(expectedPeerAddress: expectedPeerAddress),
			onClient: client
		)

		if let transferToken, transferToken.isEmpty == false {
			object.transferToken = transferToken
		}

		return object
	}

	func open() {
		guard state == .idle else {
			return
		}

		switch role {
		case let .listening(expectedPeerAddress):
			openListener(expectingPeerAt: expectedPeerAddress)
		case let .connecting(address):
			openConnection(to: address)
		}
	}

	private func openConnection(to hostAddress: String) {
		state = .connecting

		start(endpoint: .connect(
			host: hostAddress,
			port: hostPort,
			interfaceName: preferences.fileTransferIPAddressInterfaceName,
			timeout: connectTimeout
		))
	}

	private func openListener(expectingPeerAt expectedPeerAddress: String) {
		let portRangeStart = preferences.fileTransferPortRangeStart
		let portRangeEnd = preferences.fileTransferPortRangeEnd

		guard portRangeStart > 0, portRangeStart <= portRangeEnd else {
			close(with: DCCTransferError.noOpenPort)
			return
		}

		state = .listening

		start(
			endpoint: .listen(portRange: portRangeStart ... portRangeEnd),
			expectedPeerAddress: expectedPeerAddress
		)
		startListenTimeout()
	}

	private func start(endpoint: DirectChatSocket.Endpoint, expectedPeerAddress: String = "") {
		let chat = DirectChatSocket(configuration: DirectChatSocket.Configuration(
			endpoint: endpoint,
			maximumLineLength: maximumLineLength,
			sendTimeout: writeTimeout,
			expectedPeerAddress: expectedPeerAddress
		))
		self.chat = chat

		eventTask = Task { @MainActor [weak self] in
			for await event in chat.events {
				guard let self else { return }

				if case let .lines(lines, acknowledged) = event {
					for (index, line) in lines.enumerated() {
						await client?.renderAdmission.waitForCapacity()
						guard isConnected, !Task.isCancelled else { break }
						consumeReceivedLine(line)
						if (index + 1).isMultiple(of: 64) {
							await Task.yield()
						}
					}
					await client?.renderAdmission.waitForCapacity()
					acknowledged.finish()
				} else {
					handle(event)
				}
			}
		}

		Task { await chat.start() }
	}

	private func startListenTimeout() {
		cancelListenTimeout()

		listenTimeoutTask = Task { @MainActor [weak self] in
			try? await Task.sleep(for: listenTimeout)

			guard Task.isCancelled == false, let self, state == .listening else { return }

			close(with: DCCTransferError.connectTimeout)
		}
	}

	private func cancelListenTimeout() {
		listenTimeoutTask?.cancel()
		listenTimeoutTask = nil
	}

	func close() {
		guard state != .closed else {
			return
		}

		state = .closed
		tearDown()
	}

	private func close(with error: Error?) {
		guard state != .closed else {
			return
		}

		close()
		client?.directChatConnection(self, didCloseWithError: error)
	}

	private func tearDown() {
		cancelListenTimeout()

		eventTask?.cancel()
		eventTask = nil

		outboundTask?.cancel()
		outboundTask = nil

		if let portMapping {
			portMappingNotifications.cancelAll()
			self.portMapping = nil
			portMapping.close()
		}

		if let chat {
			self.chat = nil

			Task { await chat.close() }
		}
	}

	/** Mirrors the file transfer behaviour: try to map the port through the
	 router, but advertise the listener either way. */
	private func mapListeningPort(_ port: UInt16) {
		let portMapping = PortMapper(port: port)
		portMapping.mapTCP = true
		portMapping.mapUDP = false
		portMapping.desiredPublicPort = port
		self.portMapping = portMapping

		portMappingNotifications.observe(.portMapperDidChange, object: portMapping) { [weak self] _ in
			self?.portMapperDidFinishWork()
		}

		if portMapping.open() == false {
			portMapperDidFinishWork()
		}
	}

	private func portMapperDidFinishWork() {
		guard state == .listening, let portMapping else {
			return
		}

		portMappingNotifications.cancelAll()

		/* The router decides the public port, and it need not be the one asked
		 for: the offer has to name the port and address the peer can reach,
		 not the listener's own. */
		var mappedAddress: String?
		if portMapping.isMapped, portMapping.publicPort != 0 {
			hostPort = portMapping.publicPort
			mappedAddress = portMapping.publicAddress
			let port = hostPort
			directChatLogger.info("Direct chat: mapped to public port \(port, privacy: .public)")
		} else {
			directChatLogger.error(
				"Direct chat: port mapping failed with error code \(portMapping.error, privacy: .public)"
			)
		}

		client?.directChatConnection(self, didStartListeningOnPort: hostPort, mappedAddress: mappedAddress)
	}

	// MARK: - Sending

	func sendMessage(_ message: String) {
		sendLine(message)
	}

	func sendAction(_ message: String) {
		sendLine(CTCPPayload.action(message))
	}

	private func sendLine(_ line: String) {
		guard isConnected, let chat, let client else {
			return
		}

		/* A newline inside the text would be read by the peer as two
		 messages. The caller already split on newlines; this is a guard. */
		var sanitizedLine = line.replacingOccurrences(of: "\r", with: " ")
		sanitizedLine = sanitizedLine.replacingOccurrences(of: "\n", with: " ")

		guard let encoded = client.convert(toCommonEncoding: sanitizedLine) else {
			return
		}

		let previous = outboundTask
		outboundTask = Task { @MainActor [weak self] in
			_ = await previous?.value

			do {
				try await chat.send(encoded)
			} catch {
				self?.close(with: error)
			}
		}
	}

	// MARK: - Receiving

	private func handle(_ event: DCCChatEvent) {
		switch event {
		case let .listening(port):
			guard state == .listening else { return }

			hostPort = port
			mapListeningPort(port)
		case .connected:
			guard state == .listening || state == .connecting else { return }

			cancelListenTimeout()
			state = .connected
			client?.directChatConnectionDidConnect(self)
		case let .lines(_, acknowledged):
			acknowledged.finish()
		case let .closed(error):
			/* A peer that hangs up cleanly ends the conversation; only a real
			 fault is worth reporting as one. */
			close(with: error)
		}
	}

	private func consumeReceivedLine(_ lineData: Data) {
		guard let client,
		      var line = client.convert(fromCommonEncoding: lineData)
		else {
			return
		}

		line = line.trimmingCharacters(in: .newlines)

		if line.isEmpty {
			return
		}

		var isAction = false

		if let actionText = CTCPPayload.actionText(in: line) {
			line = actionText
			isAction = true
		}

		client.directChatConnection(self, didReceiveMessage: line, isAction: isAction)
	}
}
