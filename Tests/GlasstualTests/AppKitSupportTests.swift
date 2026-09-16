/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
import CocoaExtensions
import Foundation
@testable import Glasstual
import SwiftUI
import Testing

@MainActor
@Suite("AppKit support", .serialized)
struct AppKitSupportTests {
	/// The suppression family is catalogued as a container key, so the flags are
	/// stored there rather than in UserDefaults.standard, which is what makes an
	/// imported "do not ask again" take effect.
	@Test("An alert is suppressed exactly when its stored preference says so")
	func alertSuppressionDecisionFollowsTheStoredPreference() {
		let baseKey = "AppKitSupportTests.\(UUID().uuidString)"
		let defaultsKey = Alerts.suppressionKey(withBase: baseKey)
		let defaults = GlasstualUserDefaults.container
		defer { defaults.removeObject(forKey: defaultsKey) }

		#expect(Alerts.isSuppressed(baseKey: baseKey) == false)

		defaults.set(true, forKey: defaultsKey)

		#expect(Alerts.isSuppressed(baseKey: baseKey))
	}

	@Test("A notification about a client names that client and no channel")
	func spokenNotificationResolvesClientTarget() {
		let client = TestClient()
		let notification = SpokenNotification(
			notificationType: .connect,
			lineType: .notice,
			target: client,
			nickname: "alice",
			text: "connected"
		)

		#expect(notification.clientIdentifier == client.uniqueIdentifier)
		#expect(notification.channelIdentifier == nil)
		#expect(notification.notificationType == .connect)
		#expect(notification.lineType == .notice)
		#expect(notification.nickname == "alice")
		#expect(notification.text == "connected")
	}

	@Test("A notification about a channel names the channel and the client behind it")
	func spokenNotificationResolvesChannelAndItsClient() {
		let client = TestClient()
		let channel = makeChannel(named: "#chat", client: client)
		let notification = SpokenNotification(
			notificationType: .channelMessage,
			lineType: .privateMessage,
			target: channel,
			nickname: "alice",
			text: "hello"
		)

		#expect(notification.clientIdentifier == client.uniqueIdentifier)
		#expect(notification.channelIdentifier == channel.uniqueIdentifier)
	}

	private func makeChannel(named name: String, client: Client) -> Channel {
		let channel = Channel(config: ChannelConfig(channelName: name))

		channel.associatedClient = client

		return channel
	}
}
