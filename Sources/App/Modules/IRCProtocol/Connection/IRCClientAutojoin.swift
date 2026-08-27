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

import Foundation

enum IRCClientAutojoinPolicy {
	static let delayedWarningInterval: TimeInterval = 90
	static let maximumDelayedWarningCount: UInt = 3

	static func nextBatchCount(remaining: Int, configuredMaximum: UInt) -> Int {
		guard remaining > 0 else { return 0 }
		return min(remaining, max(1, Int(configuredMaximum)))
	}

	static func shouldWaitForIdentification(
		isIdentifiedWithSASL: Bool,
		waitsForNickServ: Bool,
		serverHasNickServ: Bool,
		isIdentifiedWithNickServ: Bool
	) -> Bool {
		!isIdentifiedWithSASL && waitsForNickServ && serverHasNickServ && !isIdentifiedWithNickServ
	}
}

@MainActor
public extension IRCClient {
	@objc(startAutojoinTimer)
	func startAutojoinTimer() {
		guard !autojoinTimer.timerIsActive else { return }
		let interval = TextualPreferences.autojoinDelayAfterIdentification()
		guard interval > 0 else {
			onAutojoinTimer()
			return
		}
		autojoinTimer.start(interval, onRepeat: false)
	}

	@objc(stopAutojoinTimer)
	func stopAutojoinTimer() {
		guard autojoinTimer.timerIsActive else { return }
		autojoinTimer.stop()
	}

	@objc(onAutojoinTimer)
	func onAutojoinTimer() {
		startAutojoinNextJoinTimer()
	}

	@objc(startAutojoinDelayedWarningTimer)
	func startAutojoinDelayedWarningTimer() {
		guard !autojoinDelayedWarningTimer.timerIsActive else { return }
		autojoinDelayedWarningTimer.start(IRCClientAutojoinPolicy.delayedWarningInterval, onRepeat: true)
	}

	@objc(stopAutojoinDelayedWarningTimer)
	func stopAutojoinDelayedWarningTimer() {
		guard autojoinDelayedWarningTimer.timerIsActive else { return }
		autojoinDelayedWarningTimer.stop()
	}

	@objc(onAutojoinDelayedWarningTimer)
	func onAutojoinDelayedWarningTimer() {
		guard isLoggedIn, !config.hideAutojoinDelayedWarnings,
		      autojoinDelayedWarningCount < IRCClientAutojoinPolicy.maximumDelayedWarningCount
		else {
			stopAutojoinDelayedWarningTimer()
			return
		}

		autojoinDelayedWarningCount += 1
		let text = IRCConnectionStrings.autojoinDelayedForIdentification
		printDebugInformation(toConsole: text)
		if let channel = NSObject.applicationController().mainWindow.selectedChannel(on: self) {
			printDebugInformation(text, in: channel)
		}
	}

	@objc(startAutojoinNextJoinTimer)
	func startAutojoinNextJoinTimer() {
		guard !autojoinNextJoinTimer.timerIsActive else { return }
		autojoinNextJoinTimer.start(TextualPreferences.autojoinDelayBetweenChannelJoins(), onRepeat: true)
		onAutojoinNextJoinTimer()
	}

	@objc(stopAutojoinNextJoinTimer)
	func stopAutojoinNextJoinTimer() {
		guard autojoinNextJoinTimer.timerIsActive else { return }
		autojoinNextJoinTimer.stop()
		channelsToAutojoin = nil
	}

	@objc(onAutojoinNextJoinTimer)
	func onAutojoinNextJoinTimer() {
		autojoinNextChannel()
	}

	@objc(autojoinNextChannel)
	func autojoinNextChannel() {
		guard isAutojoining, let pendingChannels = channelsToAutojoin else { return }
		let count = IRCClientAutojoinPolicy.nextBatchCount(
			remaining: pendingChannels.count,
			configuredMaximum: TextualPreferences.autojoinMaximumChannelJoins()
		)
		let channels = pendingChannels.prefix(count).compactMap { $0 as? IRCChannel }
		joinChannels(channels)

		if count < pendingChannels.count {
			pendingChannels.removeObjects(in: NSRange(location: 0, length: count))
		} else {
			isAutojoining = false
			isAutojoined = true
			stopAutojoinNextJoinTimer()
		}
	}

	@objc(autojoinChannels:)
	func autojoinChannels(_ channels: [IRCChannel]) {
		joinChannels(channels)
	}

	@objc(performAutoJoin)
	func performAutoJoin() {
		performAutoJoin(initiatedByUser: false)
	}

	@objc(performAutoJoinInitiatedByUser:)
	func performAutoJoin(initiatedByUser: Bool) {
		guard !isAutojoining else { return }
		stopAutojoinDelayedWarningTimer()

		if !initiatedByUser {
			guard !isAutojoined else { return }
			if isConnectedToZNC, config.zncIgnoreConfiguredAutojoin {
				isAutojoined = true
				return
			}
			guard !IRCClientAutojoinPolicy.shouldWaitForIdentification(
				isIdentifiedWithSASL: isCapabilityEnabled(.isIdentifiedWithSASL),
				waitsForNickServ: config.autojoinWaitsForNickServ,
				serverHasNickServ: serverHasNickServ,
				isIdentifiedWithNickServ: userIsIdentifiedWithNickServ
			) else { return }
		}

		let channels = channelList.filter { $0.isChannel && !$0.isActive && $0.config.autoJoin }
		guard !channels.isEmpty else {
			isAutojoining = false
			isAutojoined = true
			return
		}

		isAutojoining = true
		channelsToAutojoin = NSMutableArray(array: channels.shuffled())
		startAutojoinTimer()
	}
}
