// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
import os

/// How long a direct chat waits at each step it cannot hurry.
private enum DirectChatSessionPolicy {
	static let connectTimeout: Duration = .seconds(30)
	/** The whole window a listener has to bind a port and take the peer's
	 connection. A listener whose peer never dials in would otherwise hold a
	 mapped router port for the lifetime of the application. */
	static let acceptanceTimeout: Duration = .seconds(300)
	static let writeTimeout: Duration = .seconds(30)
}

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
	private(set) weak var session: ServerSession?
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
	/// Offered or accepted as `DCC SCHAT`. Fixed for the session's life: a
	/// secure chat is never carried on in plain, nor the reverse.
	let isSecure: Bool
	/// What TLS negotiated, once a secure chat is connected.
	private(set) var secureSession: DCCSecureSessionInfo?

	private let role: Role
	private var chat: DirectChatSocket?
	private var eventTask: Task<Void, Never>?
	/** Sends are chained rather than each getting its own task: two `Task`s
	 started in the same turn reach the actor in whatever order the scheduler
	 picks, and a chat that reorders the user's lines is a bug. */
	private var outboundTask: Task<Void, Never>?
	/** The hop that starts the socket. Closing waits for it, so the actor sees
	 `start` before `close` rather than whichever task the scheduler runs first. */
	private var startTask: Task<Void, Never>?
	private var portMapping: PortMapper?
	private let portMappingNotifications = NotificationSubscriptions()

	var isConnected: Bool {
		state == .connected
	}

	/// The owning session's setting snapshot, or the declared defaults once
	/// that session has gone.
	private var settings: ChatSettings {
		session?.environment.settings ?? ChatSettings()
	}

	private init(peer nickname: String, role: Role, secure: Bool, onSession session: ServerSession) {
		peerNickname = nickname
		self.role = role
		isSecure = secure
		self.session = session
	}

	isolated deinit {
		tearDown()
	}

	static func connection(
		toPeer nickname: String,
		address hostAddress: String,
		port hostPort: UInt16,
		secure: Bool = false,
		onSession session: ServerSession
	) -> DirectChatSession {
		precondition(hostPort != 0)

		let object = DirectChatSession(
			peer: nickname,
			role: .connecting(address: hostAddress),
			secure: secure,
			onSession: session
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
		secure: Bool = false,
		onSession session: ServerSession
	) -> DirectChatSession {
		let expectedPeerAddress = offeredAddress.flatMap { DCCWireFormat.isDialableAddress($0) ? $0 : nil } ?? ""
		let object = DirectChatSession(
			peer: nickname,
			role: .listening(expectedPeerAddress: expectedPeerAddress),
			secure: secure,
			onSession: session
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
			interfaceName: settings.fileTransferIPAddressInterfaceName,
			timeout: DirectChatSessionPolicy.connectTimeout
		))
	}

	private func openListener(expectingPeerAt expectedPeerAddress: String) {
		let portRangeStart = settings.fileTransferPortRangeStart
		let portRangeEnd = settings.fileTransferPortRangeEnd

		guard portRangeStart > 0, portRangeStart <= portRangeEnd else {
			close(with: DCCTransferError.noOpenPort)
			return
		}

		state = .listening

		start(
			endpoint: .listen(portRange: portRangeStart ... portRangeEnd),
			expectedPeerAddress: expectedPeerAddress,
			acceptanceTimeout: DirectChatSessionPolicy.acceptanceTimeout
		)
	}

	private func start(
		endpoint: DCCEndpoint,
		expectedPeerAddress: String = "",
		acceptanceTimeout: Duration? = nil
	) {
		let config = DirectChatSocket.Config(
			endpoint: endpoint,
			sendTimeout: DirectChatSessionPolicy.writeTimeout,
			expectedPeerAddress: expectedPeerAddress,
			acceptanceTimeout: acceptanceTimeout
		)
		guard isSecure else {
			start(config)
			return
		}

		/* The identity comes out of the keychain, off the main actor. Nothing
		 is opened before it arrives, and a chat closed meanwhile opens nothing:
		 a secure chat never falls back to plain. */
		startTask = Task { [weak self] in
			guard let session = self?.session else { return }
			let identity: DCCLocalIdentity
			do {
				identity = try await session.dccLocalIdentity()
			} catch {
				DirectConnectionLog.chat.error(
					"Could not load the identity for a secure direct chat: \(error.localizedDescription, privacy: .public)"
				)
				self?.close(with: DCCTransferError.identityUnavailable)
				return
			}
			guard let self, state == .listening || state == .connecting else { return }
			var secured = config
			secured.security = .tls(session.dccTLSConfiguration(identity: identity, context: peerContext))
			start(secured)
		}
	}

	/// Who the verifier asks about: whoever this chat's peer is called now,
	/// for as long as this chat is the one being set up.
	private var peerContext: DCCPeerContext {
		DCCPeerContext(
			nickname: { [weak self] in self?.peerNickname ?? "" },
			isCurrent: { [weak self] in
				guard let self, state == .listening || state == .connecting else { return false }
				return session?.directChatConversation(for: self) != nil
			},
			conversation: { [weak self] in
				guard let self else { return nil }
				return session?.directChatConversation(for: self)
			}
		)
	}

	private func start(_ config: DirectChatSocket.Config) {
		let chat = DirectChatSocket(config: config)
		self.chat = chat

		eventTask = Task { [weak self] in
			for await event in chat.events {
				guard let self else { return }

				if case let .lines(lines, acknowledged) = event {
					for (index, line) in lines.enumerated() {
						await session?.renderAdmission.waitForCapacity()
						guard isConnected, !Task.isCancelled else { break }
						consumeReceivedLine(line)
						if (index + 1).isMultiple(of: 64) {
							await Task.yield()
						}
					}
					await session?.renderAdmission.waitForCapacity()
					acknowledged.finish()
				} else {
					handle(event)
				}
			}
		}

		startTask = Task { await chat.start() }
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
		session?.directChatConnection(self, didCloseWithError: error)
	}

	private func tearDown() {
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

			let started = startTask
			startTask = nil
			Task {
				await started?.value
				await chat.close()
			}
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
			DirectConnectionLog.chat.info("Direct chat: mapped to public port \(port, privacy: .public)")
		} else {
			DirectConnectionLog.chat.error(
				"Direct chat: port mapping failed with error code \(portMapping.error, privacy: .public)"
			)
		}

		session?.directChatConnection(self, didStartListeningOnPort: hostPort, mappedAddress: mappedAddress)
	}

	// MARK: - Sending

	func sendAction(_ message: String) {
		sendLine(CTCPPayload.action(message))
	}

	func sendLine(_ line: String) {
		guard isConnected, let chat, let session else {
			return
		}

		/* A newline inside the text would be read by the peer as two
		 messages. The caller already split on newlines; this is a guard. */
		var sanitizedLine = line.replacingOccurrences(of: "\r", with: " ")
		sanitizedLine = sanitizedLine.replacingOccurrences(of: "\n", with: " ")

		guard let encoded = session.convert(toCommonEncoding: sanitizedLine) else {
			return
		}

		let previous = outboundTask
		outboundTask = Task { [weak self] in
			_ = await previous?.value

			do {
				try await chat.send(encoded)
			} catch {
				self?.close(with: error)
			}
		}
	}

	// MARK: - Receiving

	private func handle(_ event: DirectChatEvent) {
		switch event {
		case let .listening(port):
			guard state == .listening else { return }

			hostPort = port
			mapListeningPort(port)
		case let .connected(secureSession):
			guard state == .listening || state == .connecting else { return }

			self.secureSession = secureSession
			state = .connected
			session?.directChatConnectionDidConnect(self)
		case let .lines(_, acknowledged):
			acknowledged.finish()
		case let .closed(error):
			/* A peer that hangs up cleanly ends the conversation; only a real
			 fault is worth reporting as one. */
			close(with: error)
		}
	}

	private func consumeReceivedLine(_ lineData: Data) {
		guard let session,
		      var line = session.convert(fromCommonEncoding: lineData)
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

		session.directChatConnection(self, didReceiveMessage: line, isAction: isAction)
	}
}
