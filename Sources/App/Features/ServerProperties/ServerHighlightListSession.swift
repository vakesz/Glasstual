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
 *********************************************************************** */

import Observation

/** One connection's logged highlights, as its own window.

 A modal sheet was the wrong shape for a list whose only purpose is to jump into
 the transcript: choosing a row had to dismiss the sheet to get there, and going
 back for the next one meant reopening it. The window stays up, the transcript
 moves behind it, and highlights logged while it is open are added as they
 arrive. */
@MainActor
@Observable
public final class ServerHighlightListSession: ClientScoped {
	public let client: IRCClient
	public let clientId: String?

	let model = ServerHighlightListModel()

	public init(client: IRCClient) {
		self.client = client
		clientId = client.uniqueIdentifier
		model.replace(with: client.cachedHighlights)
	}

	var networkName: String {
		client.networkNameAlt
	}

	public func addEntry(_ newEntry: HighlightLogEntry) {
		model.addEntries([newEntry])
	}

	func clearHighlights() {
		model.clear()
		client.clearCachedHighlights()
	}

	/** Selects the channel the highlight was logged in and scrolls to the line.

	 The window stays open: the list exists to move around the transcript with,
	 and closing it on every jump made a second one a second trip through the
	 menu. The channel is looked up again once the jump lands because the wait
	 gives the world time to have destroyed it. */
	func activateHighlight(withID id: String) {
		guard let entry = model.entry(withID: id) else { return }
		let channel = ClientEnvironment.shared.world?.findChannel(
			withId: entry.channelId,
			onClientWithId: entry.clientId
		)
		guard let channel, let logController = channel.logController, let clientId else { return }

		let channelId = channel.uniqueIdentifier
		logController.jump(toLine: entry.lineNumber) { success in
			guard success else { return }
			guard let channel = ClientEnvironment.shared.world?.findChannel(
				withId: channelId,
				onClientWithId: clientId
			) else { return }

			AppController.shared.mainWindow.select(channel)
		}
	}
}
