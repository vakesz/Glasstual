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

import AppKit

// MARK: - World observer

/** The window draws what the world publishes. Nothing here reaches back into
 the IRC layer; every entry point is an event the world posted. */
extension MainWindow: WorldObserver {
	func worldWillBeginBulkUpdate(_: IRCWorld) {
		serverList?.beginUpdates()
	}

	func worldDidEndBulkUpdate(_: IRCWorld) {
		serverList?.endUpdates()
	}

	func world(_: IRCWorld, didAddClient client: IRCClient, at index: Int) {
		/* The views have to exist before the row that shows them does. */
		logControllers.registerTree(of: client)
		serverList?.addItem(toList: UInt(index), inParent: nil)
	}

	func world(_: IRCWorld, didRemoveClient client: IRCClient) {
		serverList?.removeItem(fromList: client)
		logControllers.forgetTree(of: client)
	}

	func world(_: IRCWorld, didMoveClientFrom oldIndex: Int, to newIndex: Int) {
		serverList?.moveItem(at: oldIndex, inParent: nil, to: newIndex, inParent: nil)
	}

	func world(_: IRCWorld, didAddChannel channel: IRCChannel, on client: IRCClient, at index: Int) {
		logControllers.controller(for: channel)
		serverList?.addItem(toList: UInt(index), inParent: client)
	}

	func world(_: IRCWorld, didRemoveChannel channel: IRCChannel, on _: IRCClient) {
		serverList?.removeItem(fromList: channel)
		logControllers.forget(channel)
	}

	func world(_: IRCWorld, didMoveChannelOn client: IRCClient, from oldIndex: Int, to newIndex: Int) {
		serverList?.moveItem(at: oldIndex, inParent: client, to: newIndex, inParent: client)
	}

	func world(_: IRCWorld, requestsSelectionOf item: IRCTreeItem) {
		select(item)
	}

	func world(_: IRCWorld, requestsDeselectionOf item: IRCTreeItem) {
		deselect(item)
	}

	func world(_: IRCWorld, requestsGroupDeselectionOf item: IRCTreeItem) {
		deselectGroup(item)
	}

	func worldRequestsSelectionAdjustment(_: IRCWorld) {
		adjustSelection()
	}

	func worldClientListDidChange(_: IRCWorld) {
		_ = reloadLoadingScreen()
	}
}

// MARK: - Client output

/** The window-side work the IRC layer asks for. Most of it forwards to a method
 that already existed; the seam is what keeps the caller from knowing that. */
extension MainWindow: ClientOutput {
	func selectItem(_ item: IRCTreeItem) {
		select(item)
	}

	func isItemSelectedInWindow(_ item: IRCTreeItem) -> Bool {
		isItemSelected(item)
	}

	var windowIsKey: Bool {
		isKeyWindow
	}

	var windowIsMain: Bool {
		isMainWindow
	}

	func presentAlertSheet(_ request: AlertRequest, completion: @escaping AlertCompletion) {
		Alerts.alertSheet(request: request, completionBlock: completion)
	}

	func confirmModally(_ request: AlertRequest) -> Bool {
		Alerts.runModal(request).response == .default
	}

	func closeSheets(for client: IRCClient) {
		presentationModel.closeSheets { owner in
			guard let clientSheet = owner as? ClientScoped else { return false }

			return clientSheet.clientId == client.uniqueIdentifier
		}
	}

	func accessListEntryReceived(mask: String, setBy author: String?, creationDate date: Date?) -> Bool {
		guard let sheet = presentationModel.sheetOwner(ofType: ChannelBanListSheet.self) else {
			return false
		}

		/* The sheet holds the previous reply until the next one starts arriving,
		 so that a refresh does not blank the table before the new list lands. */
		if sheet.contentAlreadyReceived {
			sheet.contentAlreadyReceived = false
			sheet.clear()
		}

		sheet.addEntry(mask, setBy: author, creationDate: date)

		return true
	}

	func accessListFinished() -> Bool {
		guard let sheet = presentationModel.sheetOwner(ofType: ChannelBanListSheet.self) else {
			return false
		}

		sheet.contentAlreadyReceived = true

		return true
	}

	func closeSheets(forChannelId channelId: String) {
		presentationModel.closeSheets { owner in
			guard let channelSheet = owner as? ChannelScoped else { return false }
			return channelSheet.channelId == channelId
		}
	}

	func highlightWasLogged(_ entry: HighlightLogEntry) {
		guard let sheet = presentationModel.sheetOwner(ofType: ServerHighlightListSheet.self),
		      sheet.clientId == entry.clientId
		else { return }

		sheet.addEntry(entry)
	}

	func reloadServerListItems(for client: IRCClient) {
		guard let serverList else { return }

		ignoreServerListSelectionChanges = true
		serverList.beginUpdates()
		serverList.reloadItem(client, reloadChildren: true)
		serverList.endUpdates()
		adjustSelection()
		ignoreServerListSelectionChanges = false
	}

	func refreshMessageCount(for item: IRCTreeItem) {
		serverList?.refreshMessageCount(forItem: item)
	}

	func updateDrawingForUser(_ user: User) {
		updateDrawingForUserInUserList(user)
	}

	func beginMemberListUpdates() -> Bool {
		guard let memberList else { return false }
		memberList.beginUpdates()
		return true
	}

	func endMemberListUpdates() {
		memberList?.endUpdates()
	}

	func refreshMemberListDrawing(forMemberAt _: Int) {
		memberList?.invalidatePresentation()
	}

	func assignMemberList(to channel: IRCChannel) {
		memberList?.assign(to: channel)
	}

	func clearContents(of item: IRCTreeItem) {
		if let channel = item as? IRCChannel {
			clearContents(of: channel)
		} else if let client = item as? IRCClient {
			clearContents(of: client)
		}
	}

	func destroyInputHistory(for item: IRCTreeItem) {
		inputHistoryManager().destroy(item)
	}

	func notifyAllViewsAppearanceDidChange() {
		for client in world?.clientList ?? [] {
			logControllers.existingController(for: client)?
				.reloadTheme()

			for channel in client.channelList {
				logControllers.existingController(for: channel)?
					.reloadTheme()
			}
		}
	}
}

// MARK: - Log controller lookup

extension MainWindow {
	/// The view controller drawing `item`, if the window has made one.
	func viewController(for item: IRCTreeItem?) -> LogController? {
		guard let item else { return nil }
		return logControllers.existingController(for: item)
	}
}

extension IRCTreeItem {
	/** The view this item is drawn into, if a window has made one.

	 This reads the weak seam the registry installed rather than a property the
	 item owns, so it is `nil` for an item no window is showing — a client in a
	 test, or one whose registry entry has already been dropped. */
	var logController: LogController? {
		presentation as? LogController
	}
}

// MARK: - Item presentation

/** A log controller is the view a tree item is drawn into. Every requirement
 already existed on the class; the protocol is what lets the IRC layer hold one
 without depending on the concrete `LogController`. */
extension LogController: TreeItemPresentation {
	public nonisolated var presentationIdentifier: String { // nonisolated: pure
		uniqueIdentifier
	}

	public func lastPrintedLine() -> LogLine? {
		lastLine()
	}
}
