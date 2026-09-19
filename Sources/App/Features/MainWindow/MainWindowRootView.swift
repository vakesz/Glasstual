// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import CocoaExtensions
import SwiftUI
import UniformTypeIdentifiers

struct MainWindowRootView: View {
	@Bindable var columns: MainWindowColumnModel
	@Bindable var sheets: MainWindowSheetModel
	let chrome: MainWindowChrome
	@Bindable var loadingScreen: MainWindowLoadingScreen

	@Bindable var sidebar: Sidebar
	let memberList: MemberList
	let inputContentView: InputFieldContentView
	/// Passed on to the sidebar's footer, which is the only part of the window
	/// that issues menu commands from SwiftUI.
	let commands: MenuActionController?

	@FocusState private var isSearchFieldFocused: Bool
	@State private var memberListWidth = CGFloat(SettingsKeys.MainWindow.memberListWidth.value)

	var body: some View {
		ZStack {
			NavigationSplitView(columnVisibility: sidebarVisibility) {
				MainWindowSidebar(
					columns: columns,
					chrome: chrome,
					sidebar: sidebar,
					commands: commands,
					redirectTyping: redirectTyping
				)
				.navigationSplitViewColumnWidth(
					min: MainWindowConstants.sidebarMinimumWidth,
					ideal: MainWindowConstants.sidebarIdealWidth,
					max: MainWindowConstants.sidebarMaximumWidth
				)
			} detail: {
				/* Beside the conversation, not in a split of its own, and not an
				 `.inspector` either.

				 An inspector -- like a second `HSplitView` pane -- inserts a pane
				 into the detail column, and the column then grows by the pane's
				 width instead of sharing its space: the columns spilled past the
				 window, or AppKit gave up after three hundred layout passes with
				 the transcript left at whatever width the loop was passing
				 through. What feeds that loop is still here: the transcript's
				 bottom inset is measured in AppKit from the floating input bar's
				 frame, so the detail column's width decides a value that moves a
				 view inside it. A stack changes nothing the split view measures,
				 so the divider carries its own drag -- with the pointer, keyboard
				 and reset behaviour an inspector's divider would have given it. */
				HStack(spacing: 0) {
					MainWindowConversation(columns: columns, inputContentView: inputContentView)
						.frame(
							minWidth: MainWindowConstants.conversationMinimumWidth,
							maxWidth: .infinity,
							maxHeight: .infinity
						)
					if columns.isMemberListAvailable, columns.isMemberListVisible {
						MemberListResizeHandle(width: $memberListWidth)
						/* The rows scroll up into the titlebar's safe area and
						 the system's soft edge effect is what keeps the toolbar
						 legible over them, so nothing here insets the list by
						 hand. The list paints no ground of its own; the column's
						 is the conversation's, so the divider is the only edge. */
						MemberListView(model: memberList, redirectTyping: redirectTyping)
							.scrollEdgeEffectStyle(.soft, for: .top)
							.frame(width: memberListWidth)
					}
				}
				/* One ground for both columns, up under the transparent titlebar.

				 Measured: the list's own scroll view runs the full height of the
				 window and insets its rows by the titlebar, while the transcript
				 is an `NSViewRepresentable` that SwiftUI lays out inside the safe
				 area. The two agree on where their content starts -- both at the
				 safe-area top -- and disagree only about the strip above it, so
				 each column painting its own ground left that strip in the theme
				 colour beside the list and in the window's colour beside the
				 transcript. A background changes nothing the split view measures,
				 which is what keeps this out of the layout loop the comment on
				 `conversation` describes; insetting the list to match the
				 transcript, or lifting the transcript out of the safe area, would
				 both put a column's own layout back into the column's insets. */
				.background(columns.conversationBackground.ignoresSafeArea(.container, edges: .top))
			}
			/* On the split view rather than on the sidebar: `.sidebar` placement
			 draws the field above the sidebar, and the window's toolbar is
			 where the user looks for it. */
			.searchable(
				text: $sidebar.filterText,
				placement: .toolbar,
				prompt: Text(String(localized: .MainWindow.filterSidebar))
			)
			.searchFocused($isSearchFieldFocused)
			/* Transparent is not gone. VoiceOver walked the invisible sidebar and
			 transcript, and `disabled` does not reach the AppKit views inside,
			 so Tab still reached the message field. The window hides those
			 views and takes the keyboard back from them; see
			 `MainWindow.setConversationObscured(_:)`. */
			.disabled(loadingScreen.viewIsVisible)
			.accessibilityHidden(loadingScreen.viewIsVisible)
			.opacity(loadingScreen.viewIsVisible ? 0 : 1)
			.onChange(of: loadingScreen.viewIsVisible, initial: true, conversationVisibilityChanged)

			if loadingScreen.viewIsVisible {
				MainWindowLoadingContent(model: loadingScreen)
					.transition(.opacity)
			}
		}
		.toolbar {
			/* No sidebar toggle is declared here: the split view contributes its
			 own where the system wants it, and re-declaring it only moved it. */
			ToolbarItem(placement: .primaryAction) {
				/* Declared whatever the selection is, and disabled where there
				 is no member list: a toolbar whose only button disappears on a
				 server row is a toolbar that changes shape as the reader moves
				 down the sidebar. The title says which way the press goes and
				 the symbol says which state the window is in, the way Mail's
				 sidebar toggle does: filled while the pane is showing. */
				Button(
					MenuCommand.memberListTitle(isVisible: columns.isMemberListVisible),
					systemImage: columns.isMemberListVisible ? "sidebar.squares.trailing" : "sidebar.trailing"
				) {
					animatingColumnChange { columns.toggleMemberList() }
				}
				.disabled(columns.isMemberListAvailable == false)
				.help(MenuCommand.memberListTitle(isVisible: columns.isMemberListVisible))
			}
		}
		/* Two directions: the menu command sets the model's flag to move the
		 keyboard into the field, and the field reports back so the flag still
		 reads true when the user focused it themselves. */
		.onChange(of: chrome.isSearchFieldFocused, adoptRequestedSearchFocus)
		.onChange(of: isSearchFieldFocused, reportSearchFocus)
		.fileImporter(
			isPresented: $sheets.isChoosingTransferFiles,
			allowedContentTypes: [.item],
			allowsMultipleSelection: true,
			onCompletion: sheets.completeTransferFileSelection
		)
		.settingsTransfer(sheets.settingsTransfer)
		.sheet(item: $sheets.inputPrompt, onDismiss: sheets.inputPromptDidDismiss) { prompt in
			InputPromptView(
				presentation: prompt,
				submit: {
					sheets.completeInputPrompt(.submitted(prompt.value))
				},
				cancel: {
					sheets.completeInputPrompt(.cancelled)
				}
			)
		}
		.sheet(item: presentedSheet) { presentation in
			MainWindowSheetHost(model: sheets, presentation: presentation)
		}
	}

