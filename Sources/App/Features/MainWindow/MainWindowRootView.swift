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
				// Automatic placement keeps this inside the sidebar; navigation placement moves it into the detail toolbar.
				.toolbar {
					if columns.isSidebarVisible {
						ToolbarItem(placement: .automatic) {
							sidebarFilterMenu
						}
					}
				}
			} detail: {
				GeometryReader { geometry in
					let railWidth = MainWindowMemberRail.effectiveWidth(preferred: memberListWidth, available: geometry.size.width)
					HStack(spacing: 0) {
						VStack(spacing: 0) {
							if let connection = chrome.connection {
								MainWindowConnectionRow(presentation: connection) { action in
									connection.perform(action, in: columns.window, commands: commands)
								}
							}
							MainWindowConversation(columns: columns, inputContentView: inputContentView)
						}
						.frame(maxWidth: .infinity, maxHeight: .infinity)
						if columns.isMemberListVisible, let width = railWidth {
							MemberListResizeHandle(width: Binding(
								get: { width }, set: { memberListWidth = $0 }
							))
							MemberListView(model: memberList, redirectTyping: redirectTyping)
								.frame(width: width)
						}
					}
				}
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

	private var sidebarFilterMenu: some View {
		Menu {
			Picker(.Sidebar.filterLabel, selection: $sidebar.filter) {
				ForEach(SidebarFilter.allCases) { filter in
					Text(filter.title).tag(filter)
				}
			}
			.pickerStyle(.inline)
		} label: {
			Label(
				.Sidebar.filterLabel,
				systemImage: sidebar.filter == .all ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill"
			)
			.labelStyle(.iconOnly)
			.foregroundStyle(sidebar.filter == .all ? Color.primary : Color.accentColor)
		}
		.menuStyle(.button)
		.menuIndicator(.hidden)
		.buttonBorderShape(.circle)
		.accessibilityValue(Text(sidebar.filter.title))
		.accessibilityIdentifier("sidebar-filter")
		.help(String(localized: .Sidebar.filterLabel))
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
