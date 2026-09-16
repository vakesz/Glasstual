/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
import CocoaExtensions
import SwiftUI
import UniformTypeIdentifiers

struct MainWindowRootView: View {
	@Bindable var model: MainWindowPresentationModel
	@Bindable var loadingScreen: MainWindowLoadingScreen

	@Bindable var serverList: ServerList
	let memberList: MemberList
	let inputContentView: InputFieldContentView

	@FocusState private var isSearchFieldFocused: Bool
	@State private var memberListWidth = CGFloat(Preferences.MainWindow.memberListWidth.value)

	var body: some View {
		ZStack {
			NavigationSplitView(columnVisibility: serverListVisibility) {
				MainWindowSidebar(model: model, serverList: serverList, redirectTyping: redirectTyping)
					.navigationSplitViewColumnWidth(
						min: MainWindowConstants.serverListMinimumWidth,
						ideal: MainWindowConstants.serverListIdealWidth,
						max: MainWindowConstants.serverListMaximumWidth
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
					MainWindowConversation(model: model, inputContentView: inputContentView)
						.frame(
							minWidth: MainWindowConstants.conversationMinimumWidth,
							maxWidth: .infinity,
							maxHeight: .infinity
						)
					if model.isMemberListAvailable, model.isMemberListVisible {
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
				.background(model.conversationBackground.ignoresSafeArea(.container, edges: .top))
			}
			/* On the split view rather than on the sidebar: `.sidebar` placement
			 draws the field above the server list, and the window's toolbar is
			 where the user looks for it. */
			.searchable(
				text: $serverList.filterText,
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
					MenuCommand.memberListTitle(isVisible: model.isMemberListVisible),
					systemImage: model.isMemberListVisible ? "sidebar.squares.trailing" : "sidebar.trailing"
				) {
					toggleMemberList()
				}
				.disabled(model.isMemberListAvailable == false)
				.help(MenuCommand.memberListTitle(isVisible: model.isMemberListVisible))
			}
		}
		/* Two directions: the menu command sets the model's flag to move the
		 keyboard into the field, and the field reports back so the flag still
		 reads true when the user focused it themselves. */
		.onChange(of: model.isSearchFieldFocused, adoptRequestedSearchFocus)
		.onChange(of: isSearchFieldFocused, reportSearchFocus)
		.fileImporter(
			isPresented: $model.isChoosingTransferFiles,
			allowedContentTypes: [.item],
			allowsMultipleSelection: true,
			onCompletion: model.completeTransferFileSelection
		)
		.preferencesTransfer(model.preferencesTransfer)
		.sheet(item: $model.inputPrompt, onDismiss: model.inputPromptDidDismiss) { prompt in
			InputPromptView(
				presentation: prompt,
				submit: {
					model.completeInputPrompt(.submitted(prompt.value))
				},
				cancel: {
					model.completeInputPrompt(.cancelled)
				}
			)
		}
		.sheet(item: presentedSheet) { presentation in
			MainWindowSheetHost(model: model, presentation: presentation)
		}
	}

	private var serverListVisibility: Binding<NavigationSplitViewVisibility> {
		Binding(
			get: { model.isServerListVisible ? .doubleColumn : .detailOnly },
			set: { model.isServerListVisible = $0 != .detailOnly }
		)
	}

	/// Dismissing has to reach the session that raised the sheet, so the
	/// binding's write goes through the model rather than clearing the item.
	private var presentedSheet: Binding<MainWindowSheet?> {
		Binding(
			get: { model.presentedSheet },
			set: { presentation in
				if presentation == nil {
					model.dismissPresentedSheet()
				}
			}
		)
	}

	/** A pane sweeping across the window is exactly the motion Reduce Motion
	 asks an interface to drop, so the column simply appears instead. The state
	 change is the view's to animate: the model only records it. */
	private func toggleMemberList() {
		withAnimation(ReduceMotion.animation(.default)) {
			model.toggleMemberList()
		}
	}

	/// The loading screen covers the window, so the views under it give the
	/// keyboard back rather than staying reachable behind it.
	private func conversationVisibilityChanged(_: Bool, _ isVisible: Bool) {
		model.window?.setConversationObscured(isVisible)
	}

	/** Two directions: the menu command sets the model's flag to move the
	 keyboard into the field, and the field reports back so the flag still reads
	 true when the reader focused it themselves. */
	private func adoptRequestedSearchFocus(_: Bool, _ isFocused: Bool) {
		isSearchFieldFocused = isFocused
	}

	private func reportSearchFocus(_: Bool, _ isFocused: Bool) {
		model.isSearchFieldFocused = isFocused
	}

	private func redirectTyping(_ text: String) {
		let textView = inputContentView.textView
		textView.focus()
		textView.insertText(text, replacementRange: textView.selectedRange())
	}
}