	private var sidebarVisibility: Binding<NavigationSplitViewVisibility> {
		Binding(
			get: { columns.isSidebarVisible ? .doubleColumn : .detailOnly },
			set: { columns.isSidebarVisible = $0 != .detailOnly }
		)
	}

	/// Dismissing has to reach the session that raised the sheet, so the
	/// binding's write goes through the model rather than clearing the item.
	private var presentedSheet: Binding<MainWindowSheet?> {
		Binding(
			get: { sheets.presentedSheet },
			set: { presentation in
				if presentation == nil {
					sheets.dismissPresentedSheet()
				}
			}
		)
	}

	/// The loading screen covers the window, so the views under it give the
	/// keyboard back rather than staying reachable behind it.
	private func conversationVisibilityChanged(_: Bool, _ isVisible: Bool) {
		columns.window?.setConversationObscured(isVisible)
	}

	/** Two directions: the menu command sets the model's flag to move the
	 keyboard into the field, and the field reports back so the flag still reads
	 true when the reader focused it themselves. */
	private func adoptRequestedSearchFocus(_: Bool, _ isFocused: Bool) {
		isSearchFieldFocused = isFocused
	}

	private func reportSearchFocus(_: Bool, _ isFocused: Bool) {
		chrome.isSearchFieldFocused = isFocused
	}

	private func redirectTyping(_ text: String) {
		let textView = inputContentView.textView
		textView.focus()
		textView.insertText(text, replacementRange: textView.selectedRange())
	}
}
