/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\\_\\__|\\__,_|\\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import Foundation
import os

private let connectTimeout: TimeInterval = 30.0
private let writeTimeout: TimeInterval = 30.0
private let maximumLineLength = 1024 * 16

private let directChatLogger = Logger(
	subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
	category: "DirectChat"
)

@objc
public enum IRCDirectChatConnectionState: UInt {
	case idle = 0
	case listening
	case connecting
	case connected
	case closed
}

@objc
public protocol IRCDirectChatConnectionDelegate: NSObjectProtocol {
	@objc(directChatConnection:didStartListeningOnPort:)
	func directChatConnection(_ connection: DirectChatConnection, didStartListeningOnPort port: UInt16)

	@objc(directChatConnectionDidConnect:)
	func directChatConnectionDidConnect(_ connection: DirectChatConnection)

	@objc(directChatConnection:didReceiveMessage:isAction:)
	func directChatConnection(
		_ connection: DirectChatConnection,
		didReceiveMessage message: String,
		isAction: Bool
	)

	@objc(directChatConnection:didCloseWithError:)
	func directChatConnection(_ connection: DirectChatConnection, didCloseWithError error: Error?)
}

/* A DCC CHAT session. One instance is one TCP connection to one peer.
 All state belongs to the main queue: the socket delivers its callbacks
 there and every method below must be called from there. */
@objc(IRCDirectChatConnection)
public final class DirectChatConnection: NSObject, TDCFileTransferDialogSocketDelegate {
	@objc public private(set) weak var client: IRCClient?
	@objc public private(set) weak var delegate: IRCDirectChatConnectionDelegate?
	@objc public private(set) var peerNickname: String
	@objc public private(set) var hostAddress: String?
	@objc public private(set) var hostPort: UInt16 = 0
	@objc public private(set) var transferToken: String?
	@objc public private(set) var state: IRCDirectChatConnectionState = .idle

	private var isListener = false
	private var listeningServer: TDCFileTransferDialogSocket?
	private var connection: TDCFileTransferDialogSocket?
	private var portMapping: XRPortMapper?
	private var lineBuffer = NSMutableData()

	@objc public var isConnected: Bool {
		state == .connected
	}

	@available(*, unavailable)
	override public init() {
		fatalError("Use factory methods")
	}

	private init(
		peer nickname: String,
		onClient client: IRCClient,
		delegate: IRCDirectChatConnectionDelegate
	) {
		peerNickname = nickname
		self.client = client
		self.delegate = delegate
		super.init()
	}

	deinit {
		tearDownSockets()
	}

	@objc(connectionToPeer:address:port:onClient:delegate:)
	public class func connection(
		toPeer nickname: String,
		address hostAddress: String,
		port hostPort: UInt16,
		onClient client: IRCClient,
		delegate: IRCDirectChatConnectionDelegate
	) -> DirectChatConnection {
		precondition(hostPort != 0)

		let object = DirectChatConnection(peer: nickname, onClient: client, delegate: delegate)
		object.hostAddress = hostAddress
		object.hostPort = hostPort
		object.isListener = false
		return object
	}

	@objc(listeningConnectionForPeer:token:onClient:delegate:)
	public class func listeningConnection(
		forPeer nickname: String,
		token transferToken: String?,
		onClient client: IRCClient,
		delegate: IRCDirectChatConnectionDelegate
	) -> DirectChatConnection {
		let object = DirectChatConnection(peer: nickname, onClient: client, delegate: delegate)

		if let transferToken, transferToken.isEmpty == false {
			object.transferToken = transferToken
		}

		object.isListener = true
		return object
	}

	@objc
	public func open() {
		dispatchPrecondition(condition: .onQueue(.main))

		guard state == .idle else {
			return
		}

		if isListener {
			openListener()
		} else {
			openConnection()
		}
	}

