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

import Observation

/// Owns one server's public-channel list and connects its SwiftUI scene to the
/// IRC client. Window lifecycle and restoration belong to SwiftUI.
@MainActor
@Observable
final class ServerChannelListSession {
	let client: IRCClient
	let model = ServerChannelListModel()

	init(client: IRCClient) {
		self.client = client
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

	func beginRefresh() {
		model.beginRefresh()
		client.requestChannelList(withArguments: serverSideListArguments)
	}

	func receiveListStart() {
		model.beginRefresh()
	}

	func clear() {
		model.clear()
	}

	func addChannel(_ channel: String, count: UInt, topic: String?) {
		model.enqueue(channelName: channel, memberCount: count, topic: topic)
	}

	func finishRefresh() {
		model.finishRefresh()
	}

	func activate(_ entryID: ServerChannelListEntry.ID) {
		model.selectOnly(entryID)
		joinSelectedChannels()
	}

	func joinSelectedChannels() {
		let channelNames = model.selectedChannelNames
		guard channelNames.isEmpty == false else { return }
		client.joinUnlistedChannelsAndSelectBestMatch(channelNames)
		model.clearSelection()
	}

	func close() {
		model.cancelPendingWrites()
	}
}
