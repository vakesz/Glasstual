/* *********************************************************************
*                  _____         _               _
*                 |_   _|____  _| |_ _   _  __ _| |
*                   | |/ _ \ \/ / __| | | |/ _` | |
*                   | |  __/>  <| |_| |_| | (_| | |
*                   |_|\___/_/\_\\__|\__,_|\__,_|_|
*
* Copyright (c) 2018 - 2020 Codeux Software, LLC & respective contributors.
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

/* Connection is the object RCMProcessMain drives over XPC. It owns the
 send queue, flood control, and the transport socket.

 Concurrency model:
 A single serial `queue` is created per Connection and shared with the
 socket. Every XPC entry point hops onto it asynchronously (or, for the
 one synchronous reply, with queue.sync) and every socket callback is
 already delivered on it. That makes sendQueue, the flood control
 counters, and the socket's flags mutually exclusive by construction;
 no locks are needed. The class is `@unchecked Sendable` because the
 compiler cannot prove that confinement, so the rule is: never read or
 write a stored property of this class or its socket off `queue`. */
@objc(IRCConnection)
final class Connection: NSObject, ConnectionSocketDelegate, @unchecked Sendable {
	fileprivate let config: IRCConnectionConfig

	fileprivate let queue: DispatchQueue

	fileprivate let socket: ConnectionSocket & ConnectionSocketProtocol

	fileprivate let serviceConnection: NSXPCConnection

	fileprivate var sendQueue: [Data] = []

	fileprivate lazy var floodControlTimer: TLOTimer =
		{
			return TLOTimer(
				actionBlock: { [weak self] _ in
					self?.onFloodControlTimer()
				}, on: queue)
		}()

	fileprivate var floodControlCurrentMessageCount = 0
	fileprivate var floodControlEnforced = false

	enum ConnectionError: Error {
		/// socketError are errors returned by the connection library.
		/// For example: Network.framework
		case socket(error: Error)

		// otherError are errors returned by ConnectionSocket instances.
		case other(message: String)

		/// invalidCertificate are errors returned when the connection
		/// cannot be secured because of problem with certificate.
		case badCertificate(failureReason: String)

		/// unableToSecure are errors returned when the connection
		/// cannot be secured for some reason. e.g. handshake failure
		case unableToSecure(failureReason: String)
	}  // ConnectionError

	// MARK: - Initialization

	@objc(initWithConfig:onConnection:)
	init(with config: IRCConnectionConfig, on connection: NSXPCConnection) {
		self.config = config

		serviceConnection = connection

		let uniqueIdentifier = UUID().uuidString

		queue = DispatchQueue(label: "Glasstual.IRCConnection.queue.\(uniqueIdentifier)")

		socket = ConnectionSocketNWF(with: config, on: queue)

		super.init()

		socket.delegate = self
	}

	// MARK: - Open/Close

	@objc
	final func open() {
		queue.async {
			self.openOnQueue()
		}
	}

	fileprivate func openOnQueue() {
		RCMLog.connection.debug("Opening connection \(self.socket.uniqueIdentifier, privacy: .public)...")

		if socket.disconnected == false {
			RCMLog.connection.error("Already connected")

			return
		}

		startFloodControlTimer()

		socket.open()
	}

	@objc
	final func close() {
		queue.async {
			self.closeOnQueue()
		}
	}

	fileprivate func closeOnQueue() {
		RCMLog.connection.debug("Closing connection \(self.socket.uniqueIdentifier, privacy: .public)...")

		if socket.disconnected {
			RCMLog.connection.debug("Not connected")

			return
		}

		resetState()

		socket.close()
	}

	/// Invoked when closing and again when the socket reports it
	/// disconnected. Both paths are idempotent so doing the work
	/// twice is harmless and keeps the state machine simple.
	fileprivate func resetState() {
		floodControlEnforced = false

		floodControlCurrentMessageCount = 0

		sendQueue.removeAll()

		stopFloodControlTimer()
	}

	// MARK: - Send Queue

	@objc
	final func clearSendQueue() {
		queue.async {
			self.sendQueue.removeAll()
		}
	}

	@discardableResult
	fileprivate func tryToSend() -> Bool {
		if socket.sending {
			return false
		}

		if sendQueue.isEmpty {
			return false
		}

		if floodControlEnforced {
			if floodControlCurrentMessageCount >= config.floodControlMaximumMessages {
				return false
			}
		}

		floodControlCurrentMessageCount += 1

		let line = sendQueue.removeFirst()

		socket.write(line)

		return true
	}

	@objc(sendData:bypassQueue:)
	final func send(_ data: Data, bypassQueue: Bool = false) {
		queue.async {
			self.sendOnQueue(data, bypassQueue: bypassQueue)
		}
	}

	fileprivate func sendOnQueue(_ data: Data, bypassQueue: Bool) {
		if socket.disconnected {
			RCMLog.connection.error("Cannot send data while disconnected")

			return
		}

		if bypassQueue {
			/* A bypass write that collides with an in-flight write would
			 be dropped by the socket. Put it at the front of the queue so
			 it is the very next thing sent instead. */
			if socket.sending {
				sendQueue.insert(data, at: 0)
			} else {
				socket.write(data)
			}

			return
		}

		sendQueue.append(data)

		tryToSend()
	}

	// MARK: - Flood Control

	@objc
	final func enforceFloodControl() {
		queue.async {
			self.floodControlEnforced = true
		}
	}

	fileprivate func startFloodControlTimer() {
		if floodControlTimer.timerIsActive {
			return
		}

		let timerInterval = Double(config.floodControlDelayInterval)

		floodControlTimer.start(timerInterval, onRepeat: true)
	}