	private func openConnection() {
		state = .connecting

		let connection = TDCFileTransferDialogSocket(
			delegate: self,
			delegateQueue: DispatchQueue.main
		)
		self.connection = connection

		guard let hostAddress else {
			return
		}

		connection.connect(
			toHost: hostAddress,
			port: hostPort,
			viaInterface: TPCPreferences.fileTransferIPAddressInterfaceName(),
			timeout: connectTimeout
		)
	}

	private func openListener() {
		let portRangeStart = TPCPreferences.fileTransferPortRangeStart()
		let portRangeEnd = TPCPreferences.fileTransferPortRangeEnd()

		if portRangeStart == 0 || portRangeStart > portRangeEnd {
			close(
				with: TDCFileTransferDialogSocket.error(
					withCode: .noOpenPort,
					description: "The file transfer port range is invalid"
				)
			)
			return
		}

		state = .listening

		let listeningServer = TDCFileTransferDialogSocket(
			delegate: self,
			delegateQueue: DispatchQueue.main
		)
		self.listeningServer = listeningServer
		listeningServer.listenOnPortRange(from: portRangeStart, to: portRangeEnd)
	}

	@objc
	public func close() {
		dispatchPrecondition(condition: .onQueue(.main))

		guard state != .closed else {
			return
		}

		state = .closed
		tearDownSockets()
	}

	private func close(with error: Error?) {
		guard state != .closed else {
			return
		}

		close()
		delegate?.directChatConnection(self, didCloseWithError: error)
	}

	private func tearDownSockets() {
		if let portMapping {
			NotificationCenter.default.removeObserver(
				self,
				name: .XRPortMapperDidChanged,
				object: portMapping
			)
			self.portMapping = nil
			portMapping.close()
		}

		if let listeningServer {
			self.listeningServer = nil
			listeningServer.disconnect()
		}

		if let connection {
			self.connection = nil
			connection.disconnect()
		}
	}

	/* Mirrors the file transfer behaviour: try to map the port through the
	 router, but advertise the listener either way. */
	private func mapListeningPort(_ port: UInt16) {
		let portMapping = XRPortMapper(port: port)
		portMapping.mapTCP = true
		portMapping.mapUDP = false
		portMapping.desiredPublicPort = port
		self.portMapping = portMapping

		NotificationCenter.default.addObserver(
			self,
			selector: #selector(portMapperDidFinishWork(_:)),
			name: .XRPortMapperDidChanged,
			object: portMapping
		)

		if portMapping.open() == false {
			portMapperDidFinishWork(nil)
		}
	}

	@objc
	private func portMapperDidFinishWork(_: Notification?) {
		dispatchPrecondition(condition: .onQueue(.main))

		guard state == .listening, let portMapping else {
			return
		}

		NotificationCenter.default.removeObserver(
			self,
			name: .XRPortMapperDidChanged,
			object: portMapping
		)

		if portMapping.isMapped {
			directChatLogger.info("Direct chat: port \(self.hostPort, privacy: .public) mapped")
		} else {
			directChatLogger.error(
				"Direct chat: port mapping failed with error code \(portMapping.error, privacy: .public)"
			)
		}

		delegate?.directChatConnection(self, didStartListeningOnPort: hostPort)
	}

	@objc(sendMessage:)
	public func sendMessage(_ message: String) {
		sendLine(message)
	}

	@objc(sendAction:)
	public func sendAction(_ message: String) {
		sendLine(String(format: "%cACTION %@%c", 0x01, message, 0x01))
	}

	private func sendLine(_ line: String) {
		dispatchPrecondition(condition: .onQueue(.main))

		guard isConnected, let client else {
			return
		}

		/* A newline inside the text would be read by the peer as two
		 messages. The caller already split on newlines; this is a guard. */
		var sanitizedLine = line.replacingOccurrences(of: "\r", with: " ")
		sanitizedLine = sanitizedLine.replacingOccurrences(of: "\n", with: " ")

		guard let encoded = client.convert(toCommonEncoding: sanitizedLine) else {
			return
		}

		let data = NSMutableData(data: encoded)
		data.append("\r\n".data(using: .utf8)!)
		connection?.write(data as Data, timeout: writeTimeout)
	}

