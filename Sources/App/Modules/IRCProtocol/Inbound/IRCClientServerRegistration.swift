/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
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
import ObjectiveC

enum IRCNicknameRetryPolicy {
	static let fallbackNickname = "0"
	static let defaultMaximumLength: UInt = 31

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
	@objc(resetCapabilityNegotiation)
	func resetCapabilityNegotiation() {
		capabilities = []
		capabilityNegotiationIsPaused = false
		saslMechanism = nil
		saslOfferedMechanisms = nil
		saslScramClient = nil
		saslIncomingPayload = nil
		saslTriedMechanisms.removeAllObjects()
		pendingDeliveries.removeAllObjects()
		labelForBatchToken.removeAllObjects()
		enabledCapabilityNames.removeAllObjects()
		offeredCapabilities.removeAllObjects()
		offeredCapabilityNames.removeAllObjects()
		objc_sync_enter(pendingCapabilityRequestsMutable)
		pendingCapabilityRequestsMutable.removeAllObjects()
		objc_sync_exit(pendingCapabilityRequestsMutable)
	}

	@objc(receivePing:)
	func receivePing(_ message: Message) {
		guard !message.params.isEmpty else { return }
		sendPong(message.sequence(0))
		_ = postReceivedMessage(message)
	}

	@objc(receiveAwayNotifyCapability:)
	func receiveAwayNotifyCapability(_ message: Message) {
		guard isCapabilityEnabled(.awayNotify), let nickname = message.senderNickname else { return }
		modifyUser(withNickname: nickname, asAway: !message.sequence.isEmpty)
	}

	@objc(receiveInit:)
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
		postEvent(toViewController: "serverConnected")
		_ = notifyEvent(.connect, lineType: .debug)

		isPerformingConnectCommands = true
		for configuredCommand in config.loginCommands {
			let command = configuredCommand.hasPrefix("/") ? String(configuredCommand.dropFirst()) : configuredCommand
			sendCommand(command, completeTarget: false, target: nil)
		}
		isPerformingConnectCommands = false

		if isCapabilityEnabled(.zncCertInfoModule) {
			sendCommand("send-data", toZNCModuleNamed: "tlsinfo")
		}
		requestPlayback()

		let mainWindow = NSObject.applicationController().mainWindow
		for channel in channelList where channel.isPrivateMessage {
			channel.activate()
			if let treeItem = (channel as AnyObject) as? IRCTreeItem {
				mainWindow?.reloadTreeItem(treeItem)
			}
		}
		mainWindow?.reloadTreeItem(self)
		mainWindow?.updateTitle(for: self)

		if !config.autojoinWaitsForNickServ || isCapabilityEnabled(.isIdentifiedWithSASL) {
			performAutoJoin(initiatedByUser: false)
		} else if isConnectedToZNC {
			textual_performSelectorInCommonModes(
				NSSelectorFromString("performAutoJoin"),
				with: nil,
				afterDelay: 3
			)
		} else {
			startAutojoinDelayedWarningTimer()
		}

		textual_performSelectorInCommonModes(
			#selector(populateISONTrackedUsersList),
			with: nil,
			afterDelay: 10
		)
	}

	@objc(receiveNicknameCollisionError:)
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

	@objc(tryAnotherNickname)
	func tryAnotherNickname() {
		guard isConnected, !isLoggedIn else { return }
		let nickname = IRCNicknameRetryPolicy.padded(
			tryingNicknameSentNickname,
			maximumLength: IRCNicknameRetryPolicy.defaultMaximumLength
		)
		tryingNicknameSentNickname = nickname
		changeNickname(nickname)
	}
}
