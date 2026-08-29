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

enum UserTrackingWhoBatchPolicy {
	/// The legacy scheduler advances through the starting channel plus four more.
	static let maximumChannelOffset = 4
	static let maximumInitialChannelSize: UInt = 5000
	static let maximumTotalChannelSize: UInt = 2000

	static func indexRange(startingAt requestedStart: Int, channelCount: Int) -> ClosedRange<Int>? {
		guard channelCount > 0 else { return nil }

		let start = requestedStart < channelCount ? requestedStart : 0
		let end = min(start + maximumChannelOffset, channelCount - 1)
		return start ... end
	}
}

extension IRCClient {
	private var userTracking: AddressBookUserTrackingContainer {
		guard let container = (trackedUsers as AnyObject) as? AddressBookUserTrackingContainer else {
			preconditionFailure("IRCClient must own its Swift user-tracking container")
		}

		return container
	}

	func clearTrackedUsers() {
		userTracking.clearTrackedUsers()
	}

	func setTrackedNickname(_ nickname: String, status: IRCAddressBookUserTrackingStatus) {
		setTrackedNickname(nickname, status: status, notify: false)
	}

	func setTrackedNickname(
		_ nickname: String,
		status: IRCAddressBookUserTrackingStatus,
		notify: Bool
	) {
		userTracking.status(ofTrackedNickname: nickname, changedTo: status)

		if notify {
			notifyTrackedNickname(nickname, status: status)
		}
	}

	private func notifyTrackedNickname(_ nickname: String, status: IRCAddressBookUserTrackingStatus) {
		guard let message = NotificationStrings.Availability.message(for: status, nickname: nickname) else {
			return
		}

		_ = notifyEvent(
			.addressBookMatch,
			lineType: .notice,
			target: nil,
			nickname: nickname,
			text: message
		)
	}

	@MainActor func populateISONTrackedUsersList() {
		guard isLoggedIn else { return }

		var additions: [String] = []
		var removals: [String] = []
		let previousNicknames = Array(userTracking.trackedUsers.keys)
		var currentNicknames: [String] = []

		for entry in config.ignoreList where entry.trackUserActivity {
			guard let nickname = entry.trackingNickname else { continue }

			if userTracking.status(ofUser: nickname) != .unknown {
				currentNicknames.append(nickname)
				continue
			}

			additions.append(nickname)
			userTracking.addTrackedUserWithoutDuplicateCheck(nickname)
		}

		for nickname in previousNicknames where currentNicknames.contains(where: {
			$0.caseInsensitiveCompare(nickname) == .orderedSame
		}) == false {
			removals.append(nickname)
			userTracking.removeTrackedUserWithoutLookup(nickname)
		}

		modifyWatchList(byAdding: true, nicknames: additions)
		modifyWatchList(byAdding: false, nicknames: removals)
		startISONTimer()
	}

	func startISONTimer() {
		guard isonTimer.isActive == false else { return }
		isonTimer.start(30, repeats: true)
		startWhoTimer()
	}

	func stopISONTimer() {
		guard isonTimer.isActive else { return }
		isonTimer.stop()
		stopWhoTimer()
	}

	@MainActor func onISONTimer() {
		guard isLoggedIn, isBrokenIRCdKnownAsTwitch == false else { return }

		var nicknames = supportsAdvancedTracking ? [] : Array(userTracking.trackedUsers.keys)
		nicknames.append(contentsOf: channelList.filter(\.isPrivateMessage).map(\.name))
		sendIson(forNicknames: nicknames, hideResponse: true)
	}

	func startWhoTimer() {
		guard whoTimer.isActive == false else { return }
		whoTimer.start(120, repeats: true)
	}

	func stopWhoTimer() {
		guard whoTimer.isActive else { return }
		whoTimer.stop()
	}

	@MainActor func onWhoTimer() {
		guard isLoggedIn, isBrokenIRCdKnownAsTwitch == false else { return }
		sendTimedWhoRequests(to: channelList)
	}

	@MainActor
	func sendTimedWhoRequests(to channels: [IRCChannel]) {
		guard isLoggedIn, isBrokenIRCdKnownAsTwitch == false,
		      let range = UserTrackingWhoBatchPolicy.indexRange(
		      	startingAt: Int(lastWhoRequestChannelListIndex),
		      	channelCount: channels.count
		      )
		else { return }

		var endIndex = range.upperBound
		var totalMemberCount: UInt = 0
		var channelsToQuery: [IRCChannel] = []

		for index in range {
			let channel = channels[index]
			guard channel.isActive, channel.isChannel else { continue }

			let sentInitialRequest = channel.sentInitialWhoRequest
			if sentInitialRequest == false {
				channel.sentInitialWhoRequest = true
			}

			guard config.sendWhoCommandRequestsToChannels else { continue }

			let memberCount = UInt(channel.numberOfMembers)
			if sentInitialRequest == false {
				guard memberCount <= UserTrackingWhoBatchPolicy.maximumInitialChannelSize else { continue }
			} else {
				guard isCapabilityEnabled(.awayNotify) == false,
				      memberCount <= environment.preferences.trackUserAwayStatusMaximumChannelSize
				else { continue }
			}

			channelsToQuery.append(channel)
			totalMemberCount += memberCount

			if totalMemberCount > UserTrackingWhoBatchPolicy.maximumTotalChannelSize {
				endIndex = index
				break
			}
		}

		lastWhoRequestChannelListIndex = UInt(endIndex + 1)

		for channel in channelsToQuery {
			sendWho(to: channel, hideResponse: true)
		}
	}

	func updateUserTrackingStatus(for entry: AddressBookEntry, message: Message) {
		guard supportsAdvancedTracking == false else { return }

		let trackingStatus = userTracking.status(of: entry)
		guard trackingStatus != .unknown, let senderNickname = message.senderNickname else { return }

		let isAvailable = trackingStatus == .available
		switch message.command.uppercased() {
		case "JOIN" where isAvailable == false:
			setTrackedNickname(senderNickname, status: .signedOn, notify: true)
		case "QUIT" where isAvailable:
			setTrackedNickname(senderNickname, status: .signedOff, notify: true)
		case "NICK":
			setTrackedNickname(senderNickname, status: isAvailable ? .signedOff : .signedOn, notify: true)
		default:
			break
		}
	}
}
