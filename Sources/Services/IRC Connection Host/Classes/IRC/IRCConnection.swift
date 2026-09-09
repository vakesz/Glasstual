/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2018 Codeux Software, LLC & respective contributors.
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

/// One IRC connection, from the service's side.
///
/// The host owns the send queue, the flood-control counters and the transport;
/// the transport hands it everything that happened through one `AsyncStream`,
/// so the ordering the client sees is the ordering the server produced. What
/// used to be a serial `DispatchQueue` shared between two classes and asserted
/// by comment is now the actor's own isolation.
actor ConnectionHost {
	/// The client half of the connection. `RemoteConnectionClientProtocol`
	/// refines `Sendable`, which is what lets the proxy live in here.
	private var client: (any RemoteConnectionClientProtocol)?

	private var socket: ConnectionSocket?
	private var eventTask: Task<Void, Never>?
	private var writerTask: Task<Void, Never>?
	private var ready = false
	private var closing = false

	private var sendQueue: [Data] = []

	/// How many entries at the head of `sendQueue` came from a bypass write.
	/// A bypass line goes in front of the queued traffic but behind the bypass
	/// lines already waiting, so two of them cannot swap places on the wire.
	private var sendQueueBypassCount = 0

	/// Ticks the flood-control window. A `ContinuousClock` task rather than a
	/// timer, so it keeps its cadence across system sleep and cancels cleanly.
	private var floodControlTask: Task<Void, Never>?
	private var floodControlCurrentMessageCount = 0
	private var floodControlEnforced = false
	private var floodControlInterval = Duration.seconds(2)
	private var floodControlMaximumMessages: UInt = 0

	/** `ProcessInfo.disableSuddenTermination()` is a counter. The host process is shared by
	 every connection, so an unbalanced disable would permanently pin the whole service. */
	private var suddenTerminationDisableCount = 0

	// MARK: - Connection Lifecycle

	init(client: any RemoteConnectionClientProtocol) {
		self.client = client
	}

	/// The application owns the connection's lifetime; this runs from its
	/// interruption and invalidation handlers.
	func detach() async {
		ConnectionHostLog.connection.debug("Client connection ended")

		client = nil
		await close()

		balanceSuddenTermination()
	}

	// MARK: - Open/Close

	func open(with config: IRCConnectionConfig) async {
		config.diagnostics?.record(.hostStarted)
		guard socket == nil else {
			ConnectionHostLog.connection.error("Cannot open a connection that is already open")

			return
		}

		guard let client else {
			ConnectionHostLog.connection.error("Cannot open a connection before the client is known")

			return
		}

		let (events, continuation) = AsyncStream<SocketEvent>.makeStream(
			// The reader waits for readDrained after each bounded chunk. Never use
			// a dropping stream policy for IRC data or terminal events.
			bufferingPolicy: .unbounded
		)

		let socket = ConnectionSocket(config: config, client: client, events: continuation)

		self.socket = socket
		closing = false
		floodControlInterval = .seconds(Double(config.floodControlDelayInterval))
		floodControlMaximumMessages = config.floodControlMaximumMessages

		eventTask = Task { [weak self] in
			for await event in events {
				await self?.handle(event, from: socket)
			}
		}

		ConnectionHostLog.connection.debug("Opening connection \(socket.uniqueIdentifier, privacy: .public)...")

		startFloodControlTimer()

		await socket.open()
	}

	func close() async {
		guard let socket else { return }
		closing = true

		ConnectionHostLog.connection.debug("Closing connection \(socket.uniqueIdentifier, privacy: .public)...")

		resetState()

		await socket.close()

		/* The transport is not let go of here. Every path out of its connection
		 task ends in a `.disconnected` event, and that event is what carries
		 the disconnect to the client; dropping the reference first would make
		 `handle(_:from:)` discard it as belonging to a transport nobody owns.
		 `releaseSocket()` runs when the event lands. */
	}

	/// Invoked when closing and again when the transport reports it
	/// disconnected. Both paths are idempotent so doing the work twice is
	/// harmless and keeps the state machine simple.
	private func resetState() {
		ready = false
		writerTask?.cancel()
		writerTask = nil
		floodControlEnforced = false
		floodControlCurrentMessageCount = 0

		clearSendQueue()

		stopFloodControlTimer()
	}

	/// Lets go of a transport that has finished, so `open(with:)` can build the
	/// next one. The socket, its event stream and everything they hold are
	/// released here rather than when the client happens to invalidate its
	/// connection.
	private func releaseSocket() {
		socket = nil

		eventTask?.cancel()
		eventTask = nil
	}

	// MARK: - Send Queue

	func clearSendQueue() {
		sendQueue.removeAll()

		sendQueueBypassCount = 0
	}

	func send(_ data: Data, bypassQueue: Bool) {
		guard socket != nil, closing == false, client != nil else {
			ConnectionHostLog.connection.error("Cannot send data while disconnected")

			return
		}

		if bypassQueue {
			sendQueue.insert(data, at: sendQueueBypassCount)
			sendQueueBypassCount += 1
		} else {
			sendQueue.append(data)
		}
		startWriterIfNeeded()
	}

	private func startWriterIfNeeded() {
		guard writerTask == nil, ready, closing == false, let socket, sendQueue.isEmpty == false else { return }
		// Only this task waits for network writes. Command and event drains stay live.
		writerTask = Task { [weak self] in
			await self?.drainWrites(to: socket)
		}
	}

	private func drainWrites(to socket: ConnectionSocket) async {
		while Task.isCancelled == false, self.socket === socket, ready, closing == false, sendQueue.isEmpty == false {
			let bypass = sendQueueBypassCount > 0
			if bypass == false, floodControlEnforced,
			   floodControlCurrentMessageCount >= Int(floodControlMaximumMessages)
			{
				break
			}
			let data = sendQueue.removeFirst()
			if bypass {
				sendQueueBypassCount -= 1
			} else {
				floodControlCurrentMessageCount += 1
			}
			guard await socket.write(data) else {
				/* The transport reports `false` only when it did not take the
				 line, so the line is still owed to the server: put it back at
				 the head, in front of the traffic queued behind it, and let
				 the next drain try again. */
				sendQueue.insert(data, at: 0)
				if bypass {
					sendQueueBypassCount += 1
				} else {
					floodControlCurrentMessageCount -= 1
				}
				break
			}
		}
		guard Task.isCancelled == false, self.socket === socket else { return }
		writerTask = nil
	}

	// MARK: - Flood Control

	func enforceFloodControl() {
		guard !floodControlEnforced else { return }
		floodControlCurrentMessageCount = 0
		floodControlEnforced = true
		startWriterIfNeeded()
	}

	private func startFloodControlTimer() {
		guard floodControlTask == nil else { return }

		let interval = floodControlInterval

		floodControlTask = Task { [weak self] in
			while Task.isCancelled == false {
				try? await Task.sleep(for: interval, clock: .continuous)

				guard Task.isCancelled == false, let self else { return }

				await onFloodControlTimer()
			}
		}
	}

	private func stopFloodControlTimer() {
		floodControlTask?.cancel()
		floodControlTask = nil
	}

	private func onFloodControlTimer() {
		floodControlCurrentMessageCount = 0

		startWriterIfNeeded()
	}

	// MARK: - Secure Connection Information

	func secureConnectionInformation() async -> SecureConnectionInformation {
		guard let socket else { return .none }

		return await socket.secureConnectionInformation()
	}

	// MARK: - App Nap and Sudden Termination

	func enableAppNap() {
		UserDefaults.standard.register(defaults: [AppSleepPreference.name: false])
	}

	func disableAppNap() {
		UserDefaults.standard.register(defaults: [AppSleepPreference.name: true])
	}

	func enableSuddenTermination() {
		guard suddenTerminationDisableCount > 0 else { return }

		suddenTerminationDisableCount -= 1

		ProcessInfo.processInfo.enableSuddenTermination()
	}

	func disableSuddenTermination() {
		guard client != nil else { return }
		suddenTerminationDisableCount += 1

		ProcessInfo.processInfo.disableSuddenTermination()
	}

	private func balanceSuddenTermination() {
		while suddenTerminationDisableCount > 0 {
			enableSuddenTermination()
		}
	}

	// MARK: - Transport Events

	private func handle(_ event: SocketEvent, from socket: ConnectionSocket) {
		if case let .readDrained(continuation) = event {
			continuation.finish()
			return
		}
		guard self.socket === socket else { return }
		switch event {
		case let .willConnectToProxy(host, port):
			client?.ircConnectionWillConnect(toProxy: host, port: port)
		case let .connected(host):
			guard closing == false else { return }
			ready = true
			client?.ircConnectionDidConnect(toHost: host)
			startWriterIfNeeded()
		case let .secured(protocolVersion, cipherSuite):
			client?.ircConnectionDidSecureConnection(withProtocolType: protocolVersion, cipherSuite: cipherSuite)
		case let .received(data):
			client?.ircConnectionDidReceive(data)
		case .readDrained:
			break
		case let .willSend(data):
			client?.ircConnectionWillSend(data)
		case .didSend:
			client?.ircConnectionDidSendData()
		case .closedReadStream:
			client?.ircConnectionDidCloseReadStream()
		case let .disconnected(error):
			resetState()

			client?.ircConnectionDidDisconnectWithError(error.map { $0 as NSError })

			releaseSocket()
		}
	}
}
