/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
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

/** The menus themselves, and the AppKit delegate protocol that reaches them.

 Commands live on ``MenuActionController``. The menu items target it directly,
 so a command is one `@objc` method rather than a forwarder, an enum case and a
 switch arm. AppKit asks an item's target to validate it, so validation lives
 there too. What is left here is what only a menu controller can be. That is
 the menus AppKit pops up, the delegate callbacks it sends, the world's
 notification that the tree changed, and the seam the protocol layer raises
 sheets through. */
@MainActor
final class MenuController: NSObject, NSMenuDelegate {
	var channelViewChannelNameMenu = NSMenu()
	var channelViewGeneralMenu = NSMenu()
	var channelViewURLMenu = NSMenu()
	var dockMenu = NSMenu()
	var mainMenuNavigationChannelListMenu = NSMenu()
	var mainMenuChannelMenu = NSMenu()
	var mainMenuQueryMenu = NSMenu()
	var mainMenuChannelMenuItem: NSMenuItem?
	var mainMenuQueryMenuItem: NSMenuItem?
	var mainMenuServerMenuItem: NSMenuItem?
	var mainMenuFormatMenuItem: NSMenuItem?
	var serverListNoSelectionMenu = NSMenu()
	var userControlMenu = NSMenu()
	var muteNotificationsDockMenuItem: NSMenuItem?
	var muteNotificationsFileMenuItem: NSMenuItem?
	var muteNotificationsSoundsDockMenuItem: NSMenuItem?
	var muteNotificationsSoundsFileMenuItem: NSMenuItem?

	let actionCoordinator = MenuActionController()

	override init() {
		super.init()
		actionCoordinator.menuController = self
		MenuFactory.install(on: self)
	}

	func prepareInitialState() {
		actionCoordinator.prepareInitialState()
	}

	func prepareForApplicationTermination() {
		actionCoordinator.prepareForApplicationTermination()
	}

	func menuWillOpen(_ menu: NSMenu) {
		actionCoordinator.menuWillOpen(menu)
	}

	func menuDidClose(_ menu: NSMenu) {
		actionCoordinator.menuDidClose(menu)
	}
}

/** The menus the connection tree feeds. The world tells the controller when the
 shape of that tree changed rather than being called into. */
extension MenuController: ClientDirectoryObserver {
	func worldNavigationListDidChange(_: ClientDirectory) {
		actionCoordinator.populateNavigationChannelList()
	}

	func worldPreferencesDidChange(_: ClientDirectory) {
		actionCoordinator.preferencesChanged()
	}
}

/// The sheets the IRC layer raises, and the one folder it asks to be shown.
extension MenuController: ClientMenuPresenting {
	func revealInFinder(_ url: URL) {
		NSWorkspace.shared.open(url)
	}

	func toggleMuteOnNotificationSoundsShortcut(on muted: Bool) {
		actionCoordinator.setNotificationSoundsMuted(muted)
	}

	func showServerPropertiesSheet(for client: Client, selection: ServerPropertiesDestination) {
		actionCoordinator.showServerProperties(for: client, selection: selection)
	}

	func showNicknameColorSheet(forNickname nickname: String) {
		actionCoordinator.showNicknameColorSheet(for: nickname)
	}

	func openAcknowledgements(_ sender: Any?) {
		actionCoordinator.openAcknowledgements(sender)
	}

	func navigateToTreeItem(at url: URL) {
		actionCoordinator.navigateToTreeItem(at: url)
	}
}
