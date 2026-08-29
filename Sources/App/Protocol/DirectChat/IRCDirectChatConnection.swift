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

public enum IRCDirectChatConnectionState: UInt {
	case idle = 0
	case listening
	case connecting
	case connected
	case closed
}

public protocol IRCDirectChatConnectionDelegate: NSObjectProtocol {
	func directChatConnection(_ connection: DirectChatConnection, didStartListeningOnPort port: UInt16)

	func directChatConnectionDidConnect(_ connection: DirectChatConnection)

	func directChatConnection(
		_ connection: DirectChatConnection,
		didReceiveMessage message: String,
		isAction: Bool
	)

	func directChatConnection(_ connection: DirectChatConnection, didCloseWithError error: Error?)
}

/** A DCC CHAT session. One instance is one TCP connection to one peer.

 The socket itself belongs to a ``DCCChatConnection`` actor, which does the
 framing and hands whole lines back through its event stream. Everything here —
 the state machine, the port mapping, the encoding, the delegate — belongs to
 the main actor, and the event loop below is the one seam between the two. */
public final class DirectChatConnection: NSObject {
	public private(set) weak var client: IRCClient?
	public private(set) weak var delegate: IRCDirectChatConnectionDelegate?
	public private(set) var peerNickname: String
	/** Only the connecting variant has an address; the listening variant learns its
	 port from the socket. Modelling it this way removes the unreachable dead-end
	 `openConnection()` used to hit when the address was nil. */
	private enum Role {
		case listening
		case connecting(address: String)
	}

	public var hostAddress: String? {
		guard case let .connecting(address) = role else { return nil }
		return address
	}

	public private(set) var hostPort: UInt16 = 0
	public private(set) var transferToken: String?
	public private(set) var state: IRCDirectChatConnectionState = .idle

	private let role: Role
	private var chat: DCCChatConnection?
	private var eventTask: Task<Void, Never>?
	private var listenTimeoutTask: Task<Void, Never>?
	/** Sends are chained rather than each getting its own task: two `Task`s
	 started in the same turn reach the actor in whatever order the scheduler
	 picks, and a chat that reorders the user's lines is a bug. */
	private var outboundTask: Task<Void, Never>?
	private var portMapping: XRPortMapper?
	private let portMappingNotifications = NotificationSubscriptions()

	public var isConnected: Bool {
		state == .connected
	}

	/// The owning client's preference snapshot, or the declared defaults once
	/// that client has gone.
	private var preferences: ClientPreferences {
		client?.environment.preferences ?? ClientPreferences()
	}

	@available(*, unavailable)
	override public init() {
		fatalError("Use factory methods")
	}

	private init(
		peer nickname: String,
		role: Role,
		onClient client: IRCClient,
		delegate: IRCDirectChatConnectionDelegate
	) {
		peerNickname = nickname
		self.role = role
		self.client = client
		self.delegate = delegate
		super.init()
	}

	isolated deinit {
		tearDown()
	}

	public static func connection(
		toPeer nickname: String,
		address hostAddress: String,
		port hostPort: UInt16,
		onClient client: IRCClient,
		delegate: IRCDirectChatConnectionDelegate
	) -> DirectChatConnection {
		precondition(hostPort != 0)

		let object = DirectChatConnection(
			peer: nickname,
			role: .connecting(address: hostAddress),
			onClient: client,
			delegate: delegate
		)
		object.hostPort = hostPort
		return object
	}

	public static func listeningConnection(
		forPeer nickname: String,
		token transferToken: String?,
		onClient client: IRCClient,
		delegate: IRCDirectChatConnectionDelegate
	) -> DirectChatConnection {
		let object = DirectChatConnection(
			peer: nickname,
			role: .listening,
			onClient: client,
			delegate: delegate
		)

		if let transferToken, transferToken.isEmpty == false {
			object.transferToken = transferToken
		}

		return object
	}

	public func open() {
		guard state == .idle else {
			return
		}

		switch role {
		case .listening:
			openListener()
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

	private func openListener() {
		let portRangeStart = preferences.fileTransferPortRangeStart
		let portRangeEnd = preferences.fileTransferPortRangeEnd

		guard portRangeStart > 0, portRangeStart <= portRangeEnd else {
			close(with: DCCTransferError.noOpenPort)
			return
		}

		state = .listening

		start(endpoint: .listen(portRange: portRangeStart ... portRangeEnd))
		startListenTimeout()
	}

	private func start(endpoint: DCCChatConnection.Endpoint) {
		let chat = DCCChatConnection(configuration: DCCChatConnection.Configuration(
			endpoint: endpoint,
			maximumLineLength: maximumLineLength,
			sendTimeout: writeTimeout
		))
		self.chat = chat

		eventTask = Task { @MainActor [weak self] in
			for await event in chat.events {
				guard let self else { return }

				handle(event)
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

	public func close() {
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
		delegate?.directChatConnection(self, didCloseWithError: error)
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
		let portMapping = XRPortMapper(port: port)
		portMapping.mapTCP = true
		portMapping.mapUDP = false
		portMapping.desiredPublicPort = port
		self.portMapping = portMapping

		portMappingNotifications.observe(.XRPortMapperDidChanged, object: portMapping) { [weak self] _ in
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

		if portMapping.isMapped {
			let port = hostPort
			directChatLogger.info("Direct chat: port \(port, privacy: .public) mapped")
		} else {
			directChatLogger.error(
				"Direct chat: port mapping failed with error code \(portMapping.error, privacy: .public)"
			)
		}

		delegate?.directChatConnection(self, didStartListeningOnPort: hostPort)
	}

	// MARK: - Sending

	public func sendMessage(_ message: String) {
		sendLine(message)
	}

	public func sendAction(_ message: String) {
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
			delegate?.directChatConnectionDidConnect(self)
		case let .line(data):
			guard isConnected else { return }

			consumeReceivedLine(data)
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

		delegate?.directChatConnection(self, didReceiveMessage: line, isAction: isAction)
	}
}
