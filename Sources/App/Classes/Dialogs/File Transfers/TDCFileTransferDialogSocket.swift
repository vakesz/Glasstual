/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
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

import Darwin
import Foundation
import Network
import os
import Synchronization

public let TDCFileTransferDialogSocketErrorDomain = "TDCFileTransferDialogSocketErrorDomain"

@objc(TDCFileTransferDialogSocketError)
public enum FileTransferDialogSocketError: Int, Error {
	case connectTimeout = 1
	case writeTimeout
	case closedByPeer
	case noOpenPort
	case badParameter
}

public typealias TDCFileTransferDialogSocketError = FileTransferDialogSocketError

@objc(TDCFileTransferDialogSocketDelegate)
public protocol FileTransferDialogSocketDelegate: AnyObject {
	@objc optional func socket(_ socket: FileTransferDialogSocket, didStartListeningOnPort port: UInt16)
	@objc optional func socket(_ socket: FileTransferDialogSocket, didFailToListenWithError error: Error)
	@objc optional func socket(
		_ socket: FileTransferDialogSocket,
		didAcceptConnection connection: FileTransferDialogSocket
	)
	@objc optional func socketDidConnect(_ socket: FileTransferDialogSocket)
	@objc(socket:didReadData:)
	optional func socket(_ socket: FileTransferDialogSocket, didRead data: Data)
	@objc optional func socketDidWriteData(_ socket: FileTransferDialogSocket)
	@objc optional func socket(_ socket: FileTransferDialogSocket, didDisconnectWithError error: Error?)
}

public typealias TDCFileTransferDialogSocketDelegate = FileTransferDialogSocketDelegate
public typealias TDCFileTransferDialogSocket = FileTransferDialogSocket

/**
 A sendable handle for a dispatch work item whose only cross-queue operation is
 cancellation. `DispatchWorkItem.cancel()` is thread-safe, while the work item
 itself has not adopted `Sendable`.
 */
private final class FileTransferTimeout: @unchecked Sendable {
	let workItem: DispatchWorkItem

	init(workItem: DispatchWorkItem) {
		self.workItem = workItem
	}

	func cancel() {
		workItem.cancel()
	}
}

/**
 A queue-confined Network.framework wrapper used by DCC file transfers.

 Every mutable network object belongs to `socketQueue`. The two flags read by
 other queues use `Mutex`, and the class is `@unchecked Sendable` only because
 Network.framework and Objective-C delegate callbacks cannot express that
 queue confinement to Swift's type system.
 */
@objc(TDCFileTransferDialogSocket)
public final class FileTransferDialogSocket: NSObject, @unchecked Sendable {
	private typealias ReceiveCompletion = @Sendable (Data?, NWConnection.ContentContext?, Bool, NWError?) -> Void

	private static let maximumReadLength = 64 * 1024
	private static let logger = Logger(
		subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
		category: "FileTransferSocket"
	)

	@objc public private(set) weak var delegate: FileTransferDialogSocketDelegate?
	@objc public let delegateQueue: DispatchQueue

	private let socketQueue: DispatchQueue
	private let invalidated = Mutex(false)
	private let connected = Mutex(false)

	private var listener: NWListener?
	private var connection: NWConnection?
	private var parentListener: FileTransferDialogSocket?
	private var pendingAcceptedConnections = Set<FileTransferDialogSocket>()
	private var outboundConnection = false
	private var nextListenPort: UInt16 = 0
	private var lastListenPort: UInt16 = 0
	private var closed = false
	private var connectTimeoutWorkItem: DispatchWorkItem?

	@objc public private(set) var isListener = false

	@objc public var isConnected: Bool {
		connected.withLock { $0 }
	}

	@objc(initWithDelegate:delegateQueue:)
	public init(delegate: FileTransferDialogSocketDelegate, delegateQueue: DispatchQueue) {
		self.delegate = delegate
		self.delegateQueue = delegateQueue
		socketQueue = DispatchQueue(
			label: "Glasstual.TDCFileTransferDialogSocket-\(UUID().uuidString)",
			qos: .default
		)
		super.init()
	}

	@available(*, unavailable)
	override public init() {
		fatalError("init() is unavailable")
	}

	deinit {
		let timeoutWorkItem = connectTimeoutWorkItem
		let listener = listener
		let connection = connection

		guard timeoutWorkItem != nil || listener != nil || connection != nil else {
			return
		}

		/* Dispatch work-item cancellation is thread-safe. Cancel before hopping
		 to the socket queue so the sendable cleanup closure only captures
		 Network.framework values. */
		timeoutWorkItem?.cancel()

		socketQueue.async {
			listener?.cancel()
			connection?.cancel()
		}
	}

