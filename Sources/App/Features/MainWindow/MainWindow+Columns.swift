// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import CocoaExtensions
import SwiftUI

/** The window's columns, and what covers them while there is nothing to show.

 The visibility itself is the presentation model's; these are the window-side
 entry points the menu bar and the IRC layer reach for, each wrapped in the one
 animation the columns share. */
extension MainWindow {
	func saveContentSplitViewState() {
		stateStore.saveLayout(columnModel.columnState)
	}

	func restoreSavedContentSplitViewState() {
		columnModel.restoreColumns(stateStore.loadLayout())
	}

	/** Stops the reader from narrowing the window past its open columns.

	 SwiftUI keeps each column's width while the window narrows. Columns wider
	 than the window would be laid out past its edges, and a split view that
	 cannot fit at all ends AppKit's constraint passes with an exception.
	 Opening columns are kept to what the window holds by the widths
	 `MainWindowRootView` offers them; this never resizes the window. */
	func updateMinimumContentSize() {
		// The setter raises the window's own minimum to the columns'.
		contentMinSize = MainWindowConstants.minimumContentSize
	}

	func toggleSidebarVisibility() {
		MainWindowColumnAnimation.run { columnModel.isSidebarVisible.toggle() }
	}

	/// The member list belongs beside a channel the connection has joined; the
	/// model derives the column's own visibility from that and from whether the
	/// reader has closed it.
	func updateMemberListVisibilityForSelection() {
		MainWindowColumnAnimation.run {
			columnModel.applyMemberListAvailability(
				selectedItem?.isChannel == true && selectedItem?.associatedSession?.isLoggedIn == true
			)
		}
	}

	func toggleMemberListVisibility() {
		MainWindowColumnAnimation.run { columnModel.toggleMemberList() }
	}

	/// Keep typing in the conversation when its focused member table disappears.
	func prepareToHideMemberList() {
		guard firstResponder is MemberListNativeTable else { return }
		inputContentView.textView.focus()
	}

	/** Hides the AppKit views under the loading overlay, or shows them again.

	 SwiftUI's `disabled` and `accessibilityHidden` stop at the representables,
	 so the message field and the transcript stayed in the key view loop and in
	 the accessibility tree under an overlay that covered them. A hidden view
	 is in neither. Nothing under the overlay may keep the keyboard either, so
	 a view that holds it gives it back to the window. */
	func setConversationObscured(_ isObscured: Bool) {
		if isObscured, firstResponder is NSView {
			makeFirstResponder(nil)
		}
		inputContentView.isHidden = isObscured
		columnModel.isConversationObscured = isObscured
	}

	/** Puts the loading screen into the state the chat session is in: waiting for the
	 configuration, offering to add the first server, or out of the way.

	 The answer is whether the window is showing conversations, which is what
	 decides whether the application may start connecting. */
	@discardableResult
	func reloadLoadingScreen() -> Bool {
		guard let chatSession else {
			loadingScreen.showProgressView(withReason: String(localized: .MainWindow.loadingConfiguration))
			return false
		}
		/* An import is replacing the chat session underneath: whatever the screen is
		 showing is what it keeps showing until that finishes. */
		guard chatSession.isImportingConfiguration == false else { return false }
		guard AppServices.delegate.applicationIsLaunched else {
			loadingScreen.showProgressView(withReason: String(localized: .MainWindow.loadingConfiguration))
			return false
		}
		guard chatSession.sessionCount > 0 else {
			loadingScreen.showNoServersView()
			return false
		}
		loadingScreen.hide()
		return true
	}
}
