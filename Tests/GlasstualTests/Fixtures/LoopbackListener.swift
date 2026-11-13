// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
import Network
import Synchronization

/// How long a loopback test waits for something the network owes it. One
/// number for every suite, so a slow runner times out in all of them or none.
nonisolated enum LoopbackTimeouts {
	static let standard = Duration.seconds(30)
}

nonisolated enum LoopbackError: Error, CustomStringConvertible {
	case listenerNeverBecameReady(NWListener.State?)
	case timedOut(String)

	var description: String {
		switch self {
		case let .listenerNeverBecameReady(state):
			"The loopback listener never became ready (last state: \(state.map { "\($0)" } ?? "none"))"
		case let .timedOut(waitingFor):
			"Timed out waiting for \(waitingFor)"
		}
	}
}

/** An `NWListener` on an ephemeral loopback port, ready when `start` returns.

 The callers differ only in the `NWParameters` they pass, TLS or plain TCP,
 and in what they do with each connection. Readiness comes from the state
 handler rather than from polling `listener.state`. */
final nonisolated class LoopbackListener: Sendable { // nonisolated: immutable
	let port: UInt16
	private let listener: NWListener

	private init(listener: NWListener, port: UInt16) {
		self.listener = listener
		self.port = port
	}

	/// `onConnection` runs on a Network.framework queue, before the connection's handshake.
	static func start(
		using parameters: NWParameters,
		timeout: Duration = LoopbackTimeouts.standard,
		onConnection: @escaping @Sendable (NWConnection) -> Void
	) async throws -> LoopbackListener {
		let listener = try NWListener(using: parameters)
		let (states, continuation) = AsyncStream<NWListener.State>.makeStream()
		listener.stateUpdateHandler = { continuation.yield($0) }
		listener.newConnectionHandler = onConnection
		listener.start(queue: .global())

		let deadline = Task {
			try? await Task.sleep(for: timeout, clock: .continuous)
			continuation.finish()
		}
		defer { deadline.cancel() }

		var lastState: NWListener.State?
		for await state in states {
			lastState = state
			switch state {
			case .ready:
				if let port = listener.port?.rawValue {
					listener.stateUpdateHandler = nil
					return LoopbackListener(listener: listener, port: port)
				}
			case .failed, .cancelled:
				listener.cancel()
				throw LoopbackError.listenerNeverBecameReady(state)
			case .setup, .waiting:
				break
			@unknown default:
				break
			}
		}

		listener.cancel()
		throw LoopbackError.listenerNeverBecameReady(lastState)
	}

	func stop() {
		listener.cancel()
	}
}

/** Wakes the tasks waiting on state that a network callback changes.

 The owner of the state calls ``signal()`` after every change, and a waiter
 re-reads the state each time it is woken, so nothing polls and nothing sleeps.
 A waiter subscribes before it first reads, so a change that lands between the
 read and the wait is not lost. */
final nonisolated class ArrivalGate: Sendable { // nonisolated: immutable
	private let subscribers = Mutex<[UUID: AsyncStream<Void>.Continuation]>([:])

	func signal() {
		subscribers.withLock { subscribers in
			for continuation in subscribers.values {
				continuation.yield()
			}
		}
	}

	/// Returns what `check` finds as soon as it finds something, reading the state
	/// now and again after every ``signal()``. Throws once `timeout` has passed.
	func wait<Value>(
		for description: @autoclosure () -> String,
		timeout: Duration = LoopbackTimeouts.standard,
		isolation _: isolated (any Actor)? = #isolation,
		until check: () -> Value?
	) async throws -> Value {
		let (changes, continuation) = AsyncStream<Void>.makeStream()
		let identifier = UUID()
		subscribers.withLock { $0[identifier] = continuation }
		defer {
			subscribers.withLock { $0[identifier] = nil }
			continuation.finish()
		}

		let deadline = Task {
			try? await Task.sleep(for: timeout, clock: .continuous)
			continuation.finish()
		}
		defer { deadline.cancel() }

		if let value = check() {
			return value
		}
		for await _ in changes {
			if let value = check() {
				return value
			}
		}
		throw LoopbackError.timedOut(description())
	}
}
