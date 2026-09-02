/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation
@testable import Glasstual
import GlasstualPluginKit
import Testing

@MainActor
@Suite("Client highlight cache")
struct IRCClientHighlightCacheTests {
	private func makeClient() -> GLTTestClient {
		var preferences = ClientPreferences()
		preferences.logHighlights = true

		return GLTTestClient(
			configDictionary: [:],
			nicknamePassword: nil,
			fixture: GLTClientEnvironmentFixture(preferences: preferences)
		)
	}

	private func makeChannel(on client: IRCClient) -> IRCChannel {
		let channel = Channel(config: ChannelConfig(channelName: "#chat", type: .channel))
		channel.associatedClient = client

		return channel
	}

	private func logLine(_ body: String) -> LogLine {
		var line = LogLine()
		line.messageBody = body
		line.nickname = "alice"
		line.lineType = .privateMessage

		return line
	}

	@Test("A logged highlight is offered to the window, not to a sheet the client reached for")
	func aCachedHighlightIsReportedThroughTheOutputSeam() {
		let client = makeClient()
		let channel = makeChannel(on: client)

		client.cacheHighlight(in: channel, with: logLine("hello"))

		#expect(client.cachedHighlights.count == 1)
		#expect(client.recordedOutput.loggedHighlights.map(\.lineLogged.messageBody) == ["hello"])
	}

	@Test("Highlights are not cached when the preference is off")
	func highlightsAreNotCachedWhenLoggingIsOff() {
		let client = GLTTestClient(
			configDictionary: [:],
			nicknamePassword: nil,
			fixture: GLTClientEnvironmentFixture(preferences: ClientPreferences())
		)
		let channel = makeChannel(on: client)

		client.cacheHighlight(in: channel, with: logLine("hello"))

		#expect(client.cachedHighlights.isEmpty)
		#expect(client.recordedOutput.loggedHighlights.isEmpty)
	}

	/// The cache used to grow for the life of the session, holding every
	/// `LogLine` it ever matched.
	@Test("The cache stops at its ceiling and drops the oldest highlights")
	func theCacheIsBounded() {
		let client = makeClient()
		let channel = makeChannel(on: client)
		let overflow = 10

		for index in 0 ..< (IRCClient.maximumCachedHighlights + overflow) {
			client.cacheHighlight(in: channel, with: logLine("\(index)"))
		}

		#expect(client.cachedHighlights.count == IRCClient.maximumCachedHighlights)
		#expect(client.cachedHighlights.first?.lineLogged.messageBody == "\(overflow)")
		#expect(
			client.cachedHighlights.last?.lineLogged.messageBody
				== "\(IRCClient.maximumCachedHighlights + overflow - 1)"
		)
	}
}
