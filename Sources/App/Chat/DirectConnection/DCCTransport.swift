// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Darwin
import Foundation
import Network
import os

/** The transport both DCC features are built on: listening, connecting,
 deadlines and address canonicalisation.

 The helpers return owned Sendable handles. Network operations create their
 resources locally, and each transfer owns the resulting listener lifetime. */
nonisolated enum DCCTransport {
	/// Read buffer, and the ceiling on a single connection receive.
	static let bufferSize = 64 * 1024

	// MARK: - Listening

	/** A bound port, and the arrivals on it.

	 `task` is the listener: it owns the only reference to it, so cancelling the
	 task finishes `connections` and gives the port back. Nothing else can reach
	 the listener, which is why there is only one way to close one. */
	struct ListeningSession: Sendable {
		let port: UInt16
		let connections: AsyncStream<NetworkConnection<TCP>>
		let task: Task<Void, Never>
	}

	/// Starts the first listener in `portRange` that actually reaches the
	/// ready state.
	///
	/// Constructing a `NetworkListener` does not bind its port. The bind happens
	/// in `run`, so returning immediately after construction makes every caller
	/// believe the range's first port is available even when another listener
	/// already owns it. This helper owns that asynchronous startup boundary and
	/// returns only after Network.framework confirms the selected port.
	static func startListener(
		portRange: ClosedRange<UInt16>
	) async throws -> ListeningSession {
		guard portRange.lowerBound > 0 else {
			throw DCCTransferError.noOpenPort
		}

		for port in portRange {
			try Task.checkCancellation()

			guard let networkPort = NWEndpoint.Port(rawValue: port) else {
				continue
			}

			guard let listener = try? NetworkListener<TCP>(
				using: .parameters { TCP() }.localPort(networkPort)
			) else {
				continue
			}

			/* Bounded, but oldest-first: `bufferingNewest(1)` dropped the peer's
			 connection the moment anything else reached the port, which is the
			 one arrival that matters and the one a racing connector displaced. */
			let (connections, connectionContinuation) = AsyncStream<NetworkConnection<TCP>>
				.makeStream(bufferingPolicy: .bufferingOldest(8))
			let (readiness, readinessContinuation) = AsyncStream<Bool>.makeStream()

			listener.onStateUpdate { _, state in
				switch state {
				case .ready:
					readinessContinuation.yield(true)
					readinessContinuation.finish()
				case .waiting, .failed, .cancelled:
					readinessContinuation.yield(false)
					readinessContinuation.finish()
				case .setup:
					break
				@unknown default:
					readinessContinuation.yield(false)
					readinessContinuation.finish()
				}
			}

			let task = Task {
				defer {
					connectionContinuation.finish()
					readinessContinuation.finish()
				}

				do {
					try await listener.run { connection in
						connectionContinuation.yield(connection)
					}
				} catch {
					readinessContinuation.yield(false)
				}
			}

			var isReady = false

			for await result in readiness {
				isReady = result
				break
			}

			guard isReady else {
				task.cancel()
				try Task.checkCancellation()
				continue
			}
			if Task.isCancelled {
				task.cancel()
				throw CancellationError()
			}

			return ListeningSession(
				port: listener.port?.rawValue ?? port,
				connections: connections,
				task: task
			)
		}

		throw DCCTransferError.noOpenPort
	}

	/// Runs `operation`, failing with `error` if it outlasts `duration`.
	static func withTimeout<Value: Sendable>(
		_ duration: Duration?,
		failingWith error: DCCTransferError,
		operation: @escaping @Sendable () async throws -> Value
	) async throws -> Value {
		guard let duration else {
			return try await operation()
		}

		return try await withThrowingTaskGroup(of: Value.self) { group in
			defer { group.cancelAll() }
			group.addTask { try await operation() }
			group.addTask {
				try await Task.sleep(for: duration)

				throw error
			}

			guard let value = try await group.next() else { throw CancellationError() }
			return value
		}
	}

	/// Runs `operation` against a deadline shared with the other steps in the
	/// same window, rather than restarting the clock for each of them.
	static func withDeadline<Value: Sendable>(
		_ deadline: ContinuousClock.Instant?,
		failingWith error: DCCTransferError,
		operation: @escaping @Sendable () async throws -> Value
	) async throws -> Value {
		let remaining = deadline.map { max(.zero, $0 - ContinuousClock.now) }

		return try await withTimeout(remaining, failingWith: error, operation: operation)
	}

	// MARK: - Addresses

	static func parameters(
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
			DirectConnectionLog.transport.error(
				"Interface '\(interfaceName, privacy: .public)' has no usable address. Using the default interface."
			)
		}

		return parameters
	}

	/** Whether an inbound connection came from the peer the transfer was
	 negotiated with.

	 An empty expectation accepts anything, which is what is left whenever the
	 offer named no address — a plain `DCC SEND` names none, and the peer's
	 hostmask is not a substitute for one.

	 Both sides are reduced to address bytes before they are compared. One
	 address has many spellings: `2001:0db8::1` and `2001:db8::1` are the same
	 host, and `Network` renders what it resolved rather than what the offer
	 wrote, so comparing the text refused the very peer the offer named. */
	static func connection(
		_ connection: NetworkConnection<TCP>,
		isFrom expectedPeerAddress: String
	) -> Bool {
		guard expectedPeerAddress.isEmpty == false else {
			return true
		}

		guard let peerAddress = connection.remoteEndpoint.flatMap(host(of:)) else {
			return false
		}

		guard let expectedBytes = DCCWireFormat.addressBytes(of: expectedPeerAddress),
		      let peerBytes = DCCWireFormat.addressBytes(of: peerAddress)
		else {
			/* A resolved name on either side is not an address to canonicalise,
			 so the text is all there is to go on. */
			return peerAddress == expectedPeerAddress
		}

		return peerBytes == expectedBytes
	}

	private static func host(of endpoint: NWEndpoint) -> String? {
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

	private static func normalized(_ address: String) -> String {
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
	static func address(ofInterfaceNamed interfaceName: String) -> String? {
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

	private static func address(
		of interface: UnsafeMutablePointer<ifaddrs>,
		named interfaceName: String
	) -> (address: String, isIPv4: Bool)? {
		/* `ifa_name` is an implicitly unwrapped import of a C pointer the
		 kernel is not obliged to fill in, so it is bound rather than read. */
		guard let address = interface.pointee.ifa_addr,
		      let name = interface.pointee.ifa_name,
		      interface.pointee.ifa_flags & UInt32(IFF_UP) != 0,
		      String(cString: name) == interfaceName
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
