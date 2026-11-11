// Copyright (c) 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
import Network

extension ConnectionSocket {
	// MARK: - Read & Write

	func read(from connection: TransportConnection, generation: Int) async throws {
		if case let .webSocket(options) = config.transport {
			try await readWebSocket(from: connection, options: options, generation: generation)

			return
		}

		while connecting || connected, disconnecting == false {
			let message = try await connection.receive(atMost: Self.maximumDataLength)
			try Task.checkCancellation()
			// A completed read also proves readiness if its state callback is still queued.
			onReady(generation: generation)

			let (content, isComplete) = message

			/* The final bytes (typically an ERROR line with the reason for the
			 disconnect) can arrive together with the EOF. */
			let lines = content.isEmpty ? [] : readIn(content)

			if lines.isEmpty == false {
				try await deliver(lines)
			}

			if isComplete {
				if framer.hasPartialLine {
					throw ConnectionError.socket(error: NSError(domain: NSPOSIXErrorDomain, code: Int(EPROTO)))
				}
				events.yield(.closedReadStream)

				return
			}
		}
	}

	/** Hands `lines` to the application and waits until it has handled them.

	 The end-to-end flow control: nothing more is read until the application
	 has handled these lines and said so, so a server that outpaces it fills
	 the TCP window instead of a queue between the processes. Ending the
	 connection cancels this task, which ends the wait too. The wait never
	 occupies the host's command or writer task. */
	func deliver(_ lines: [Data]) async throws {
		let (acknowledgement, acknowledged) = AsyncStream<Void>.makeStream()
		events.yield(.received(lines, acknowledged: acknowledged))
		for await _ in acknowledgement {}
		try Task.checkCancellation()
	}

	/** Cuts `data` into lines and returns the ones it completes, in order.

	 A line too long to buffer closes the connection, and nothing after it on
	 this read is framed. The lines before it are still the server's, and they
	 go out ahead of the disconnect. */
	func readIn(_ data: Data) -> [Data] {
		guard disconnected == false, disconnecting == false else { return [] }

		do {
			return try framer.lines(appending: data)
		} catch {
			fail(with: .other(message: String(localized: .ConnectionErrors.peerLineTooLong)))

			return error.completedLines
		}
	}

	/** Sends `data`, reporting whether it was taken.

	 Only one write is in flight at a time, and this is where that is decided:
	 the claim on `sending` is made without an intervening suspension, so a
	 caller that is told `false` knows the data was not sent and can queue it
	 again. Deciding it anywhere else meant two callers could both pass the
	 check and the loser's line would be dropped with nobody told. */
	func write(_ data: Data) async -> Bool {
		guard connected, disconnecting == false, sending == false, let connection else {
			return false
		}

		sending = true

		await startWriting(data, over: connection)

		return true
	}

	/** Sends one queued write. The application is told about `data` as it
	 queued it, terminator and all, whatever framing carries it. */
	func startWriting(_ data: Data, over connection: TransportConnection) async {
		events.yield(.willSend(data))

		let payload = webSocket.map { WebSocketSession.frames(for: data, framedBy: $0.lines) } ?? data

		do {
			if payload.isEmpty == false {
				try await connection.send(payload)
			}
		} catch {
			sending = false
			fail(with: ConnectionError.translating(error))

			return
		}

		/* Cleared before the disconnect check: returning with it still set left
		 the writer believing a send was in flight, and nothing else clears it. */
		sending = false

		guard disconnecting == false else { return }

		events.yield(.didSend)
	}
}
