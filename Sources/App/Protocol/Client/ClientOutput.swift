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

import Foundation

/// Where a menu asks ``ServerPropertiesSheet`` to open, and what it opens
/// there with. The payloads used to travel beside the case as an `Any?` the
/// sheet cast back.
enum ServerPropertiesDestination {
	case `default`
	case addressBook
	/// A new ignore entry, pre-filled with the hostmask `/ignore` collected.
	case newIgnoreEntry(hostmask: String?)
	/// The address book entry the member-list menu asked to edit.
	case editIgnoreEntry(AddressBookEntry)
}

/** The view a single tree item is drawn into, as the protocol layer sees it.

 The item holds this weakly and does not create it: the main window's log
 controller registry owns the controller and installs itself here. When there is
 no window — tests, teardown — the reference is simply `nil` and printing is a
 no-op, which is what the force-unwrapped `viewController` property could not
 express. */
@MainActor
protocol TreeItemPresentation: AnyObject {
	/** Main actor: the only readers are the two termination logs
	 (`Channel.prepareForApplicationTermination`, its client's counterpart),
	 which already run there, so the identifier never leaves the main actor. */
	var presentationIdentifier: String { get }

	func print(_ logLine: LogLine, completionBlock: LogControllerPrintOperationCompletion?)
	/* Main actor: the newest printed line is the controller's own state, and
	 both callers (`Channel.lastLine`, `IRCClient.lastLine`) are already
	 there. */
	func lastPrintedLine() -> LogLine?
	func lastRenderedLineDate() -> Date?
	/** The newest line a person wrote that this view knows about, ignoring the
	 events the client narrates — a join, a mode, a topic. A line printed in this
	 turn counts, whether or not it has rendered yet.

	 A received read marker is answered against this: the burst a join prints is
	 stamped now, and none of it is news the badge should count. */
	func newestConversationLineDate() -> Date?
	/// How many of the view's conversation lines are newer than `date`, which is
	/// how many messages a read marker placed at `date` leaves unread.
	func conversationLineCount(after date: Date) -> Int
	func setTopic(_ topic: String?)

	func mark()
	func mark(at date: Date)
	func noteReaction(_ emoji: String, fromNickname nickname: String, toMessageIdentifier identifier: String)
	func updateDeliveryState(
		forLineNumber lineNumber: String,
		state: LogLineDeliveryState,
		messageIdentifier: String?,
		reason: String?
	)
	func prependHistoricLogLines(_ logLines: [LogLine])

	func tearDown(_ reason: TreeItemTeardown)
}

extension TreeItemPresentation {
	func lastRenderedLineDate() -> Date? {
		lastPrintedLine()?.receivedAt
	}

	/// A presentation that keeps no history of its own answers from the last line
	/// it printed, which is a conversation line or nothing.
	func newestConversationLineDate() -> Date? {
		guard let logLine = lastPrintedLine(), logLine.lineType.isConversation else { return nil }

		return logLine.receivedAt
	}

	func conversationLineCount(after date: Date) -> Int {
		newestConversationLineDate().map { $0 > date } == true ? 1 : 0
	}
}

/// Why a tree item's view is being torn down. One question the conformer
/// answers once, rather than three protocol members a caller has to match up
/// with the `preservingLocalData` flag elsewhere.
enum TreeItemTeardown {
	/// The application is quitting. The transcript is flushed and its historic
	/// log closed; nothing is deleted.
	case applicationTermination
	/// The item is going away but is expected back — a transfer, an import —
	/// so its historic log stays where it is.
	case preservingRemoval
	/// The item is going away for good, and its historic log goes with it.
	case permanentRemoval
}

/** The window-side work the protocol layer asks for: selection, redraws, titles
 and the member list. Implemented by the main window; absent in tests. */
@MainActor
protocol ClientOutput: AnyObject {
	// MARK: Selection

	var selectedItem: TreeItem? { get }
	var selectedClient: IRCClient? { get }
	var selectedChannel: Channel? { get }
	func selectedChannel(on client: IRCClient) -> Channel?
	func select(_ item: TreeItem?)
	func isItemSelected(_ item: TreeItem?) -> Bool
	func isItemVisible(_ item: TreeItem) -> Bool

