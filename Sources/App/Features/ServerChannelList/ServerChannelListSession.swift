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

import Combine
import Foundation

/// Owns one server's public-channel list and connects its SwiftUI scene to the
/// IRC client. Window lifecycle and restoration belong to SwiftUI.
@MainActor
final class ServerChannelListSession {
	let client: IRCClient
	let model = ServerChannelListModel()

	/** How long a listing may go without a reply before the window stops
	 waiting for it.

	 `RPL_LISTEND` is the only reply that ends a listing, and plenty of paths
	 never send one: a server that throttles `LIST` answers with a notice or
	 an unlisted numeric, and a connection can go quiet without closing. The
	 limit counts from the last reply, so a network streaming a very long
	 listing is never cut off. */
	private let replyTimeout: Duration
	private var replyDeadline: ContinuousClock.Instant?
	private var replyWatchdog: Task<Void, Never>?
	private var connectionObservation: Task<Void, Never>?

	init(client: IRCClient, replyTimeout: Duration = .seconds(60)) {
		self.client = client
		self.replyTimeout = replyTimeout
		observeConnection()
	}

	isolated deinit {
		replyWatchdog?.cancel()
		connectionObservation?.cancel()
	}

	var clientIdentifier: String {
		client.uniqueIdentifier
	}

	var networkName: String {
		client.networkNameAlt
	}

	var supportsMinimumUserCount: Bool {
		client.supportInfo.extendedListSupportsToken("U")
	}

	var serverSideListArguments: String? {
		model.listArguments(supportedTokens: client.supportInfo.extendedListTokens)
	}

	/// Asks the server for a fresh listing. A client that is not logged in has
	/// nobody to ask, so the list does not wait for an answer.
	func beginRefresh() {
		model.beginRefresh()
		guard client.isLoggedIn else {
			finishRefresh()
			return
		}
		client.requestChannelList(withArguments: serverSideListArguments)
		noteReply()
	}

	func receiveListStart() {
		model.beginRefresh()
		noteReply()
	}

	func clear() {
		model.clear()
	}

	func addChannel(_ channel: String, count: UInt, topic: String?) {
		model.enqueue(channelName: channel, memberCount: count, topic: topic)
		if model.isRefreshing {
			noteReply()
		}
	}

	func finishRefresh() {
		replyWatchdog?.cancel()
		replyWatchdog = nil
		replyDeadline = nil
		model.finishRefresh()
	}

	func joinSelectedChannels() {
		let channelNames = model.selectedChannelNames
		guard channelNames.isEmpty == false else { return }
		client.joinUnlistedChannelsAndSelectBestMatch(channelNames)
		model.clearSelection()
	}

	func close() {
		replyWatchdog?.cancel()
		replyWatchdog = nil
		connectionObservation?.cancel()
		connectionObservation = nil
		model.cancelPendingWrites()
	}

	/// Moves the deadline on, and starts the watchdog if nothing is watching it.
	private func noteReply() {
		replyDeadline = .now + replyTimeout
		guard replyWatchdog == nil else { return }
		replyWatchdog = Task { [weak self] in
			while let deadline = self?.replyDeadline {
				do {
					try await Task.sleep(until: deadline, clock: .continuous)
				} catch {
					return
				}
				guard let self else { return }
				/* A reply that arrived during the sleep moved the deadline; only
				 one that is still in the past ends the wait. */
				if let current = replyDeadline, current <= .now {
					replyWatchdog = nil
					finishRefresh()
					return
				}
			}
		}
	}

	/** A listing cannot outlive the registration it was asked on: the server
	 that would have finished it is gone.

	 The initial value is read too. The observation starts when its task first
	 runs, which can be after a logout that happened in the same turn as the
	 refresh; the value it starts from is what still catches that one. */
	private func observeConnection() {
		let client = client
		connectionObservation = Task { [weak self] in
			for await isLoggedIn in client.publisher(for: \.isLoggedIn, options: [.initial, .new]).bufferedValues {
				guard let self, !Task.isCancelled else { return }
				if isLoggedIn == false, model.isRefreshing {
					finishRefresh()
				}
			}
		}
	}
}
