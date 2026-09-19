// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

/** Where registration is in working through the alternate nicknames.

 A server that refuses a nickname is answered with the next candidate, so the
 session has to remember which one it is on and what it last sent: the refusal
 names the nickname the server saw, not the one the user configured. */
struct NicknameRetry {
	/// How many alternates have been tried, zero before the first refusal.
	var attempt: UInt = 0
	/// The nickname the last `NICK` sent, which is what a refusal is about.
	var sentNickname: String?
}

enum NicknameRetryPolicy {
	static let fallbackNickname = "0"

	/** How many nicknames the session tries before it stops asking.

	 Ten is a full alternate list and several rounds of padding behind it, which
	 is more than a server refusing one name in use needs. What it stops is the
	 server that refuses every name — a `NICKLEN` the session cannot satisfy, a
	 ban on the whole family of names, or services holding them — where each
	 432/433 produced another NICK and the exchange only ended when one side gave
	 up on the connection. */
	static let maximumAttempts: UInt = 10

	static func alternate(at attempt: UInt, from nicknames: [String]) -> String? {
		guard attempt < nicknames.count else { return nil }
		return nicknames[Int(attempt)]
	}

	static func padded(_ nickname: String?, maximumLength: UInt) -> String {
		guard let nickname,
		      let padded = nickname.padNickname(
		      	withCharacter: 95,
		      	maximumLength: maximumLength
		      )
		else { return fallbackNickname }
		return padded
	}
}

@MainActor
extension ServerSession {
	func resetCapabilityNegotiation() {
		capabilityNegotiation.reset()
		sasl.mechanism = nil
		sasl.offeredMechanisms = nil
		sasl.scramSession = nil
		sasl.incomingPayload = nil
		sasl.triedMechanisms.removeAll()
		failPendingDeliveriesForDisconnect()
		NotificationCenter.default.post(name: .sessionCapabilitiesDidChange, object: self)
	}

	func receivePing(_ message: Message) {
		guard !message.params.isEmpty else { return }
		sendPong(message.sequence(0))
		_ = shouldPrintReceivedMessage(message)
	}

	func receiveAwayNotifyCapability(_ message: Message) {
		guard isCapabilityEnabled(.awayNotify), let nickname = message.senderNickname else { return }
		modifyUser(withNickname: nickname, asAway: !message.sequence.isEmpty)
	}

	func receiveInit(_ message: Message) {
		guard !isLoggedIn, !isTerminating, !isQuitting, !isDisconnecting,
		      let nickname = message.params.first else { return }
		startPongTimer()
		stopRetryTimer()
		isLoggedIn = true
		socket?.config.diagnostics?.record(.registered)
		supportInfo.serverAddress = message.senderHostmask
		invokingISONCommandForFirstTime = true
		reconnect.isEnabledForSleepMode = false
		nicknameRetry.sentNickname = nil
		userNickname = nickname
		successfulConnects += 1
		socket?.enforceFloodControl()

		beginConnectCommands()

		if isCapabilityEnabled(.zncCertInfoModule) {
			sendCommand(
				ServerQuirks.ZNC.sendCertificateChainCommand,
				toZNCModuleNamed: ServerQuirks.ZNC.certificateInfoModule
			)
		}
		requestPlayback()

		let output = output
		/* Presumed present until a MONITOR reply or the ISON poll says otherwise;
		 activating now is what asks the server for each direct conversation's
		 history. */
		for directConversation in conversationList where directConversation.isDirect {
			applyPresence(true, to: directConversation)
		}
		output?.reloadChatItem(self)
		output?.updateTitle(for: self)

		performAutoJoin()

		trackedUserPopulationTask?.cancel()
		trackedUserPopulationTask = Task { [weak self] in
			try? await Task.sleep(for: .seconds(10))

			guard Task.isCancelled == false, let self else { return }

			populateISONTrackedUsersList()
		}
	}

	func receiveNicknameCollisionError(_: Message) {
		guard isConnected, !isLoggedIn else { return }
		printDebugInformation(
			toConsole: String(localized: .IRC.cannotUseNicknameTryingAnother(nicknameRetry.sentNickname ?? ""))
		)

		/* Past the ceiling the session says so once and waits: the count is reset
		 when the user's own /nick lands, so asking again is what starts it over. */
		guard nicknameRetry.attempt < NicknameRetryPolicy.maximumAttempts else {
			if nicknameRetry.attempt == NicknameRetryPolicy.maximumAttempts {
				nicknameRetry.attempt += 1
				printDebugInformation(toConsole: String(localized: .IRC.nicknameRetriesExhausted))
			}

			return
		}

		if let nickname = NicknameRetryPolicy.alternate(
			at: nicknameRetry.attempt,
			from: config.alternateNicknames
		) {
			nicknameRetry.sentNickname = nickname
			changeNickname(nickname)
		} else {
			tryAnotherNickname()
		}
		nicknameRetry.attempt += 1
	}

	/** The length to pad a retried nickname to.

	 A hardcoded 31 used to stand here, so on a network advertising a shorter
	 `NICKLEN` the server answered 432 again and the retry ran over the wire
	 until `padNickname` had nothing left to pad. */
	private var nicknameRetryMaximumLength: UInt {
		guard supportInfo.configurationReceived, supportInfo.maximumNicknameLength > 0 else {
			return UInt(ProtocolLimits.defaultNicknameMaximumLength)
		}

		return supportInfo.maximumNicknameLength
	}

	func tryAnotherNickname() {
		guard isConnected, !isLoggedIn else { return }
		let nickname = NicknameRetryPolicy.padded(
			nicknameRetry.sentNickname,
			maximumLength: nicknameRetryMaximumLength
		)
		nicknameRetry.sentNickname = nickname
		changeNickname(nickname)
	}
}
