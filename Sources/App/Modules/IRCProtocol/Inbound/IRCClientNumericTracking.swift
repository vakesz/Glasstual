/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_
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

@MainActor
extension IRCClient {
	func handleTrackingNumeric(_ numeric: UInt, message: Message, shouldPrint: Bool) -> Bool {
		if handlePresenceTrackingNumeric(numeric, message: message, shouldPrint: shouldPrint) {
			return true
		}

		return handleAuthenticationTrackingNumeric(numeric, message: message, shouldPrint: shouldPrint)
	}

	private func handlePresenceTrackingNumeric(_ numeric: UInt, message: Message, shouldPrint: Bool) -> Bool {
		switch numeric {
		case IRCNumeric.youreoper.rawValue:
			guard !userIsIRCop else { return true }
			userIsIRCop = true
			if shouldPrint {
				print(
					IRCInboundStrings.Numeric.operatorStatus(networkName: message.senderNickname ?? ""),
					by: nil,
					in: nil,
					as: .debug,
					command: message.command, receivedAt: message.receivedAt
				)
			}
		case IRCNumeric.channelUrl.rawValue:
			guard shouldPrint, message.params.count == 3,
			      let channel = findChannel(message.params[1]) else { return true }
			print(
				IRCInboundStrings.Numeric.website(message.params[2]),
				by: nil,
				in: channel,
				as: .website,
				command: message.command, receivedAt: message.receivedAt
			)
		case IRCNumeric.watchstat.rawValue, IRCNumeric.watchlist.rawValue, IRCNumeric.watchoff.rawValue,
		     IRCNumeric.endofwatchlist.rawValue,
		     IRCNumeric.monlist.rawValue, IRCNumeric.endofmonlist.rawValue:
			if shouldPrint {
				printReplyToHiddenCommandResponsesQuery(message)
			}
		case IRCNumeric.reaway.rawValue, IRCNumeric.goneaway.rawValue, IRCNumeric.notaway.rawValue:
			handleTrackedAwayNumeric(numeric, message: message, shouldPrint: shouldPrint)
		case IRCNumeric.logon.rawValue, IRCNumeric.logoff.rawValue, IRCNumeric.nowon.rawValue,
		     IRCNumeric.nowoff.rawValue:
			handleTrackedStatusNumeric(numeric, message: message, shouldPrint: shouldPrint)
		case IRCNumeric.toomanywatch.rawValue, IRCNumeric.monlistfull.rawValue:
			if shouldPrint {
				printErrorReply(message)
			}
		case IRCNumeric.mononline.rawValue, IRCNumeric.monoffline.rawValue:
			handleMonitorStatusNumeric(numeric, message: message, shouldPrint: shouldPrint)
		case IRCNumeric.targumodeg.rawValue:
			break
		default:
			return false
		}

		return true
	}

	private func handleAuthenticationTrackingNumeric(
		_ numeric: UInt,
		message: Message,
		shouldPrint: Bool
	) -> Bool {
		switch numeric {
		case IRCNumeric.targnotify.rawValue:
			if shouldPrint, message.params.count == 3 {
				printDebugInformation(IRCInboundStrings.Numeric.cannotMessageUnrecognizedUser(message.params[1]))
			}
		case IRCNumeric.umodegmsg.rawValue: handleUserModeMessageNumeric(message, shouldPrint: shouldPrint)
		case IRCNumeric.loggedin.rawValue:
			guard message.params.count == 4 else { return true }
			guard scramMutualAuthenticationIsSatisfied() else {
				abortUnverifiedSASLSuccess()
				return true
			}
			setCapabilityEnabled(.isIdentifiedWithSASL)
			if shouldPrint {
				printNumericSequence(message, startingAt: 3)
			}
		case IRCNumeric.loggedout.rawValue:
			guard message.params.count == 3 else { return true }
			resetSASLNegotiation()
			if shouldPrint {
				printNumericSequence(message, startingAt: 2)
			}
		case IRCNumeric.saslmechs.rawValue: handleSASLMechanismsNumeric(message, shouldPrint: shouldPrint)
		case IRCNumeric.saslsuccess.rawValue, IRCNumeric.nicklocked.rawValue, IRCNumeric.saslfail.rawValue,
		     IRCNumeric.sasltoolong.rawValue,
		     IRCNumeric.saslaborted.rawValue, IRCNumeric.saslalready.rawValue:
			handleSASLResultNumeric(numeric, message: message, shouldPrint: shouldPrint)
		default: return false
		}

		return true
	}