	private func consumeReceivedData(_ data: Data) {
		lineBuffer.append(data)

		while lineBuffer.length > 0 {
			let newlineRange = lineBuffer.range(
				of: Data([0x0A]),
				options: [],
				in: NSRange(location: 0, length: lineBuffer.length)
			)

			if newlineRange.location == NSNotFound {
				if lineBuffer.length > maximumLineLength {
					close(
						with: TDCFileTransferDialogSocket.error(
							withCode: .badParameter,
							description: "The peer sent a line which is too long"
						)
					)
				}
				return
			}

			let lineData = lineBuffer.subdata(with: NSRange(location: 0, length: newlineRange.location))
			lineBuffer.replaceBytes(
				in: NSRange(location: 0, length: newlineRange.location + 1),
				withBytes: nil,
				length: 0
			)

			consumeReceivedLine(lineData)

			if state == .closed {
				return
			}
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
		let actionPrefix = String(format: "%cACTION ", 0x01)

		if line.hasPrefix(actionPrefix) {
			let prefixLength = actionPrefix.count
			let suffixLength = line.hasSuffix(String(format: "%c", 0x01)) ? 1 : 0

			if line.count > (prefixLength + suffixLength) {
				let start = line.index(line.startIndex, offsetBy: prefixLength)
				let end = line.index(line.endIndex, offsetBy: -suffixLength)
				line = String(line[start..<end])
			} else {
				line = ""
			}

			isAction = true
		}

		delegate?.directChatConnection(self, didReceiveMessage: line, isAction: isAction)
	}

	// MARK: - Socket Delegate

	public func socket(_ socket: TDCFileTransferDialogSocket, didStartListeningOnPort port: UInt16) {
		dispatchPrecondition(condition: .onQueue(.main))

		guard socket === listeningServer else {
			return
		}

		hostPort = port
		mapListeningPort(port)
	}

	public func socket(_ socket: TDCFileTransferDialogSocket, didFailToListenWithError error: Error) {
		dispatchPrecondition(condition: .onQueue(.main))

		guard socket === listeningServer else {
			return
		}

		close(with: error)
	}

	public func socket(
		_ socket: TDCFileTransferDialogSocket,
		didAcceptConnection connection: TDCFileTransferDialogSocket
	) {
		dispatchPrecondition(condition: .onQueue(.main))

		if socket !== listeningServer || state != .listening {
			connection.disconnect()
			return
		}

		/* One peer only. Stop listening the moment somebody connects. */
		listeningServer = nil
		socket.disconnect()
		self.connection = connection
		connectionDidBecomeReady()
	}

	public func socketDidConnect(_ socket: TDCFileTransferDialogSocket) {
		dispatchPrecondition(condition: .onQueue(.main))

		guard socket === connection, state == .connecting else {
			return
		}

		connectionDidBecomeReady()
	}

	private func connectionDidBecomeReady() {
		state = .connected
		connection?.readData()
		delegate?.directChatConnectionDidConnect(self)
	}

	public func socket(_ socket: TDCFileTransferDialogSocket, didRead data: Data) {
		dispatchPrecondition(condition: .onQueue(.main))

		guard socket === connection, isConnected else {
			return
		}

		consumeReceivedData(data)

		if isConnected {
			socket.readData()
		}
	}

	public func socketDidWriteData(_: TDCFileTransferDialogSocket) {
		/* Nothing to do. Writes are fire and forget. */
	}

	public func socket(_ socket: TDCFileTransferDialogSocket, didDisconnectWithError error: Error?) {
		dispatchPrecondition(condition: .onQueue(.main))

		guard socket === connection || socket === listeningServer else {
			return
		}

		var closeError = error

		/* A clean close by the peer arrives as a "closed by peer" error.
		 Treat that as a normal end of the conversation. */
		if let nsError = error as NSError?,
			nsError.domain == TDCFileTransferDialogSocketErrorDomain,
			nsError.code == TDCFileTransferDialogSocketError.closedByPeer.rawValue
		{
			closeError = nil
		}

		close(with: closeError)
	}
}
