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
				// Automatic placement keeps the filter in the sidebar toolbar.
				.toolbar {
					if columns.isSidebarVisible {
						ToolbarItem(placement: .automatic) {
							sidebarFilterMenu
						}
					}
				}
			} detail: {
				GeometryReader { _ in
					VStack(spacing: 0) {
						if let connection = chrome.connection {
							MainWindowConnectionRow(presentation: connection) { action in
								connection.perform(action, in: columns.window, commands: commands)
							}
						}
						MainWindowConversation(columns: columns, inputContentView: inputContentView)
					}
					.frame(minWidth: MainWindowConstants.conversationMinimumWidth, maxWidth: .infinity, maxHeight: .infinity)
				}
				.background(columns.conversationBackground.ignoresSafeArea(.container, edges: .top))
				.inspector(isPresented: memberListVisibility) {
					MemberListView(model: memberList, redirectTyping: redirectTyping)
						.inspectorColumnWidth(
							min: MemberListLayout.minimumWidth,
							ideal: CGFloat(SettingsKeys.MainWindow.memberListWidth.value),
							max: MemberListLayout.maximumWidth
						)
						.onGeometryChange(for: CGFloat.self) { geometry in
							geometry.size.width.rounded()
						} action: { width in
							let key = SettingsKeys.MainWindow.memberListWidth
							guard key.accepts(Double(width)), key.value != Double(width) else { return }
							key.value = Double(width)
						}
				}
			}
			.navigationSplitViewStyle(.balanced)
			// Attach search to the split view to place it in the window toolbar.
			.searchable(
				text: $sidebar.filterText,
				placement: .toolbar,
				prompt: Text(String(localized: .MainWindow.filterSidebar))
			)
			.searchFocused($isSearchFieldFocused)
			// The window also hides hosted AppKit views and clears their focus;
			// these SwiftUI modifiers alone do not remove them from navigation.
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
			// NavigationSplitView supplies the sidebar toggle.
			ToolbarItem(placement: .primaryAction) {
				// Keep the button visible so selection changes preserve toolbar layout.
				Button(
					MenuCommand.memberListTitle(isVisible: columns.isMemberListVisible),
					systemImage: columns.isMemberListVisible ? "sidebar.squares.trailing" : "sidebar.trailing"
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
		.sheet(item: inputPrompt) { prompt in
			InputPromptView(
				presentation: prompt,
				submit: {
					sheets.completeInputPrompt(.submitted(prompt.value), for: prompt)
				},
				cancel: {
					sheets.completeInputPrompt(.cancelled, for: prompt)
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

	private var memberListVisibility: Binding<Bool> {
		Binding(
			get: { columns.isMemberListVisible && !loadingScreen.viewIsVisible },
			set: { visible in
				guard !loadingScreen.viewIsVisible else { return }
				columns.setMemberListVisible(visible)
			}
		)
	}

	private var inputPrompt: Binding<InputPromptPresentation?> {
		let presentation = sheets.inputPrompt
		return Binding(
			get: { sheets.inputPrompt },
			set: { value in
				if value == nil, let presentation {
					sheets.completeInputPrompt(.cancelled, for: presentation)
				}
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
