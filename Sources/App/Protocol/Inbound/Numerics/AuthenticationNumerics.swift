// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

@MainActor
extension ServerSession {
	func handleAuthenticationTrackingNumeric(_ numeric: ServerNumeric, message: Message, shouldPrint: Bool) {
		switch numeric {
		case .targnotify:
			if shouldPrint, message.params.count == 3 {
				printDebugInformation(String(localized: .IRC.youCannotSendPrivateMessages(message.params[1])))
			}
		case .umodegmsg: handleUserModeMessageNumeric(message, shouldPrint: shouldPrint)
		case .loggedin:
			guard message.params.count == 4, message.senderIsServer,
			      nicknameIsMyself(message.params[0]), message.params[2] != "*",
			      !message.params[2].isEmpty else { return }
			guard scramMutualAuthenticationIsSatisfied() else {
				abortUnverifiedSASLSuccess()
				return
			}
			noteAccountAuthenticated()
			if shouldPrint {
				printNumericSequence(message, startingAt: 3)
			}
		case .loggedout:
			guard message.params.count == 3 else { return }
			resetSASLNegotiation()
			if startup.authentication == .confirmed {
				startup.authentication = .pending
			}
			nickServ.isConfirmed = false
			if shouldPrint {
				printNumericSequence(message, startingAt: 2)
			}
		case .saslmechs: handleSASLMechanismsNumeric(message, shouldPrint: shouldPrint)
		case .saslsuccess, .nicklocked, .saslfail, .sasltoolong, .saslaborted, .saslalready:
			handleSASLResultNumeric(numeric, message: message, shouldPrint: shouldPrint)
		default: break
		}
	}

	private func handleUserModeMessageNumeric(_ message: Message, shouldPrint: Bool) {
		guard shouldPrint, message.params.count == 4 else { return }
		let text = String(localized: .IRC.triedToSendYouAPrivate(message.params[1], message.params[2]))
		if environment.settings.locationToSendNotices == .selectedConversation,
		   let selectedConversation = output?.selectedConversation(on: self)
		{
			printDebugInformation(text, in: selectedConversation)
		} else {
			printDebugInformation(toConsole: text)
		}
	}

	/** `RPL_SASLMECHS`: the mechanisms the server would have taken.

	 The server sends this when it refuses the mechanism the session named, and
	 follows it with `ERR_SASLFAIL`. The failure is what moves the exchange on
	 to the next mechanism; this only narrows what that next one may be. Moving
	 on here as well sent the retry ahead of the 904 that belonged to the
	 refused attempt, and the 904 then ended the retry before it began. */
	private func handleSASLMechanismsNumeric(_ message: Message, shouldPrint: Bool) {
		if shouldPrint {
			printErrorReply(message)
		}
		guard isCapabilityEnabled(.isInSASLNegotiation), message.params.count >= 2 else { return }
		let mechanisms = message.params[1]
			.components(separatedBy: CharacterSet(charactersIn: ", "))
			.filter { !$0.isEmpty }
		guard !mechanisms.isEmpty else { return }
		sasl.offeredMechanisms = mechanisms
	}

	/// The numerics that mean the server refused this SASL attempt, as opposed
	/// to 903 (success) or 907 (already authenticated).
	private static let saslFailureNumerics: Set<ServerNumeric> = [.nicklocked, .saslfail, .sasltoolong, .saslaborted]

	private func handleSASLResultNumeric(_ numeric: ServerNumeric, message: Message, shouldPrint: Bool) {
		if shouldPrint {
			if numeric == .saslsuccess {
				printReply(message)
			} else {
				printErrorReply(message)
			}
		}
		guard isCapabilityEnabled(.isInSASLNegotiation) else { return }
		let failed = Self.saslFailureNumerics.contains(numeric)
		/* 904 is a refused attempt, not a refused login: a certificate the
		 account does not know fails EXTERNAL while the password would still
		 pass SCRAM. The exchange ends only once every mechanism both sides
		 speak has been tried. The other failures are about the account or the
		 exchange itself, and another mechanism would not change them. */
		if numeric == .saslfail, retrySASLNegotiation(withMechanisms: []) {
			return
		}
		if !failed, scramMutualAuthenticationIsSatisfied() == false {
			abortUnverifiedSASLSuccess()
			return
		}
		if !failed {
			enableCapability(.isIdentifiedWithSASL)
			noteAccountAuthenticated()
		}
		finishSASLNegotiation(failed: failed)
	}

	private func printNumericSequence(_ message: Message, startingAt index: UInt) {
		print(message.sequence(index), by: nil, in: nil, as: .debug, command: message.command,
		      receivedAt: message.receivedAt)
	}
}
