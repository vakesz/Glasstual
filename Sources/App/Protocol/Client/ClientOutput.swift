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

// AppKit: `alertPresentationWindow` hands the window layer's window back for a
// sheet; nothing else here touches AppKit.
import AppKit

/** The view a single tree item is drawn into, as the protocol layer sees it.

 The item holds this weakly and does not create it: the main window's log
 controller registry owns the controller and installs itself here. When there is
 no window — tests, teardown — the reference is simply `nil` and printing is a
 no-op, which is what the force-unwrapped `viewController` property could not
 express. */
@MainActor
protocol TreeItemPresentation: AnyObject {
	nonisolated var presentationIdentifier: String { get } // nonisolated: pure

	func print(_ logLine: LogLine, completionBlock: LogControllerPrintOperationCompletion?)
	/* Main actor: the newest printed line is the controller's own state, and
	 both callers (`IRCChannel.lastLine`, `IRCClient.lastLine`) are already
	 there. */
	func lastPrintedLine() -> LogLine?
	nonisolated func setTopic(_ topic: String?) // nonisolated: pure

	func mark()
	func mark(at date: Date)
	func noteReaction(_ emoji: String, fromNickname nickname: String, toMessageIdentifier identifier: String)
	func prependHistoricLogLines(_ logLines: [LogLine])
	func evaluateFunction(_ function: String, withArguments arguments: [Any]?, onQueue: Bool)

	func prepareForPermanentDestruction()
	func prepareForApplicationTermination()
}

/** The window-side work the protocol layer asks for: selection, redraws, titles
 and the member list. Implemented by the main window; absent in tests. */
@MainActor
protocol ClientOutput: AnyObject {
	// MARK: Selection

	var selectedItem: IRCTreeItem? { get }
	var selectedClient: IRCClient? { get }
	var selectedChannel: IRCChannel? { get }
	func selectedChannel(on client: IRCClient) -> IRCChannel?
	func selectItem(_ item: IRCTreeItem)
	func isItemSelectedInWindow(_ item: IRCTreeItem) -> Bool
	func isItemVisible(_ item: IRCTreeItem) -> Bool

	var windowIsKey: Bool { get }
	var windowIsMain: Bool { get }
	/// The window a sheet raised by the protocol layer should hang from.
	var alertPresentationWindow: NSWindow? { get }

	// MARK: Server list

	func reloadTreeItem(_ item: IRCTreeItem)
	func reloadTreeGroup(_ item: IRCTreeItem)
	/// Reloads a client and its children in place, keeping the selection.
	func reloadServerListItems(for client: IRCClient)
	func refreshMessageCount(for item: IRCTreeItem)

	// MARK: Titles and chrome

	func updateTitle(for item: IRCTreeItem)
	func updateTitle()
	func updateDrawingForUser(_ user: User)

	// MARK: Member list

	/// `false` when there is no member list to update, in which case
	/// `endMemberListUpdates()` must not be called.
	func beginMemberListUpdates() -> Bool
	func endMemberListUpdates()
	func refreshMemberListDrawing(forMemberAt index: Int)
	func assignMemberList(to channel: IRCChannel)
	func updateMemberListVisibilityForSelection()

	// MARK: Views

	func clearContents(of item: IRCTreeItem)
	func destroyInputHistory(for item: IRCTreeItem)
	func evaluateFunctionOnAllViews(_ function: String, arguments: [Any]?, onQueue: Bool)
	/// Tells every view that the window's appearance changed.
	func notifyAllViewsAppearanceDidChange()
}

/** The menus the protocol layer raises. Kept apart from `ClientOutput` because
 the menu controller, not the window, owns them. */
@MainActor
protocol ClientMenuPresenting: AnyObject {
	func toggleMuteOnNotificationSoundsShortcut(on muted: Bool)
	func showServerPropertiesSheet(for client: IRCClient, selection: UInt, context: Any?)
	func showNicknameColorSheet(forNickname nickname: String)
	func openAcknowledgements(_ sender: Any?)
	func navigateToTreeItem(at url: URL)
	func connectToGlasstualHelpChannel(_ sender: Any?)
	func connectToGlasstualTestingChannel(_ sender: Any?)
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