	fileprivate func stopFloodControlTimer() {
		if floodControlTimer.timerIsActive == false {
			return
		}

		floodControlTimer.stop()
	}

	fileprivate func onFloodControlTimer() {
		floodControlCurrentMessageCount = 0

		while tryToSend() {

		}
	}

	// MARK: - Socket Proxy

	@objc(exportSecureConnectionInformation:error:)
	final func exportSecureConnectionInformation(to receiver: RCMSecureConnectionInformationCompletionBlock) throws {
		/* The receiver block does not escape (NS_NOESCAPE) so the
		 XPC reply must be produced before this method returns. */
		try queue.sync {
			try socket.exportSecureConnectionInformation(to: receiver)
		}
	}

	// MARK: - Socket Delegate

	/// A proxy whose failures are logged. Messages sent through it
	/// are one way; nothing here waits on the client.
	fileprivate var remoteObjectProxy: RCMConnectionManagerClientProtocol? {
		let proxy = serviceConnection.remoteObjectProxyWithErrorHandler { (error) in
			RCMLog.connection.error("Error communicating with client: \(error.localizedDescription, privacy: .public)")
		}

		guard let proxy = proxy as? RCMConnectionManagerClientProtocol else {
			RCMLog.connection.error("Remote object proxy does not conform to client protocol")

			return nil
		}

		return proxy
	}

	final func connection(_ connection: ConnectionSocket, willConnectToProxy address: String, on port: UInt16) {
		remoteObjectProxy?.ircConnectionWillConnect(toProxy: address, port: port)
	}

	final func connection(_ connection: ConnectionSocket, willConnectTo address: String, on port: UInt16) {

	}

	final func connection(_ connection: ConnectionSocket, didConnectTo address: String?) {
		remoteObjectProxy?.ircConnectionDidConnect(toHost: address)
	}

	final func connection(
		_ connection: ConnectionSocket, securedWith protocol: tls_protocol_version_t, cipherSuite: tls_ciphersuite_t
	) {
		remoteObjectProxy?.ircConnectionDidSecureConnection(withProtocolType: `protocol`, cipherSuite: cipherSuite)
	}

	final func connection(_ connection: ConnectionSocket, requiresTrust response: @escaping (Bool) -> Void) {
		/* If the client cannot be reached, answer "not trusted" so the
		 handshake completes (with failure) instead of hanging forever. */
		let proxy = serviceConnection.remoteObjectProxyWithErrorHandler { (error) in
			RCMLog.connection.error("Trust request failed: \(error.localizedDescription, privacy: .public)")

			response(false)
		}

		guard let proxy = proxy as? RCMConnectionManagerClientProtocol else {
			response(false)

			return
		}

		proxy.ircConnectionRequestInsecureCertificateTrust(response)
	}

	final func connectionClosedReadStream(_ connection: ConnectionSocket) {
		remoteObjectProxy?.ircConnectionDidCloseReadStream()
	}

	final func connectionDisconnected(_ connection: ConnectionSocket) {
		resetState()

		remoteObjectProxy?.ircConnectionDidDisconnectWithError(nil)
	}

	final func connection(_ connection: ConnectionSocket, disconnectedWith error: ConnectionError) {
		resetState()

		remoteObjectProxy?.ircConnectionDidDisconnectWithError(error as NSError)
	}

	final func connection(_ connection: ConnectionSocket, received data: Data) {
		remoteObjectProxy?.ircConnectionDidReceive(data)
	}

	final func connection(_ connection: ConnectionSocket, willSend data: Data) {
		remoteObjectProxy?.ircConnectionWillSend(data)
	}

	final func connectionDidSend(_ connection: ConnectionSocket) {
		remoteObjectProxy?.ircConnectionDidSendData()

		tryToSend()
	}
}

// MARK: - Extensions

typealias ConnectionError = Connection.ConnectionError

extension ConnectionError: CustomNSError {
	/* Error domain and codes are defined in IRCConnectionErrors.h/m */
	static let errorDomain = ConnectionErrorDomain

	var errorCode: Int {
		let errorCode: ConnectionErrorCode

		switch self {
		case .socket(_):
			errorCode = .socket
		case .other(_):
			errorCode = .other
		case .badCertificate(_):
			errorCode = .badCertificate
		case .unableToSecure(_):
			errorCode = .unableToSecure
		}

		return Int(errorCode.rawValue)
	}

	var errorUserInfo: [String: Any] {
		var userInfo: [String: Any] = [:]

		if let errorDescription = errorDescription {
			userInfo[NSLocalizedDescriptionKey] = errorDescription
		}

		// While we don't make use of it right now, pass the original
		// error inside the user info dictionary because at a later
		// time, we may be interested in its contents. Only the
		// domain, code, and description are kept so that the error
		// is guaranteed to survive secure coding across XPC.
		if case .socket(let error) = self {
			let nsError = error as NSError

			userInfo["UnderlyingSocketError"] = NSError(
				domain: nsError.domain,
				code: nsError.code,
				userInfo: [NSLocalizedDescriptionKey: nsError.localizedDescription])
		}

		return userInfo
	}
}

extension ConnectionError: LocalizedError {
	var errorDescription: String? {
		switch self {
		case .socket(let error):
			/* The underlying socket error is almost always an NSError
			 which means we can just ask for its localized description. */
			return error.localizedDescription
		case .other(let message),
			.badCertificate(let message),
			.unableToSecure(let message):
			return message
		}
	}
}
