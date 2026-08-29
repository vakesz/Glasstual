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

import Darwin
import Foundation
import Network
import os

/** Every member here is a pure function of `Sendable` arguments: Network's own
 types are `Sendable`, and the callbacks these install only resume a
 continuation or yield into an `AsyncStream`. None of them read or write actor
 state, which is why they can be `nonisolated` and why the actor can call them
 without handing any of its own state across. */
extension DCCTransfer {
	// MARK: - Starting

	/// Starts `connection` and returns once it is ready to carry bytes.
	nonisolated static func start(_ connection: NWConnection) async throws { // nonisolated: pure
		let states = AsyncStream<NWConnection.State> { continuation in
			connection.stateUpdateHandler = { state in
				continuation.yield(state)

				switch state {
				case .cancelled, .failed:
					continuation.finish()
				default:
					break
				}
			}
		}

		connection.start(queue: callbackQueue)

		defer { connection.stateUpdateHandler = nil }

		for await state in states {
			switch state {
			case .ready:
				return
			case let .failed(error):
				throw DCCTransferError.network(error.localizedDescription)
			case let .waiting(error):
				logger.debug("DCC connection is waiting: \(error.localizedDescription, privacy: .public)")
			case .cancelled:
				throw DCCTransferError.closedByPeer
			case .setup, .preparing:
				break
			@unknown default:
				break
			}
		}

		throw DCCTransferError.closedByPeer
	}

	/// Starts `listener` and returns the port it bound.
	nonisolated static func start(_ listener: NWListener) async throws -> UInt16 { // nonisolated: pure
		let states = AsyncStream<NWListener.State> { continuation in
			listener.stateUpdateHandler = { state in
				continuation.yield(state)

				switch state {
				case .cancelled, .failed:
					continuation.finish()
				default:
					break
				}
			}
		}

		listener.start(queue: callbackQueue)

		defer { listener.stateUpdateHandler = nil }

		for await state in states {
			switch state {
			case .ready:
				guard let port = listener.port?.rawValue else {
					throw DCCTransferError.noOpenPort
				}

				return port
			case let .failed(error):
				throw DCCTransferError.network(error.localizedDescription)
			case .cancelled:
				throw DCCTransferError.noOpenPort
			case .setup, .waiting:
				break
			@unknown default:
				break
			}
		}

		throw DCCTransferError.noOpenPort
	}

	// MARK: - Reading and writing

