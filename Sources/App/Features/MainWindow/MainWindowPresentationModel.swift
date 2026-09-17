// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
import Observation
import os
import SwiftUI

private let mainWindowPresentationLogger = Logger(
	subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
	category: "MainWindowPresentationModel"
)

@MainActor
@Observable
final class MainWindowPresentationModel {
	var isServerListVisible = true
	/// Whether the selection has a member list at all: a joined channel has
	/// one, a server row and a one-to-one conversation do not.
	private(set) var isMemberListAvailable = false
	/// Whether the column is showing. Derived, never set from outside: the
	/// member list shows while the selection has one and the reader has not
	/// closed it.
	private(set) var isMemberListVisible = true
	/** Whether the reader wants the member list beside a channel that has one.

	 The pane's own visibility cannot carry this: it is false for every server
	 row too, so restoring it would have closed the list for good the first
	 time the reader left a server selected. This used to live on `MemberList`
	 as `isHiddenByUser`, a second store of the same fact that six call sites
	 kept in step with this one. */
	private(set) var userPrefersMemberList = true
	var transcript: TranscriptView?
	/// Whether the loading overlay covers the conversation. The transcript
	/// host hides its AppKit view while it does.
	var isConversationObscured = false
	var appearanceRevision = 0
	var isChoosingTransferFiles = false
	let preferencesTransfer = MainWindowPreferencesTransferModel()
	var inputPrompt: InputPromptPresentation?
	/** Mirrors the toolbar search field's focus. The root view keeps it in step
	 with its `@FocusState` in both directions, so setting it is what moves the
	 keyboard into the field and clicking away is what clears it. */
	var isSearchFieldFocused = false
	/** Mirrors the notification controller's mute switch so the footer menu can
	 tick it. The controller is not observable and the switch is thrown from the
	 main menu as well, so the coordinator that owns the switch writes it here
	 whenever it changes. */
	var areNotificationsDisabled = false
	/// The outermost sheet the window is showing; each one holds whatever it
	/// raised on top of itself.
	private(set) var presentedSheet: MainWindowSheet?

	@ObservationIgnored weak var window: MainWindow?
	@ObservationIgnored private var transferFileSelection: (([URL]) -> Void)?

	func attach(to window: MainWindow) {
		precondition(self.window == nil || self.window === window)
		self.window = window
	}

	/// Puts the keyboard in the sidebar filter field, which now lives in the
	/// window toolbar. Channel Spotlight has a command of its own.
	func focusSearchField() {
		isSearchFieldFocused = true
	}

	/// The commands the sidebar's footer menus issue. They are the menu bar's
	/// commands, sent to the object that performs them, rather than eight
	/// methods on this model that only renamed them.
	var commands: MenuActionController? {
		AppServices.delegate.menuController
	}

	/** Applies a selection to the member-list column.

	 One derivation, so the two facts cannot disagree: the column is available
	 beside a joined channel, and it is open while it is available and the
	 reader has not closed it. */
	func applyMemberListAvailability(_ isAvailable: Bool) {
		isMemberListAvailable = isAvailable
		isMemberListVisible = isAvailable && userPrefersMemberList
	}

	/** The reader's own switch, from either menu or the toolbar.

	 Nothing happens where there is no member list to show: both menus disable
	 the command there, and a "Show Member List" that quietly recorded "hide it"
	 is what the guard is for. */
	func toggleMemberList() {
		guard isMemberListAvailable else { return }
		userPrefersMemberList.toggle()
		isMemberListVisible = userPrefersMemberList
	}

	/// Restores what the reader last left the columns at.
	func restoreColumns(_ state: MainWindowLayoutState) {
		isServerListVisible = state.isServerListVisible
		userPrefersMemberList = state.isMemberListVisible
		isMemberListVisible = state.isMemberListVisible
	}

	var columnState: MainWindowLayoutState {
		MainWindowLayoutState(
			isServerListVisible: isServerListVisible,
			isMemberListVisible: userPrefersMemberList
		)
	}

	func chooseTransferFiles(perform: @escaping ([URL]) -> Void) {
		transferFileSelection = perform
		isChoosingTransferFiles = true
	}

	func completeTransferFileSelection(_ result: Result<[URL], Error>) {
		defer { transferFileSelection = nil }
		switch result {
		case let .success(urls):
			transferFileSelection?(urls)
		case let .failure(error):
			mainWindowPresentationLogger.error("Choosing files to transfer failed: \(error)")
		}
	}

	func presentInputPrompt(
		_ request: InputPromptRequest,
		completion: @escaping @MainActor (InputPromptOutcome) -> Void
	) {
		inputPrompt?.finish(.cancelled)
		inputPrompt = InputPromptPresentation(request: request, completion: completion)
	}

	func completeInputPrompt(_ outcome: InputPromptOutcome) {
		guard let inputPrompt else { return }
		inputPrompt.finish(outcome)
		self.inputPrompt = nil
	}

	func inputPromptDidDismiss() {
		guard let inputPrompt else { return }
		inputPrompt.finish(.cancelled)
		self.inputPrompt = nil
	}

	/// Raises a sheet: the first one on the window, any after it on whichever
	/// sheet is innermost.
	func presentSheet(_ presentation: MainWindowSheet) {
		guard let innermost = presentedSheet?.chain.last else {
			presentedSheet = presentation
			return
		}
		innermost.child = presentation
	}

	func dismissSheet(ownedBy owner: AnyObject) {
		closeSheets { $0 === owner }
	}

	func dismissPresentedSheet() {
		dismiss(presentedSheet)
	}

	func closeSheets(where shouldClose: (AnyObject) -> Bool) {
		dismiss(presentedSheet?.chain.first { shouldClose($0.owner) })
	}

	/// Takes `presentation` down, and everything it raised with it.
	func dismiss(_ presentation: MainWindowSheet?) {
		guard let presentation else { return }
		if presentedSheet === presentation {
			presentedSheet = nil
		} else {
			presentedSheet?.chain.first { $0.child === presentation }?.child = nil
		}
		presentation.finish()
	}
}

extension MainWindowPresentationModel {
	/** The ground the sidebar and the conversation both paint.

	 `appearanceRevision` is read so a theme change redraws it: the colour comes
	 from the theme controller, which is not observable on its own. */
	var conversationBackground: Color {
		_ = appearanceRevision
		return Color(nsColor: AppServices.theme.backgroundColor)
	}
}
