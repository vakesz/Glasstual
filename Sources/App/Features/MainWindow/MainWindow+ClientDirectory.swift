// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit

// MARK: - ClientDirectory observer

/** The window draws what the client directory publishes. Nothing here reaches
 back into the IRC layer; every entry point is an event the directory posted. */
extension MainWindow: ClientDirectoryObserver {
	func clientDirectoryWillBeginBulkUpdate(_: ClientDirectory) {
		serverList?.beginUpdates()
	}

	func clientDirectoryDidEndBulkUpdate(_: ClientDirectory) {
		serverList?.endUpdates()
	}

	func clientDirectory(_: ClientDirectory, didAddClient client: Client, at _: Int) {
		/* The views have to exist before the row that shows them does. */
		transcriptControllers.registerTree(of: client)
		serverList?.setNeedsRefresh()
	}

	func clientDirectory(_: ClientDirectory, didRemoveClient client: Client) {
		serverList?.itemWasRemoved(client)
		transcriptControllers.forgetTree(of: client)
	}

	func clientDirectory(_: ClientDirectory, didMoveClientFrom _: Int, to _: Int) {
		serverList?.setNeedsRefresh()
	}

	func clientDirectory(_: ClientDirectory, didAddChannel channel: Channel, on _: Client, at _: Int) {
		transcriptControllers.controller(for: channel)
		serverList?.setNeedsRefresh()
	}

	func clientDirectory(_: ClientDirectory, didRemoveChannel channel: Channel, on _: Client) {
		serverList?.itemWasRemoved(channel)
		transcriptControllers.forget(channel)
	}

	func clientDirectory(_: ClientDirectory, didMoveChannelOn _: Client, from _: Int, to _: Int) {
		serverList?.setNeedsRefresh()
	}

	func clientDirectory(_: ClientDirectory, requestsSelectionOf item: ChatItem) {
		select(item)
	}

	func clientDirectory(_: ClientDirectory, requestsDeselectionOf item: ChatItem) {
		deselect(item)
	}

	func clientDirectory(_: ClientDirectory, requestsGroupDeselectionOf item: ChatItem) {
		deselectGroup(item)
	}

	func clientDirectoryRequestsSelectionAdjustment(_: ClientDirectory) {
		adjustSelection()
	}

	func clientDirectoryClientListDidChange(_: ClientDirectory) {
		reloadLoadingScreen()
	}
}
