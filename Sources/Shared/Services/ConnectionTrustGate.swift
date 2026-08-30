/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import Foundation

/** What a connection does with traffic while the user is being asked about a
 certificate the system would not trust on its own.

 The TLS verify block is synchronous and its completion is not `Sendable`, so
 the old design parked the block's thread on a semaphore until the panel was
 answered -- a blocked thread nobody owned, for as long as the user took. The
 handshake completes immediately instead and this gate stands in its place:
 from the moment the question is asked until it is answered, what the peer
 sends is held and what the application writes is held, so neither side learns
 anything about the other.

 A rejection drops everything held, unread; an acceptance releases it in
 arrival order. The gate is a value with no I/O of its own, which is what makes
 that ordering checkable without a server. */
public nonisolated struct ConnectionTrustGate<Event: Sendable>: Sendable { // nonisolated: value
	/// What `resolve(trusted:)` decided.
	public struct Outcome: Sendable {
		/// Events to deliver to the application, in arrival order. Empty on a
		/// rejection: the user said they do not trust the peer, so nothing it
		/// said is passed on.
		public let deliver: [Event]

		/// `true` when the connection should be closed rather than resumed.
		public let closes: Bool
	}

	/// `true` while an answer is outstanding.
	public private(set) var isPending = false

	private var heldEvents: [Event] = []
	private var heldWrites: [Data] = []

	public init() {}

	/** Starts holding traffic.

	 Returns `false` when a question is already outstanding, which is the guard
	 against asking twice for one connection. */
	public mutating func begin() -> Bool {
		guard isPending == false else {
			return false
		}

		isPending = true

		return true
	}

	/// Holds `event` and returns `true`, or returns `false` when the caller
	/// should deliver it now.
	public mutating func hold(_ event: Event) -> Bool {
		guard isPending else {
			return false
		}

		heldEvents.append(event)

		return true
	}

	/// Holds `data` and returns `true`, or returns `false` when the caller
	/// should send it now.
	public mutating func holdWrite(_ data: Data) -> Bool {
		guard isPending else {
			return false
		}

		heldWrites.append(data)

		return true
	}

	/// The next held write, once the gate is open. `nil` while it is closed or
	/// when nothing is left to send.
	public mutating func nextWrite() -> Data? {
		guard isPending == false, heldWrites.isEmpty == false else {
			return nil
		}

		return heldWrites.removeFirst()
	}

	/** The application answered. Opens the gate and says what to deliver.

	 The held writes stay here and come back one at a time through
	 `nextWrite()`, because the connection allows one write in flight and starts
	 the next when the transport reports the previous one sent. */
	public mutating func resolve(trusted: Bool) -> Outcome {
		guard isPending else {
			return Outcome(deliver: [], closes: false)
		}

		isPending = false

		guard trusted else {
			heldEvents.removeAll()
			heldWrites.removeAll()

			return Outcome(deliver: [], closes: true)
		}

		let deliver = heldEvents
		heldEvents.removeAll()

		return Outcome(deliver: deliver, closes: false)
	}
}
