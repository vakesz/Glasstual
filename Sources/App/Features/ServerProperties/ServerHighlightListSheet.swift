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

import SwiftUI

@MainActor
public protocol ServerHighlightListSheetDelegate: AnyObject {
	func serverHighlightListSheetWillClose(_ sender: ServerHighlightListSheet)
}

@MainActor
public final class ServerHighlightListSheet: MainWindowSheetSession, ClientScoped {
	public private(set) var client: IRCClient!
	public private(set) var clientId: String?

	let model = ServerHighlightListModel()

	public init(client: IRCClient) {
		self.client = client
		clientId = client.uniqueIdentifier
		super.init(window: nil)
		installSheet()
		model.replace(with: client.cachedHighlights)
	}

	private func installSheet() {
		let rootView = ServerHighlightListView(
			model: model,
			networkName: client.networkNameAlt,
			activate: { [weak self] id in self?.activateHighlight(withID: id) },
			clear: { [weak self] in self?.clearHighlights() },
			close: { [weak self] in self?.cancel(nil) }
		)
		setContent(rootView)
	}

	public func start() {
		startSheet()
	}

	public func addEntry(_ newEntry: HighlightLogEntry) {
		model.addEntries([newEntry])
	}

	private func clearHighlights() {
		model.clear()
		client.clearCachedHighlights()
	}

	private func activateHighlight(withID id: String) {
		guard let entry = model.entry(withID: id) else { return }
		let channel = ClientEnvironment.shared.world?.findChannel(
			withId: entry.channelId,
			onClientWithId: entry.clientId
		)
		guard let channel, let logController = channel.logController, let clientId else { return }

		let channelId = channel.uniqueIdentifier
		logController.jump(toLine: entry.lineNumber) { [weak self] success in
			guard success else { return }
			guard let channel = ClientEnvironment.shared.world?.findChannel(
				withId: channelId,
				onClientWithId: clientId
			) else { return }

			AppController.shared.mainWindow.select(channel)
			self?.cancel(nil)
		}
	}

	override public func sheetDidEnd(withReturnCode _: Int) {
		(delegate as? any ServerHighlightListSheetDelegate)?.serverHighlightListSheetWillClose(self)
	}
}
