// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Observation

/** The access-list window, and the list it is showing.

 One window, so opening a second channel's list replaces what it shows rather
 than adding a window whose replies it could not tell apart. That is why this is
 observable: the scene root reads the session through it, so a replacement
 redraws the window that is already up. */
@MainActor
@Observable
final class ChannelMaskListWindow {
	private(set) var current: ChannelMaskListSession?

	@ObservationIgnored private let scenes: ApplicationScenes

	init(scenes: ApplicationScenes = AppServices.scenes) {
		self.scenes = scenes
	}

	/** Opens one channel's access list, replacing whatever the window was
	 showing.

	 A window rather than a sheet, so the channel the list is about can be read
	 and typed into while its entries are being looked over. The mode query that
	 fills it is sent by the caller, so the session is in place before the first
	 reply can arrive. */
	func open(maskKind: ChannelMaskKind, in channel: Conversation) {
		guard let session = ChannelMaskListSession(maskKind: maskKind, in: channel) else { return }
		current = session
		scenes.open(ApplicationSceneID.channelMaskList)
	}

	func didClose() {
		current?.cancelPendingRefresh()
		current = nil
	}

	/// Offers a refused change to the open list. `true` when it was this list's.
	func receiveRefusal(session: ServerSession, channelName: String, numeric: UInt, text: String) -> Bool {
		current?.receiveRefusal(session: session, channelName: channelName, numeric: numeric, text: text) ?? false
	}

	/// Closes the list when the channel or connection it is about goes away,
	/// which is what the sheet it replaced got from the main window.
	func close(matching isStale: (ChannelMaskListSession) -> Bool) {
		guard let session = current, isStale(session) else { return }
		session.cancelPendingRefresh()
		current = nil
		scenes.dismiss(ApplicationSceneID.channelMaskList)
	}
}