	@objc(errorWithCode:description:)
	public static func error(withCode code: FileTransferDialogSocketError, description: String) -> NSError {
		NSError(
			domain: TDCFileTransferDialogSocketErrorDomain,
			code: code.rawValue,
			userInfo: [NSLocalizedDescriptionKey: description]
		)
	}

	private static func error(
		from networkError: NWError?,
		fallbackCode: FileTransferDialogSocketError
	) -> NSError {
		if let networkError {
			return networkError as NSError
		}

		return error(withCode: fallbackCode, description: "Unknown socket error")
	}

	private var isInvalidated: Bool {
		invalidated.withLock { $0 }
	}

	private func setConnected(_ value: Bool) {
		connected.withLock { $0 = value }
	}

	private func deliverToDelegate(
		_ action: @escaping @Sendable (FileTransferDialogSocketDelegate) -> Void
	) {
		delegateQueue.async { [self] in
			guard isInvalidated == false, let delegate else {
				return
			}

			action(delegate)
		}
	}

	private func tearDownNetworkObjects() {
		connectTimeoutWorkItem?.cancel()
		connectTimeoutWorkItem = nil

		listener?.cancel()
		listener = nil

		connection?.cancel()
		connection = nil

		setConnected(false)
		parentListener = nil

		let acceptedConnections = pendingAcceptedConnections
		pendingAcceptedConnections.removeAll()

		for connection in acceptedConnections {
			connection.disconnect()
		}
	}

	private func fail(with error: NSError) {
		guard closed == false, isInvalidated == false else {
			return
		}

		closed = true
		let wasConnected = isConnected
		let wasOutbound = outboundConnection
		let listener = parentListener
		tearDownNetworkObjects()

		if wasConnected == false, wasOutbound == false {
			listener?.acceptedConnectionDidFail(self)
			return
		}

		deliverToDelegate { [weak self] delegate in
			guard let self else {
				return
			}

			delegate.socket?(self, didDisconnectWithError: error)
		}
	}

	@objc public func disconnect() {
		invalidated.withLock { $0 = true }

		socketQueue.async { [self] in
			closed = true
			tearDownNetworkObjects()
		}
	}

	// MARK: - Listening

	@objc(listenOnPortRangeFrom:to:)
	public func listenOnPortRange(from startPort: UInt16, to endPort: UInt16) {
		socketQueue.async { [self] in
			guard closed == false, isInvalidated == false else {
				return
			}

			isListener = true
			nextListenPort = startPort
			lastListenPort = endPort
			listenOnNextPort()
		}
	}

	private func listenOnNextPort() {
		guard closed == false, isInvalidated == false else {
			return
		}

		let port = nextListenPort

		guard port > 0, port <= lastListenPort else {
			failToListen(
				with: Self.error(
					withCode: .noOpenPort,
					description: "No port in the configured range could be opened"
				)
			)
			return
		}

		nextListenPort = port &+ 1

		guard let networkPort = NWEndpoint.Port(rawValue: port),
		      let listener = try? NWListener(using: .tcp, on: networkPort)
		else {
			listenOnNextPort()
			return
		}

		self.listener = listener

		listener.stateUpdateHandler = { [weak self, weak listener] state in
			guard let self, let listener, self.listener === listener else {
				return
			}

			handle(listener: listener, state: state)
		}

		listener.newConnectionHandler = { [weak self, weak listener] connection in
			guard let self, let listener, self.listener === listener else {
				connection.cancel()
				return
			}

			accept(connection: connection)
		}

		listener.start(queue: socketQueue)
	}

	private func handle(listener: NWListener, state: NWListener.State) {
		switch state {
		case .setup, .waiting:
			break
		case .ready:
			guard let port = listener.port?.rawValue else {
				failToListen(with: Self.error(withCode: .noOpenPort, description: "Listener has no bound port"))
				return
			}

			setConnected(true)
			deliverToDelegate { [weak self] delegate in
				guard let self else {
					return
				}

				delegate.socket?(self, didStartListeningOnPort: port)
			}
		case let .failed(error):
			let listenError = Self.error(from: error, fallbackCode: .noOpenPort)

			if isConnected {
				fail(with: listenError)
				return
			}

			Self.logger.debug(
				"Failed to listen on port \(listener.port?.rawValue ?? 0, privacy: .public): \(listenError.localizedDescription, privacy: .public)"
			)
			self.listener = nil
			listener.cancel()
			listenOnNextPort()
		case .cancelled:
			if self.listener === listener {
				self.listener = nil
			}
		@unknown default:
			break
		}
	}

