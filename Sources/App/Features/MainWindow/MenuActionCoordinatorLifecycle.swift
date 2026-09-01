/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2020 Codeux Software, LLC & respective contributors.
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

import AppKit

enum MenuLifecyclePolicy {
	static func shouldResetSelectionAfterMenuCloses(performedAction: Bool) -> Bool {
		performedAction == false
	}
}

@MainActor
public extension MenuActionCoordinator {
	func prepareInitialState() {
		guard let menuController else {
			return
		}

		if Preferences.Notifications.soundIsMuted.value {
			menuController.muteNotificationsSoundsDockMenuItem?.state = .on
			menuController.muteNotificationsSoundsFileMenuItem?.state = .on
		}

		menuController.channelViewGeneralMenu.item(for: .webChannelMenu)?.submenu =
			menuController.mainMenuChannelMenu.copy() as? NSMenu

		SharedApplication.sharedFileTransferCenter().startUsingDownloadDestinationURL()
		applyMenuSymbols()

		notifications.observe(NSMenu.willSendActionNotification) { [weak self] notification in
			self?.menuItemWillPerformAction(notification)
		}
		notifications.observe(NSMenu.didSendActionNotification) { [weak self] notification in
			self?.menuItemDidPerformAction(notification)
		}
		notifications.observe(.mainWindowSelectionChanged) { [weak self] notification in
			self?.mainWindowSelectionChanged(notification)
		}

		// The first selection is already in place by the time the menu is built.
		attachChannelMenu(to: menuController.mainMenuChannelMenuItem)
		attachQueryMenu(to: menuController.mainMenuQueryMenuItem)
	}

	func prepareForApplicationTermination() {
		SharedApplication.sharedFileTransferCenter().prepareForApplicationTermination()
	}

	func preferencesChanged() {
		SharedApplication.sharedFileTransferCenter().clearIPAddress()
	}

	func menuWillOpen(_: NSMenu) {
		menuIsOpen = true
		pointedClient = mainWindow.selectedClient
		pointedChannel = mainWindow.selectedChannel
		menuPerformedActionLastOpen = false
	}

	func menuDidClose(_: NSMenu) {
		menuIsOpen = false

		// AppKit closes the menu before it sends the selected item's action.
		// Deferring preserves the click-time selection until that action runs.
		DispatchQueue.main.async { [weak self] in
			guard let self,
			      MenuLifecyclePolicy.shouldResetSelectionAfterMenuCloses(
			      	performedAction: self.menuPerformedActionLastOpen
			      )
			else {
				return
			}
			resetSelectedItems()
		}
	}

	func resetSelectedItems() {
		pointedClient = nil
		pointedChannel = nil
	}

	func objcSelectedClient() -> IRCClient? {
		selectedClient
	}

	func objcSelectedChannel() -> IRCChannel? {
		selectedChannel
	}

	func objcSelectedViewController() -> LogController? {
		selectedChannel?.logController ?? selectedClient?.logController
	}

	func objcSelectedViewControllerBackingView() -> LogView? {
		objcSelectedViewController()?.backingView
	}

	private func applyMenuSymbols() {
		guard let menuController else {
			return
		}

		let menus = [
			NSApp.mainMenu,
			menuController.channelViewChannelNameMenu,
			menuController.channelViewGeneralMenu,
			menuController.channelViewURLMenu,
			menuController.dockMenu,
			menuController.mainMenuChannelMenu,
			menuController.mainMenuQueryMenu,
			menuController.mainMenuNavigationChannelListMenu,
			menuController.mainWindowSegmentedControllerCellMenu,
			menuController.serverListNoSelectionMenu,
			menuController.userControlMenu,
		]

		for menu in menus {
			MenuPresentation.apply(to: menu)
		}
	}

	private func mainWindowSelectionChanged(_: Notification) {
		if menuIsOpen == false {
			resetSelectedItems()
		}

		attachChannelMenu(to: menuController?.mainMenuChannelMenuItem)
		attachQueryMenu(to: menuController?.mainMenuQueryMenuItem)

		menuController?.mainMenuChannelMenuItem?.submenu?.update()
		menuController?.mainMenuQueryMenuItem?.submenu?.update()
	}

	private func menuItemWillPerformAction(_ notification: Notification) {
		guard notificationMenuItem(notification)?.target === menuController else {
			return
		}
		menuPerformedActionLastOpen = true
	}

	private func menuItemDidPerformAction(_ notification: Notification) {
		guard notificationMenuItem(notification)?.target === menuController else {
			return
		}
		resetSelectedItems()
	}

	private func notificationMenuItem(_ notification: Notification) -> NSMenuItem? {
		notification.userInfo?["MenuItem"] as? NSMenuItem
	}
}
