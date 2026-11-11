// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** How the server framed a WebSocket connection's lines, as the upgrade settled it.

 Decides the session's encoding: `text.ircv3.net` frames are UTF-8 by
 definition, and with no subprotocol the host sends every line in a text
 frame, so either way only UTF-8 goes out. */
enum WebSocketFraming: Equatable {
	case negotiated(WebSocketSubprotocol)
	/// The server chose none, which the IRCv3 specification leaves to the
	/// implementation.
	case unnegotiated

	init(subprotocolName: String?) {
		/* The host refuses a subprotocol it did not offer, so a name it reports
		 is one of these; an unknown one is treated as none. */
		if let name = subprotocolName, let subprotocol = WebSocketSubprotocol(rawValue: name) {
			self = .negotiated(subprotocol)
		} else {
			self = .unnegotiated
		}
	}

	/// Whether every line this connection carries must be UTF-8.
	var requiresUTF8: Bool {
		self != .negotiated(.binary)
	}
}

extension ServerSession {
	func connectionDidNegotiateWebSocket(_ framing: WebSocketFraming) {
		switch framing {
		case let .negotiated(subprotocol):
			printDebugInformation(toConsole: String(localized: .IRC.webSocketSubprotocolNegotiated(subprotocol.rawValue)))
		case .unnegotiated:
			printDebugInformation(toConsole: String(localized: .IRC.webSocketNoSubprotocol))
		}
	}
}