	private func failToListen(with error: NSError) {
		guard closed == false, isInvalidated == false else {
			return
		}

		closed = true
		tearDownNetworkObjects()
		deliverToDelegate { [weak self] delegate in
			guard let self else {
				return
			}

			delegate.socket?(self, didFailToListenWithError: error)
		}
	}

	private func accept(connection: NWConnection) {
		guard closed == false, isInvalidated == false, let delegate else {
			connection.cancel()
			return
		}

		let accepted = FileTransferDialogSocket(delegate: delegate, delegateQueue: delegateQueue)
		pendingAcceptedConnections.insert(accepted)
		accepted.adopt(connection: connection, acceptedBy: self)
	}

	private func acceptedConnectionDidFail(_ connection: FileTransferDialogSocket) {
		socketQueue.async { [self] in
			pendingAcceptedConnections.remove(connection)
		}
	}

	private func acceptedConnectionIsReady(_ connection: FileTransferDialogSocket) {
		socketQueue.async { [self] in
			pendingAcceptedConnections.remove(connection)

			guard closed == false, isInvalidated == false else {
				connection.disconnect()
				return
			}

			deliverToDelegate { [weak self, connection] delegate in
				guard let self else {
					return
				}

				delegate.socket?(self, didAcceptConnection: connection)
			}
		}
	}

	// MARK: - Connecting

	private func adopt(connection: NWConnection, acceptedBy listener: FileTransferDialogSocket) {
		socketQueue.async { [self] in
			parentListener = listener
			outboundConnection = false
			start(connection: connection)
		}
	}

	@objc(connectToHost:port:viaInterface:timeout:)
	public func connect(
		toHost host: String,
		port: UInt16,
		viaInterface interfaceName: String?,
		timeout: TimeInterval
	) {
		socketQueue.async { [self] in
			guard closed == false, isInvalidated == false else {
				return
			}

			outboundConnection = true

			guard host.isEmpty == false, let networkPort = NWEndpoint.Port(rawValue: port) else {
				fail(with: Self.error(withCode: .badParameter, description: "Invalid host address or port"))
				return
			}

			let parameters = NWParameters.tcp

			if timeout > 0,
			   let tcpOptions = parameters.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options
			{
				tcpOptions.connectionTimeout = Int(ceil(timeout))
			}

			if let interfaceName, interfaceName.isEmpty == false {
				if let localAddress = Self.address(ofInterfaceNamed: interfaceName) {
					parameters.requiredLocalEndpoint = .hostPort(host: NWEndpoint.Host(localAddress), port: .any)
				} else {
					Self.logger.error(
						"Interface '\(interfaceName, privacy: .public)' has no usable address. Using the default interface."
					)
				}
			}

			let connection = NWConnection(host: NWEndpoint.Host(host), port: networkPort, using: parameters)

			if timeout > 0 {
				let timeoutWorkItem = DispatchWorkItem { [weak self, weak connection] in
					guard let self, let connection, self.connection === connection, isConnected == false else {
						return
					}

					fail(
						with: Self.error(
							withCode: .connectTimeout,
							description: "Connection attempt timed out"
						)
					)
				}

				connectTimeoutWorkItem = timeoutWorkItem
				socketQueue.asyncAfter(deadline: .now() + timeout, execute: timeoutWorkItem)
			}

			start(connection: connection)
		}
	}

	private static func address(ofInterfaceNamed interfaceName: String) -> String? {
		var interfaceList: UnsafeMutablePointer<ifaddrs>?

		guard getifaddrs(&interfaceList) == 0, let firstInterface = interfaceList else {
			return nil
		}

		defer { freeifaddrs(firstInterface) }

		var ipv4Address: String?
		var ipv6Address: String?
		var current: UnsafeMutablePointer<ifaddrs>? = firstInterface

		while let interface = current {
			defer { current = interface.pointee.ifa_next }

			guard let address = interface.pointee.ifa_addr,
			      interface.pointee.ifa_flags & UInt32(IFF_UP) != 0,
			      String(cString: interface.pointee.ifa_name) == interfaceName
			else {
				continue
			}

			let family = Int32(address.pointee.sa_family)

			guard family == AF_INET || family == AF_INET6 else {
				continue
			}

			var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
			let addressLength = socklen_t(family == AF_INET ? MemoryLayout<sockaddr_in>
				.size : MemoryLayout<sockaddr_in6>.size)

			guard getnameinfo(address, addressLength, &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else {
				continue
			}

			let hostBytes = host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }

			guard let hostAddress = String(bytes: hostBytes, encoding: .utf8) else {
				continue
			}

			if family == AF_INET, ipv4Address == nil {
				ipv4Address = hostAddress
			} else if family == AF_INET6,
			          ipv6Address == nil,
			          hostAddress.lowercased().hasPrefix("fe80:") == false
			{
				ipv6Address = hostAddress
			}
		}

		return ipv4Address ?? ipv6Address
	}