	private func handleTrackedAwayNumeric(_ numeric: UInt, message: Message, shouldPrint: Bool) {
		guard message.params.count > 4 else { return }
		if shouldPrint {
			printReplyToHiddenCommandResponsesQuery(message)
		}
		let nickname = message.params[1]
		guard findUserTrackingAddressBookEntry(forNickname: nickname) != nil else { return }
		modifyUser(withNickname: nickname, asAway: numeric != IRCNumeric.notaway.rawValue)
	}

	private func handleTrackedStatusNumeric(_ numeric: UInt, message: Message, shouldPrint: Bool) {
		guard message.params.count > 4 else { return }
		if shouldPrint {
			printReplyToHiddenCommandResponsesQuery(message)
		}
		let nickname = message.params[1]
		guard findUserTrackingAddressBookEntry(forNickname: nickname) != nil else { return }
		let status: IRCAddressBookUserTrackingStatus
		let notify: Bool
		switch numeric {
		case IRCNumeric.logon.rawValue: status = .signedOn; notify = true
		case IRCNumeric.logoff.rawValue: status = .signedOff; notify = true
		case IRCNumeric.nowon.rawValue: status = .available; notify = false
		default: status = .notAvailable; notify = false
		}
		setTrackedNickname(nickname, status: status, notify: notify)
	}

	private func handleMonitorStatusNumeric(_ numeric: UInt, message: Message, shouldPrint: Bool) {
		guard message.params.count == 2 else { return }
		if shouldPrint {
			printReplyToHiddenCommandResponsesQuery(message)
		}
		for changedUser in message.params[1].components(separatedBy: ",") {
			let nickname = (changedUser as NSString).nicknameFromHostmask ?? changedUser
			guard findUserTrackingAddressBookEntry(forNickname: nickname) != nil else { continue }
			setTrackedNickname(
				nickname,
				status: numeric == IRCNumeric.mononline.rawValue ? .signedOn : .signedOff,
				notify: true
			)
		}
	}

	private func handleUserModeMessageNumeric(_ message: Message, shouldPrint: Bool) {
		guard shouldPrint, message.params.count == 4 else { return }
		let text = IRCInboundStrings.Numeric.privateMessageBlocked(
			nickname: message.params[1],
			account: message.params[2]
		)
		if TextualPreferences.locationToSendNotices() == .selectedChannel,
		   let channel = NSObject.applicationController().mainWindow.selectedChannel(on: self)
		{
			printDebugInformation(text, in: channel)
		} else {
			printDebugInformation(toConsole: text)
		}
	}

	private func handleSASLMechanismsNumeric(_ message: Message, shouldPrint: Bool) {
		if shouldPrint {
			printErrorReply(message)
		}
		guard capabilityIsEnabled(.isInSASLNegotiation) else { return }
		let mechanisms = message.params.count >= 2
			? message.params[1].components(separatedBy: CharacterSet(charactersIn: ", ")).filter { !$0.isEmpty }
			: []
		guard !retrySASL(withMechanisms: mechanisms) else { return }
		setCapabilityDisabled(.isInSASLNegotiation)
		resumeQueuedCapabilityNegotiation()
	}

	/// The numerics that mean the server refused this SASL attempt, as opposed
	/// to 903 (success) or 907 (already authenticated).
	private static let saslFailureNumerics: Set<UInt> = [
		IRCNumeric.saslfail.rawValue,
		IRCNumeric.sasltoolong.rawValue,
		IRCNumeric.saslaborted.rawValue,
	]

	private func handleSASLResultNumeric(_ numeric: UInt, message: Message, shouldPrint: Bool) {
		if shouldPrint {
			if numeric == IRCNumeric.saslsuccess.rawValue {
				printReply(message)
			} else {
				printErrorReply(message)
			}
		}
		guard capabilityIsEnabled(.isInSASLNegotiation) else { return }
		if numeric == IRCNumeric.saslsuccess.rawValue, scramMutualAuthenticationIsSatisfied() == false {
			abortUnverifiedSASLSuccess()
			return
		}
		setCapabilityDisabled(.isInSASLNegotiation)
		saslScramClient = nil
		saslIncomingPayload = nil
		if Self.saslFailureNumerics.contains(numeric), config.disconnectOnSASLFailure {
			// Otherwise registration completes unauthenticated, which many
			// networks treat as a security failure.
			printDebugInformation(IRCInboundStrings.Numeric.saslAuthenticationFailedDisconnecting)
			quit()
			return
		}
		resumeQueuedCapabilityNegotiation()
	}

	private func printNumericSequence(_ message: Message, startingAt index: UInt) {
		print(message.sequence(index), by: nil, in: nil, as: .debug, command: message.command,
		      receivedAt: message.receivedAt)
	}
}
