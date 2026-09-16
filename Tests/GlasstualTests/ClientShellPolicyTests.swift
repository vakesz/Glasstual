/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
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

@testable import Glasstual
import Testing

@MainActor
@Suite("Client shell policies")
struct ClientShellPolicyTests {
	@Test("Channels are stored ahead of queries")
	func channelStoragePlacesChannelsBeforeQueries() {
		let client = TestClient()

		client.add(Channel(config: ChannelConfig(channelName: "#first")))
		client.add(Channel(config: ChannelConfig(channelName: "someone", type: .privateMessage)))
		client.add(Channel(config: ChannelConfig(channelName: "#second")))
		client.add(Channel(config: ChannelConfig(channelName: "other", type: .privateMessage)))

		#expect(client.channelList.map(\.name) == ["#first", "#second", "someone", "other"])
	}

	@Test("A utility window or a direct chat is never written to the stored configuration")
	func storedConfigurationExcludesTransientChannels() {
		#expect(
			ClientConfigurationPolicy.shouldStoreChannel(
				isUtility: true,
				isDirectChat: false,
				isChannel: true,
				rememberQueries: true
			) == false
		)
		#expect(
			ClientConfigurationPolicy.shouldStoreChannel(
				isUtility: false,
				isDirectChat: true,
				isChannel: false,
				rememberQueries: true
			) == false
		)
	}

	@Test("A query is stored only while the remember-queries preference is on")
	func storedConfigurationHonorsQueryPreference() {
		#expect(
			ClientConfigurationPolicy.shouldStoreChannel(
				isUtility: false,
				isDirectChat: false,
				isChannel: false,
				rememberQueries: false
			) == false
		)
		#expect(
			ClientConfigurationPolicy.shouldStoreChannel(
				isUtility: false,
				isDirectChat: false,
				isChannel: false,
				rememberQueries: true
			)
		)
	}

	@Test("An unreachable network disconnects a logged-in client only when asked to")
	func reachabilityDisconnectRequiresAllConditions() {
		#expect(
			ClientReachabilityPolicy.shouldDisconnect(
				isLoggedIn: true,
				disconnectWhenUnreachable: true
			)
		)
		#expect(
			ClientReachabilityPolicy.shouldDisconnect(
				isLoggedIn: true,
				disconnectWhenUnreachable: false
			) == false
		)
		#expect(
			ClientReachabilityPolicy.shouldDisconnect(
				isLoggedIn: false,
				disconnectWhenUnreachable: true
			) == false
		)
	}

	@Test("Termination disconnects a client that is connecting or connected")
	func terminationDisconnectsConnectingOrConnectedClients() {
		#expect(ClientLifecyclePolicy.requiresDisconnect(isConnecting: true, isConnected: false))
		#expect(ClientLifecyclePolicy.requiresDisconnect(isConnecting: false, isConnected: true))
		#expect(ClientLifecyclePolicy.requiresDisconnect(isConnecting: false, isConnected: false) == false)
	}
}
