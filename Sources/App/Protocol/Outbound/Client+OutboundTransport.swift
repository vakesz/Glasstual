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
			printDebugInformation(toConsole: CommandStrings.invalidArguments)
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
