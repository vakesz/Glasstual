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
	/// Routes sidebar and connection actions through the native menu commands.
	let commands: MenuActionController?

	@FocusState private var isSearchFieldFocused: Bool
	/// The restored column widths, read once. An ideal that tracks the live
	/// value re-proposes the column mid-drag, so the divider springs back.
	@State private var sidebarIdealWidth = CGFloat(SettingsKeys.MainWindow.sidebarWidth.value)
	@State private var memberListIdealWidth = CGFloat(SettingsKeys.MainWindow.memberListWidth.value)
	@State private var sidebarWidthWriter = ColumnWidthWriter(SettingsKeys.MainWindow.sidebarWidth)
	@State private var memberListWidthWriter = ColumnWidthWriter(SettingsKeys.MainWindow.memberListWidth)
	/// The window's content width, which bounds what the columns may take.
	@State private var contentWidth = MainWindowConstants.minimumContentSize.width

	var body: some View {
		NavigationSplitView(columnVisibility: sidebarVisibility) {
			MainWindowSidebar(sidebar: sidebar, redirectTyping: redirectTyping)
				/* The width modifiers have to stay outermost: wrapped in
				 `onGeometryChange`, the split view no longer sees them and the
				 columns open at SwiftUI's own default widths. */
				.onGeometryChange(for: CGFloat.self) { geometry in
					geometry.size.width.rounded()
				} action: { width in
					// A closing column passes through widths nobody chose.
					guard columns.isSidebarVisible else { return }
					columns.recordSidebarWidth(width)
					sidebarWidthWriter.record(width)
				}
				.navigationSplitViewColumnWidth(
					min: MainWindowConstants.sidebarMinimumWidth,
					ideal: min(sidebarIdealWidth, sidebarMaximumWidth),
					max: sidebarMaximumWidth
				)
				/* Automatic placement keeps both in the sidebar's part of the
				 toolbar: adding a server is about the list beneath them. The
				 File menu offers Add Server as well. */
				.toolbar {
					if columns.isSidebarVisible {
						ToolbarItemGroup(placement: .automatic) {
							sidebarFilterMenu
							addServerButton
						}
					}
				}
		} detail: {
			detailColumn
				/* The conversation's ground runs under the toolbar, so the
				 toolbar's Liquid Glass and scroll edge effect sit over the
				 transcript rather than over a band of their own. */
				.background(columns.conversationBackground.ignoresSafeArea(.container, edges: .top))
				.inspector(isPresented: memberListVisibility) {
					MemberListView(model: memberList, redirectTyping: redirectTyping)
						.onGeometryChange(for: CGFloat.self) { geometry in
							geometry.size.width.rounded()
						} action: { width in
							guard columns.isMemberListVisible else { return }
							columns.recordMemberListWidth(width)
							memberListWidthWriter.record(width)
						}
						.inspectorColumnWidth(
							min: MemberListLayout.minimumWidth,
							ideal: min(memberListIdealWidth, memberListMaximumWidth),
							max: memberListMaximumWidth
						)
				}
		}
		.navigationSplitViewStyle(.balanced)
		.onChange(of: columns.isMemberListVisible) { _, isVisible in
			if isVisible == false {
				columns.memberListDidClose()
			}
		}
		.onGeometryChange(for: CGFloat.self) { geometry in
			geometry.size.width.rounded()
		} action: { width in
			contentWidth = width
		}
		// The field filters the sidebar, so it stays on that column's background.
		.searchable(
			text: $sidebar.filterText,
			placement: .sidebar,
			prompt: Text(String(localized: .MainWindow.filterSidebar))
		)
		.searchFocused($isSearchFieldFocused)
		.onChange(of: loadingScreen.viewIsVisible, initial: true, conversationVisibilityChanged)
		.toolbar {
			/* NavigationSplitView supplies the sidebar toggle. The inspector's
			 toggle sits at the trailing edge, over the inspector, with one
			 symbol whatever its state: the title says what a click does. It
			 stays in the window toolbar so it is there to open the inspector
			 again once it is closed. */
			ToolbarItem(placement: .primaryAction) {
				Button(
					MenuCommand.memberListTitle(isVisible: columns.isMemberListVisible),
					systemImage: "sidebar.trailing"
				) {
					MainWindowColumnAnimation.run { columns.toggleMemberList() }
				}
				.disabled(columns.isMemberListAvailable == false)
				.help(MenuCommand.memberListTitle(isVisible: columns.isMemberListVisible))
			}
		}
		// Synchronize menu requests and user-driven search focus.
		.onChange(of: chrome.isSearchFieldFocused, adoptRequestedSearchFocus)
		.onChange(of: isSearchFieldFocused, reportSearchFocus)
		.fileImporter(
			isPresented: $sheets.isChoosingTransferFiles,
			allowedContentTypes: [.item],
			allowsMultipleSelection: true,
			onCompletion: sheets.completeTransferFileSelection
		)
		.settingsTransfer(sheets.settingsTransfer)
		.sheet(item: presentedSheet) { presentation in
			MainWindowSheetHost(model: sheets, presentation: presentation)
		}
	}

	/** The conversation, or the empty state that stands in for it. The
	 conversation stays in the hierarchy under the empty state, so its AppKit
	 views keep their place; the window hides them and takes their focus
	 (`setConversationObscured`), which SwiftUI's modifiers alone do not. */
	private var detailColumn: some View {
		ZStack {
			conversationDetail
				.disabled(loadingScreen.viewIsVisible)
				.accessibilityHidden(loadingScreen.viewIsVisible)
				.opacity(loadingScreen.viewIsVisible ? 0 : 1)

			if loadingScreen.viewIsVisible {
				MainWindowLoadingContent(model: loadingScreen)
					.transition(.opacity)
			}
		}
	}

	/// The connection row above the conversation. It fills the column from the
	/// top-leading corner, as the geometry reader it replaces did.
	private var conversationDetail: some View {
		VStack(spacing: 0) {
			if let connection = chrome.connection, connection.hasActions {
				MainWindowConnectionRow(presentation: connection) { action in
					connection.perform(action, in: columns.window, commands: commands)
				}
			}
			MainWindowConversation(columns: columns, inputContentView: inputContentView)
		}
		.frame(
			minWidth: MainWindowConstants.conversationMinimumWidth,
			maxWidth: .infinity,
			maxHeight: .infinity,
			alignment: .topLeading
		)
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
		}
		/* A plain toolbar symbol the system tints; the filled variant says a
		 filter is on, as Mail's does. */
		.menuIndicator(.hidden)
		.accessibilityValue(Text(sidebar.filter.title))
		.accessibilityIdentifier("sidebar-filter")
		.help(String(localized: .Sidebar.filterLabel))
	}

	private var addServerButton: some View {
		Button(String(localized: .MainWindow.toolbarAddServer), systemImage: "plus") {
			commands?.addServer(nil)
		}
		.help(String(localized: .MainWindow.toolbarAddServer))
		.accessibilityIdentifier(AccessibilityIdentifier.toolbarAddServer)
	}

	/** No column may be offered more than the window holds beside the
	 others: SwiftUI never narrows the window's other columns to make room,
	 and a split view that cannot fit ends AppKit's constraint passes with an
	 exception. */
	private var sidebarMaximumWidth: CGFloat {
		MainWindowConstants.sidebarMaximumWidth(inContentWidth: contentWidth, memberListOpen: columns.isMemberListVisible)
	}

	private var memberListMaximumWidth: CGFloat {
		columns.memberListMaximumWidth(inContentWidth: contentWidth)
	}

	private var sidebarVisibility: Binding<NavigationSplitViewVisibility> {
		Binding(
			get: { columns.isSidebarVisible ? .doubleColumn : .detailOnly },
			set: { columns.isSidebarVisible = $0 != .detailOnly }
		)
	}

	private var memberListVisibility: Binding<Bool> {
		Binding(
			get: { columns.isMemberListVisible && !loadingScreen.viewIsVisible },
			set: { visible in
				guard !loadingScreen.viewIsVisible else { return }
				columns.inspectorDidChangePresentation(visible)
			}
		)
	}

	/// Notify the sheet's owning session when SwiftUI dismisses it.
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

	private func conversationVisibilityChanged(_: Bool, _ isVisible: Bool) {
		columns.window?.setConversationObscured(isVisible)
	}

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
