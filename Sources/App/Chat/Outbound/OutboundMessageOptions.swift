// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

/** One outbound text send, decided once.

 The three commands that carry a person's text are `PRIVMSG`, a `PRIVMSG`
 whose body is an `ACTION`, and `NOTICE`; a failed initializer is how "that is
 not a text command" is said. Everything else the send path needs — the wire
 name, the line type it prints as, and the two things the `/o…` and `/s…`
 spellings change — is read off the one remote command, so the value cannot
 disagree with itself. */
struct OutboundMessageOptions {
	let remoteCommand: RemoteCommand
	let isOperatorMessage: Bool
	let isSecretMessage: Bool

	/// How the line prints locally.
	var lineType: ChatLineKind {
		switch remoteCommand {
		case .privmsgAction: .action
		case .notice: .notice
		default: .privateMessage
		}
	}

	init?(remoteCommand: RemoteCommand, isOperatorMessage: Bool = false, isSecretMessage: Bool = false) {
		switch remoteCommand {
		case .privmsg, .privmsgAction, .notice:
			self.remoteCommand = remoteCommand
		default:
			return nil
		}

		self.isOperatorMessage = isOperatorMessage
		self.isSecretMessage = isSecretMessage
	}

	init?(command: LocalCommand?, silentlyConnecting: Bool) {
		switch command {
		case .msg, .omsg, .smsg, .umsg:
			self.init(
				remoteCommand: .privmsg,
				isOperatorMessage: command == .omsg,
				isSecretMessage: command == .smsg || silentlyConnecting
			)
		case .me, .sme, .ume:
			self.init(remoteCommand: .privmsgAction, isSecretMessage: command == .sme)
		case .notice, .onotice, .unotice:
			self.init(remoteCommand: .notice, isOperatorMessage: command == .onotice)
		default:
			return nil
		}
	}
}
