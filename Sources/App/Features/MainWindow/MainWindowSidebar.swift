// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import SwiftUI

/// The sidebar, and the two icon-only controls under it.
struct MainWindowSidebar: View {
	let columns: MainWindowColumnModel
	let chrome: MainWindowChrome
	@Bindable var sidebar: Sidebar
	/// The object the footer's menus send their commands to, handed in rather
	/// than reached for: the whole command graph behind a view model's property
	/// is a route from any subview to the application delegate.
	let commands: MenuActionController?
	let redirectTyping: (String) -> Void
	@State private var appearance = SidebarAppearance()

	var body: some View {
		VStack(spacing: 0) {
			SidebarView(model: sidebar, redirectTyping: redirectTyping)
			Divider()
			sidebarFooter
		}
		.background {
			SidebarBackgroundView(isOpaque: appearance.isOpaque)
				.ignoresSafeArea(.container, edges: .top)
		}
	}

	/** Two icon-only controls at the sidebar's foot.

	 The `plus` is Notes' New Folder button: a press adds a channel, a press and
	 hold offers the whole list. It used to be a plain menu with the indicator
	 hidden, which reads as an immediate action and then is not one. The
	 overflow menu keeps its indicator hidden -- `ellipsis.circle` already says
	 there is more behind it -- and neither icon is permanently dimmed any
	 longer: secondary foreground on a control that is not disabled reads as
	 disabled. */
	private var sidebarFooter: some View {
		HStack(spacing: UISpacing.tight) {
			Menu {
				Button(.MainWindow.menuServerAddServer, systemImage: "server.rack") {
					commands?.addServer(nil)
				}
				Button(.MainWindow.menuServerAddChannel, systemImage: "number") {
					commands?.addChannel(nil)
				}
			} label: {
				footerIcon("plus", titled: String(localized: .MainWindow.addServerOrChannel))
			} primaryAction: {
				commands?.addChannel(nil)
			}
			.sidebarFooterMenu()
			.help(String(localized: .MainWindow.addServerOrChannel))

			Spacer(minLength: UISpacing.regular)

			Menu {
				Button(String(localized: .MainWindow.markAllAsRead), systemImage: "checkmark.circle") {
					commands?.markAllAsRead(nil)
				}
				/* A mode is ticked while it is in force, which is what the
				 application menu and the Dock menu already do with it. Renaming
				 the item instead left one command with three names. */
				Toggle(.MainWindow.menuMuteNotifications, isOn: Binding(
					get: { chrome.areNotificationsDisabled },
					set: { _ in commands?.toggleMuteOnNotifications(nil) }
				))
				Divider()
				Button(.MainWindow.menuWindowAddressBook, systemImage: "person.crop.circle") {
					commands?.showAddressBook(nil)
				}
				Button(.MainWindow.menuWindowFileTransfers, systemImage: "arrow.down.circle") {
					commands?.showFileTransfersWindow(nil)
				}
				Divider()
				Button(
					MenuCommand.memberListTitle(isVisible: columns.isMemberListVisible),
					systemImage: columns.isMemberListVisible ? "sidebar.squares.trailing" : "sidebar.trailing"
				) {
					animatingColumnChange { columns.toggleMemberList() }
				}
				.disabled(columns.isMemberListAvailable == false)
				Button(String(localized: .MainWindow.toolbarInputBarAccessibilitySettings), systemImage: "gear") {
					commands?.showSettingsWindow(nil)
				}
			} label: {
				footerIcon("ellipsis.circle", titled: String(localized: .MainWindow.toolbarInputBarAccessibilityMore))
			}
			.sidebarFooterMenu()
			.menuIndicator(.hidden)
			.help(String(localized: .MainWindow.toolbarInputBarAccessibilityMore))
		}
		.padding(.horizontal, UISpacing.wide)
		.frame(height: MainWindowConstants.sidebarFooterHeight)
	}

	/// A bare `Image` carries no accessibility label, so VoiceOver announced
	/// the two always-visible sidebar controls as "plus, menu" and nothing at
	/// all. A `Label` keeps the name for assistive technology while drawing
	/// only the symbol.
	private func footerIcon(_ systemName: String, titled title: String) -> some View {
		Label(title, systemImage: systemName)
			.labelStyle(.iconOnly)
			.font(.callout.weight(.medium))
			.frame(width: MainWindowConstants.footerIconSize, height: MainWindowConstants.footerIconSize)
			.contentShape(Rectangle())
	}
}

private extension View {
	/// A footer control: a bare icon as the label, with the accessory bar's
	/// hover and pressed treatment so it answers the pointer the way the rows
	/// above it do. The label style is left alone so the menu's own items keep
	/// their titles.
	func sidebarFooterMenu() -> some View {
		menuStyle(.button)
			.buttonStyle(.accessoryBar)
	}
}
