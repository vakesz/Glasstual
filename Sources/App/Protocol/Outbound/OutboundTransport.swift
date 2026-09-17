// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
import os

private let outboundTransportLogger = Logger(
	subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
	category: "IRCOutboundTransport"
)

extension Client {
	func send(_ command: String, arguments: [String]) {
		sendCommand(command, arguments: arguments, tags: nil)
	}

	/// Sends `command` with whichever of `tags` the server takes: none without
	/// `message-tags`, and no client-only tag its `CLIENTTAGDENY` refuses.
	func sendCommand(_ command: String, arguments: [String], tags: [String: String]?) {
		let negotiatedTags = isCapabilityEnabled(.messageTags) ? tags?.filter { isClientTagPermitted($0.key) } : nil
		do {
			let line = try SendingMessage.string(command: command, arguments: arguments, tags: negotiatedTags)
			sendLine(line)
		} catch {
			/* The arguments came from somewhere a user can type into, and the
			 line they make is not the command they meant. Nothing goes out. */
			outboundTransportLogger.error("Refused to send \(command, privacy: .public): \(String(describing: error), privacy: .public)")
			printDebugInformation(toConsole: String(localized: .IRC.oneOrMoreArgumentsAreNot))
		}
	}

	/** Sends a `TAGMSG` carrying `tags`, or nothing.

	 A `TAGMSG` has no body, so its tags are its whole meaning and they stand or
	 fall together: a reaction stripped of its `+draft/react` is a bare reply
	 marker. Where `CLIENTTAGDENY` refuses any of them the message is not sent at
	 all, rather than spending a line the server drops or relays half of. */
	@discardableResult
	func sendTagMessage(_ tags: [String: String], toTarget target: String) -> Bool {
		guard isCapabilityEnabled(.messageTags), tags.isEmpty == false, target.isEmpty == false,
		      tags.keys.allSatisfy(isClientTagPermitted)
		else {
			return false
		}

		sendCommand("TAGMSG", arguments: [target], tags: tags)
		return true
	}

	/// Whether the server relays the tag `name`, written as it goes on the wire.
	/// Only a client-only tag — one spelled with a leading `+` — is subject to
	/// `CLIENTTAGDENY`, which names them without it.
	func isClientTagPermitted(_ name: String) -> Bool {
		guard name.hasPrefix("+") else {
			return true
		}

		return supportInfo.isClientTagDenied(String(name.dropFirst())) == false
	}
}