	var isKeyWindow: Bool { get }
	var isMainWindow: Bool { get }
	/// Puts a sheet in front of the user. The protocol layer says what to ask;
	/// what the sheet hangs from is the window layer's business, and no
	/// `NSWindow` crosses back.
	func presentAlertSheet(_ request: AlertRequest, completion: @escaping AlertCompletion)
	/** Asks a yes/no question and blocks until the user answers, reporting
	 `true` for the default button.

	 The two call sites need the answer before they can decide whether to keep
	 going. With no window to ask in, the answer is the default one, which is
	 also what an already-suppressed alert reports. */
	func confirmModally(_ request: AlertRequest) -> Bool
	/// Closes every sheet the window is showing on this client's behalf.
	func closeSheets(for client: IRCClient)

	// MARK: Access lists

	/** A `+b`/`+e`/`+I`/`+q` list entry arrived from the server.

	 The connection, the channel and the mode letter all travel with the mask
	 because a window is open on one list of one channel: this seam is shared
	 with the transcript and is one object for every connection, so an entry
	 routed to whichever list happened to be frontmost put another channel's bans
	 in it. The receiver answers `false` for an entry that is not its own, and the
	 protocol layer prints it into the transcript instead.

	 `true` when a window is showing that list and took the entry, in which case
	 the protocol layer does not also print it. */
	func accessListEntryReceived(
		for client: IRCClient,
		inChannelNamed channelName: String,
		modeSymbol: String,
		mask: String,
		setBy author: String?,
		creationDate date: Date?
	) -> Bool
	/// The end of such a list. `true` when a window showing that list took it.
	func accessListFinished(for client: IRCClient, inChannelNamed channelName: String, modeSymbol: String) -> Bool
	/// Dismisses whatever sheet is scoped to a channel that is going away. The
	/// protocol layer knows the channel is gone; which sheets were hanging off
	/// it is the window layer's business.
	func closeSheets(forChannelId channelId: String)
	/// Offers a freshly logged highlight to a highlight list that happens to be
	/// open for the same client, so the list does not have to be reopened to
	/// show it. A no-op when none is open.
	func highlightWasLogged(_ entry: HighlightLogEntry)

	// MARK: Server list

	func reloadTreeItem(_ item: TreeItem)
	func reloadTreeGroup(_ item: TreeItem)
	/// Reloads a client and its children in place, keeping the selection.
	func reloadServerListItems(for client: IRCClient)
	func refreshMessageCount(for item: TreeItem)

	// MARK: Titles and chrome

	func updateTitle(for item: TreeItem)
	func updateTitle()
	func updateDrawingForUserInUserList(_ user: User)

	// MARK: Member list

	func assignMemberList(to channel: Channel)
	func updateMemberListVisibilityForSelection()

	// MARK: Views

	func clearContents(of item: TreeItem)
	func destroyInputHistory(for item: TreeItem)
	/// Tells every view that the window's appearance changed.
	func notifyAllViewsAppearanceDidChange()
}

/** The menus the protocol layer raises. Kept apart from `ClientOutput` because
 the menu controller, not the window, owns them. */
@MainActor
protocol ClientMenuPresenting: AnyObject {
	func toggleMuteOnNotificationSoundsShortcut(on muted: Bool)
	func showServerPropertiesSheet(for client: IRCClient, selection: ServerPropertiesDestination)
	func showNicknameColorSheet(forNickname nickname: String)
	func openAcknowledgements(_ sender: Any?)
	func navigateToTreeItem(at url: URL)
	/// Reveals a folder of the application's in the Finder. What "reveal" means
	/// is the app layer's business; the protocol layer only knows the folder.
	func revealInFinder(_ url: URL)
}

/** Application-wide state the protocol layer branches on. A separate seam from
 the window so that a client can be built without one. */
@MainActor
protocol ClientApplicationState: AnyObject {
	var ghostModeIsOn: Bool { get }
	var applicationIsTerminating: Bool { get }
	/// Decremented by each client as it finishes its termination work.
	func noteClientDidFinishTerminating()
}
