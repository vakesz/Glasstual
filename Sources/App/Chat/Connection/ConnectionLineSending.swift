// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
import os

/// The same category the rest of `Connection` logs under: which of its files a
/// line came from is not something anyone filters on.
private nonisolated let connectionLineLogger = Logger(
	subsystem: LogSubsystem.current,
	category: "Connection"
)

/** The last thing that happens to an outgoing line before the host writes it:
 the terminator is put back on, the assembled line is measured against what the
 server carries, the text is encoded, and the queue it joins is chosen. */
extension Connection {
	func sendLine(_ line: String) {
		let body = line
			.replacingOccurrences(of: "\r", with: "")
			.replacingOccurrences(of: "\n", with: "")
		/* Last stop before the socket: everything upstream budgets its own text,
		 but nothing measured the assembled line, so a long enough command went
		 out over what the protocol carries and the server cut it where it
		 landed — mid-character for anything but ASCII. */
		let bodyLimit = ProtocolLimits.bodyLimit(forAdvertisedLineLength: maximumLineLength)
		let enforcedBody = ProtocolLimits.enforcedWireLine(body, bodyLimit: bodyLimit)

		if enforcedBody != body {
			connectionLineLogger.error(
				"Truncated an outgoing line from \(body.utf8.count, privacy: .public) to \(enforcedBody.utf8.count, privacy: .public) bytes"
			)
			/* The log is not where the user is looking. Text they typed is gone
			 from what the server saw, so the transcript has to say so. */
			session?.printDebugInformation(
				toConsole: ConnectionSafetyStrings.Wire.lineTruncated(
					sentByteCount: body.utf8.count,
					limit: enforcedBody.utf8.count
				)
			)
		}

		let cleanLine = enforcedBody + "\r\n"

		guard let data = convertToCommonEncoding(cleanLine) else { return }

		if Self.bypassesFloodControl(cleanLine) {
			remoteObjectProxy()?.send(data, bypassQueue: true)
		} else {
			remoteObjectProxy()?.send(data)
		}
	}

	/** Whether `line` goes out ahead of the flood-control queue.

	 A PONG answers the server's liveness probe, which a backed-up queue would
	 otherwise make it miss. A QUIT is the last line a closing connection sends:
	 the disconnect that follows it clears the queue, so a QUIT waiting behind
	 flood control was thrown away and the user's quit message never reached
	 anyone. */
	static func bypassesFloodControl(_ line: String) -> Bool {
		line.hasPrefix("PONG") || line.hasPrefix("QUIT")
	}

	func clearSendQueue() {
		remoteObjectProxy()?.clearSendQueue()
	}

	func enforceFloodControl() {
		guard isConnected else { return }
		remoteObjectProxy()?.enforceFloodControl()
	}

	private func convertToCommonEncoding(_ string: String) -> Data? {
		guard let session else { return nil }

		return session.convert(toCommonEncoding: string)
	}
}
