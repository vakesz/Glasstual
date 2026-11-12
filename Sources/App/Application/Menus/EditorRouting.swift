// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/// An editor a menu command opens, with what it opens on.
nonisolated enum EditorRequest: Equatable, Sendable {
	case newServer
	case serverProperties
	case addChannel
	case channelProperties(channel: String)
	case topic(channel: String, current: String)
	case modes(channel: String)
	case invite(nicknames: [String])
	case nickname(current: String)
	case nicknameColor(nickname: String)
	case ignore(mask: String?)
	case virtualHost(nickname: String)
	case redact(messageID: String)
	case saslSignIn
	case registerAccount
}

/// How an editor opens.
nonisolated enum EditorRoute: Equatable, Sendable {
	/// As its sheet.
	case sheet
	/// As a command in the message field, with `selection` selected, or the
	/// caret at the end when there is none.
	case prefill(command: String, selection: NSRange?)
}

/** Whether an editor opens as its sheet or as a command in the message field.

 Dialogs open the sheet. The conversation puts the command that does the same
 thing in the message field, filled in as far as the menu knows, with the part
 the reader is most likely to change selected; Return runs it. A command that
 asks for a secret, such as `/register`, asks for it in a secure field rather
 than on the command line. */
nonisolated enum EditorRouting {
	static func route(_ request: EditorRequest, style: InteractionStyle) -> EditorRoute {
		guard style == .conversation else { return .sheet }
		switch request {
		case .newServer:
			return .prefill(command: "/server ", selection: nil)
		case .serverProperties:
			return .prefill(command: "/serverconfig ", selection: nil)
		case .addChannel:
			return prefillSelectingTail("/join ", tail: "#")
		case let .channelProperties(channel):
			return .prefill(command: "/channelconfig \(channel) ", selection: nil)
		case let .topic(channel, current):
			return prefillSelectingTail("/topic \(channel) ", tail: current)
		case let .modes(channel):
			return .prefill(command: "/mode \(channel) ", selection: nil)
		case let .invite(nicknames):
			return .prefill(command: "/invite \(nicknames.joined(separator: " ")) #", selection: nil)
		case let .nickname(current):
			return prefillSelectingTail("/nick ", tail: current)
		case let .nicknameColor(nickname):
			return .prefill(command: "/setcolor \(nickname) ", selection: nil)
		case let .ignore(mask):
			return .prefill(command: "/ignore " + (mask.map { "\($0) " } ?? ""), selection: nil)
		case let .virtualHost(nickname):
			return .prefill(command: "/" + MemberModerationCommand.setVhost("", nickname: nickname), selection: nil)
		case let .redact(messageID):
			return .prefill(command: "/redact \(messageID) ", selection: nil)
		case .saslSignIn:
			return .prefill(command: "/sasl auth", selection: nil)
		case .registerAccount:
			return .prefill(command: "/register ", selection: nil)
		}
	}

	/// The command with `tail` after it, and `tail` selected so typing replaces it.
	private static func prefillSelectingTail(_ head: String, tail: String) -> EditorRoute {
		.prefill(
			command: head + tail,
			selection: NSRange(location: (head as NSString).length, length: (tail as NSString).length)
		)
	}
}