	nonisolated static func send(_ data: Data, over connection: NWConnection) async throws { // nonisolated: pure
		try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
			connection.send(content: data, completion: .contentProcessed { error in
				if let error {
					continuation.resume(throwing: DCCTransferError.network(error.localizedDescription))
				} else {
					continuation.resume()
				}
			})
		}
	}

	/// Reads whatever the peer has sent, and reports whether the peer is done.
	nonisolated static func receive(on connection: NWConnection) async throws -> (Data?, Bool) { // nonisolated: pure
		try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(Data?, Bool), Error>) in
			connection.receive(
				minimumIncompleteLength: 1,
				maximumLength: bufferSize
			) { content, _, isComplete, error in
				if let error {
					continuation.resume(throwing: DCCTransferError.network(error.localizedDescription))
				} else {
					continuation.resume(returning: (content, isComplete))
				}
			}
		}
	}

	/// Reads and discards whatever the peer sends until it closes.
	///
	/// The sender uses this for the receiver's acknowledgements: it has no use
	/// for their contents, but leaving them unread would eventually fill the
	/// receive buffer and stall the peer, and the close they end with is the
	/// sender's proof that the whole file landed.
	nonisolated static func drainUntilPeerCloses(_ connection: NWConnection) async { // nonisolated: pure
		await withTaskCancellationHandler {
			while Task.isCancelled == false {
				do {
					let (_, isComplete) = try await receive(on: connection)

					if isComplete {
						return
					}
				} catch {
					/* A peer that resets instead of closing has still stopped
					 talking, which is all this needs to know. */
					return
				}
			}
		} onCancel: {
			/* Nothing else would resume the pending receive. */
			connection.cancel()
		}
	}

	/// Runs `operation`, failing with `error` if it outlasts `duration`.
	nonisolated static func withTimeout( // nonisolated: pure
		_ duration: Duration?,
		failingWith error: DCCTransferError,
		operation: @escaping @Sendable () async throws -> Void
	) async throws { // nonisolated: pure
		guard let duration else {
			try await operation()

			return
		}

		try await withThrowingTaskGroup(of: Void.self) { group in
			group.addTask { try await operation() }
			group.addTask {
				try await Task.sleep(for: duration)

				throw error
			}

			_ = try await group.next()
			group.cancelAll()
		}
	}

	// MARK: - Addresses

	nonisolated static func parameters( // nonisolated: pure
		interfaceName: String?,
		connectTimeout: Duration?
	) -> NWParameters {
		let parameters = NWParameters.tcp

		if let connectTimeout,
		   let options = parameters.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options
		{
			options.connectionTimeout = Int(connectTimeout.components.seconds)
		}

		guard let interfaceName, interfaceName.isEmpty == false else {
			return parameters
		}

		if let localAddress = address(ofInterfaceNamed: interfaceName) {
			parameters.requiredLocalEndpoint = .hostPort(host: NWEndpoint.Host(localAddress), port: .any)
		} else {
			logger.error(
				"Interface '\(interfaceName, privacy: .public)' has no usable address. Using the default interface."
			)
		}

		return parameters
	}

	/// Whether an inbound connection came from the peer the transfer was
	/// negotiated with.
	///
	/// Only a reverse DCC gives us the peer's address up front: for a plain
	/// `DCC SEND` we listen and the remote end announces itself by connecting,
	/// so there is nothing to compare against and the connection is allowed.
	nonisolated static func connection( // nonisolated: pure
		_ connection: NWConnection,
		isFrom expectedPeerAddress: String
	) -> Bool {
		guard expectedPeerAddress.isEmpty == false else {
			return true
		}

		guard let peerAddress = host(of: connection.endpoint) else {
			return false
		}

		return peerAddress == expectedPeerAddress
	}

	nonisolated static func host(of endpoint: NWEndpoint) -> String? { // nonisolated: pure
		guard case let .hostPort(host, _) = endpoint else {
			return nil
		}

		switch host {
		case let .ipv4(address):
			return normalized(address.debugDescription)
		case let .ipv6(address):
			return normalized(address.debugDescription)
		case let .name(name, _):
			return name
		@unknown default:
			return nil
		}
	}

	nonisolated static func normalized(_ address: String) -> String { // nonisolated: pure
		/* `IPv6Address` renders an interface zone as a `%en0` suffix, and a
		 dual-stack listener reports IPv4 peers in the `::ffff:` mapped form. */
		var address = address

		if let zone = address.firstIndex(of: "%") {
			address = String(address[address.startIndex ..< zone])
		}

		let mappedPrefix = "::ffff:"

		if address.lowercased().hasPrefix(mappedPrefix) {
			address = String(address.dropFirst(mappedPrefix.count))
		}

		return address
	}

	/// The address the given interface is reachable at, preferring IPv4 and
	/// skipping link-local IPv6.
	nonisolated static func address(ofInterfaceNamed interfaceName: String) -> String? { // nonisolated: pure
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

			guard let hostAddress = address(of: interface, named: interfaceName) else {
				continue
			}

			if hostAddress.isIPv4, ipv4Address == nil {
				ipv4Address = hostAddress.address
			} else if hostAddress.isIPv4 == false,
			          ipv6Address == nil,
			          hostAddress.address.lowercased().hasPrefix("fe80:") == false
			{
				ipv6Address = hostAddress.address
			}
		}

		return ipv4Address ?? ipv6Address
	}

	private nonisolated static func address( // nonisolated: pure
		of interface: UnsafeMutablePointer<ifaddrs>,
		named interfaceName: String
	) -> (address: String, isIPv4: Bool)? {
		guard let address = interface.pointee.ifa_addr,
		      interface.pointee.ifa_flags & UInt32(IFF_UP) != 0,
		      String(cString: interface.pointee.ifa_name) == interfaceName
		else {
			return nil
		}

		let family = Int32(address.pointee.sa_family)

		guard family == AF_INET || family == AF_INET6 else {
			return nil
		}

		var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
		let addressLength = socklen_t(
			family == AF_INET ? MemoryLayout<sockaddr_in>.size : MemoryLayout<sockaddr_in6>.size
		)

		guard getnameinfo(address, addressLength, &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else {
			return nil
		}

		let hostBytes = host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }

		guard let hostAddress = String(bytes: hostBytes, encoding: .utf8) else {
			return nil
		}

		return (hostAddress, family == AF_INET)
	}
}
