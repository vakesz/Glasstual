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

import CocoaExtensions
import Foundation

enum IRCNicknameRetryPolicy {
	static let fallbackNickname = "0"

	static func alternate(at attempt: UInt, from nicknames: [String]) -> String? {
		guard attempt < nicknames.count else { return nil }
		return nicknames[Int(attempt)]
	}

	static func padded(_ nickname: String?, maximumLength: UInt) -> String {
		guard let nickname,
		      let padded = (nickname as NSString).padNickname(
		      	withCharacter: 95,
		      	maximumLength: maximumLength
		      )
		else { return fallbackNickname }
		return padded
	}
}

@MainActor
public extension IRCClient {
	func resetCapabilityNegotiation() {
		capabilities = []
		capabilityNegotiationIsPaused = false
		saslMechanism = nil
		saslOfferedMechanisms = nil
		saslScramClient = nil
		saslIncomingPayload = nil
		saslTriedMechanisms.removeAll()
		pendingDeliveries.removeAll()
		labelForBatchToken.removeAll()
		enabledCapabilityNames.removeAll()
		NotificationCenter.default.post(name: .ircClientCapabilitiesDidChange, object: self)
		offeredCapabilities.removeAll()
		pendingCapabilityRequests.removeAll()
	}

	func receivePing(_ message: Message) {
		guard !message.params.isEmpty else { return }
		sendPong(message.sequence(0))
		_ = postReceivedMessage(message)
	}

	func receiveAwayNotifyCapability(_ message: Message) {
		guard isCapabilityEnabled(.awayNotify), let nickname = message.senderNickname else { return }
		modifyUser(withNickname: nickname, asAway: !message.sequence.isEmpty)
	}

	func receiveInit(_ message: Message) {
		guard let nickname = message.params.first else { return }
		startPongTimer()
		stopRetryTimer()
		isLoggedIn = true
		supportInfo.serverAddress = message.senderHostmask
		invokingISONCommandForFirstTime = true
		reconnectEnabledBecauseOfSleepMode = false
		tryingNicknameSentNickname = nil
		userNickname = nickname
		successfulConnects += 1
		socket?.enforceFloodControl()
		_ = notifyEvent(.connect, lineType: .debug)

		isPerformingConnectCommands = true
		for configuredCommand in config.loginCommands {
			let command = configuredCommand.hasPrefix("/") ? String(configuredCommand.dropFirst()) : configuredCommand
			sendCommand(command, completeTarget: false, target: nil)
		}
		isPerformingConnectCommands = false
		/* The commands are sent inline, so by here they have run — or there were
		 none to run. This releases an autojoin held back by
		 `autojoinWaitsForConnectCommands`; every other wait still applies. */
		markConnectCommandsPerformed()

		if isCapabilityEnabled(.zncCertInfoModule) {
			sendCommand(
				IRCServerQuirks.ZNC.sendCertificateChainCommand,
				toZNCModuleNamed: IRCServerQuirks.ZNC.certificateInfoModule
			)
		}
		requestPlayback()

		let output = output
		/* Presumed present until a MONITOR reply or the ISON poll says otherwise;
		 activating now is what asks the server for each query's history. */
		for channel in channelList where channel.isPrivateMessage {
			applyPresence(true, to: channel)
		}
		output?.reloadTreeItem(self)
		output?.updateTitle(for: self)

		if !config.autojoinWaitsForNickServ || isCapabilityEnabled(.isIdentifiedWithSASL) {
			performAutoJoin(initiatedByUser: false)
		} else if isConnectedToZNC {
			postRegistrationAutoJoinTask?.cancel()
			postRegistrationAutoJoinTask = Task { [weak self] in
				try? await Task.sleep(for: .seconds(3))

				guard Task.isCancelled == false, let self else { return }

				performAutoJoin()
			}
		} else {
			startAutojoinDelayedWarningTimer()
		}

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
			toConsole: IRCInboundStrings.Numeric.nicknameUnavailable(tryingNicknameSentNickname ?? "")
		)

		if let nickname = IRCNicknameRetryPolicy.alternate(
			at: tryingNicknameNumber,
			from: config.alternateNicknames
		) {
			tryingNicknameSentNickname = nickname
			changeNickname(nickname)
		} else {
			tryAnotherNickname()
		}
		tryingNicknameNumber += 1
	}

	/** The length to pad a retried nickname to.

	 A hardcoded 31 used to stand here, so on a network advertising a shorter
	 `NICKLEN` the server answered 432 again and the retry ran over the wire
	 until `padNickname` had nothing left to pad. */
	private var nicknameRetryMaximumLength: UInt {
		guard supportInfo.configurationReceived, supportInfo.maximumNicknameLength > 0 else {
			return UInt(IRCProtocolLimits.defaultNicknameMaximumLength)
		}

		return supportInfo.maximumNicknameLength
	}

	func tryAnotherNickname() {
		guard isConnected, !isLoggedIn else { return }
		let nickname = IRCNicknameRetryPolicy.padded(
			tryingNicknameSentNickname,
			maximumLength: nicknameRetryMaximumLength
		)
		tryingNicknameSentNickname = nickname
		changeNickname(nickname)
	}
}