	private func start(connection: NWConnection) {
		guard closed == false, isInvalidated == false else {
			connection.cancel()
			return
		}

		self.connection = connection
		connection.stateUpdateHandler = { [weak self, weak connection] state in
			guard let self, let connection, self.connection === connection else {
				return
			}

			handle(connection: connection, state: state)
		}
		connection.start(queue: socketQueue)
	}

	private func handle(connection: NWConnection, state: NWConnection.State) {
		switch state {
		case .setup, .preparing:
			break
		case let .waiting(error):
			Self.logger.debug("Connection is waiting: \(error.localizedDescription, privacy: .public)")
		case .ready:
			connectTimeoutWorkItem?.cancel()
			connectTimeoutWorkItem = nil
			setConnected(true)

			if let listener = parentListener {
				parentListener = nil
				listener.acceptedConnectionIsReady(self)
				return
			}

			deliverToDelegate { [weak self] delegate in
				guard let self else {
					return
				}

				delegate.socketDidConnect?(self)
			}
		case let .failed(error):
			fail(with: Self.error(from: error, fallbackCode: .closedByPeer))
		case .cancelled:
			if self.connection === connection {
				self.connection = nil
			}
		@unknown default:
			break
		}
	}

	// MARK: - Reading

	@objc public func readData() {
		socketQueue.async { [self] in
			guard closed == false,
			      isInvalidated == false,
			      let connection,
			      isConnected
			else {
				return
			}

			let connectionIdentity = ObjectIdentifier(connection)
			let receiveCompletion: ReceiveCompletion = { [weak self] content, _, isComplete, error in
				guard let self,
				      let activeConnection = self.connection,
				      ObjectIdentifier(activeConnection) == connectionIdentity
				else {
					return
				}

				didReceive(content: content, isComplete: isComplete, error: error)
			}

			connection.receive(
				minimumIncompleteLength: 1,
				maximumLength: Self.maximumReadLength,
				completion: receiveCompletion
			)
		}
	}

	private func didReceive(content: Data?, isComplete: Bool, error: NWError?) {
		guard closed == false, isInvalidated == false else {
			return
		}

		if let content, content.isEmpty == false {
			deliverToDelegate { [weak self, content] delegate in
				guard let self else {
					return
				}

				delegate.socket?(self, didRead: content)
			}
		}

		if let error {
			fail(with: Self.error(from: error, fallbackCode: .closedByPeer))
			return
		}

		if isComplete {
			fail(with: Self.error(withCode: .closedByPeer, description: "Socket closed by remote peer"))
		}
	}

	// MARK: - Writing

	@objc(writeData:timeout:)
	public func write(_ data: Data, timeout: TimeInterval) {
		socketQueue.async { [self] in
			guard closed == false,
			      isInvalidated == false,
			      let connection,
			      isConnected
			else {
				return
			}

			let timeoutHandle: FileTransferTimeout? = if timeout > 0 {
				FileTransferTimeout(workItem: DispatchWorkItem { [weak self, weak connection] in
					guard let self, let connection, self.connection === connection else {
						return
					}

					fail(with: Self.error(withCode: .writeTimeout, description: "Write operation timed out"))
				})
			} else {
				nil
			}

			if let timeoutHandle {
				socketQueue.asyncAfter(deadline: .now() + timeout, execute: timeoutHandle.workItem)
			}

			connection.send(content: data, completion: .contentProcessed { [weak self, weak connection] error in
				timeoutHandle?.cancel()

				guard let self,
				      let connection,
				      self.connection === connection,
				      closed == false,
				      isInvalidated == false
				else {
					return
				}

				if let error {
					fail(with: Self.error(from: error, fallbackCode: .closedByPeer))
					return
				}

				deliverToDelegate { [weak self] delegate in
					guard let self else {
						return
					}

					delegate.socketDidWriteData?(self)
				}
			})
		}
	}
}
