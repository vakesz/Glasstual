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
import os

private let menuControllerLogger = Logger(
	subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
	category: "MenuController"
)

@MainActor
@objc(TXMenuController)
public final class TXMenuController: NSObject, NSMenuDelegate, NSMenuItemValidation {
	@IBOutlet public var channelViewChannelNameMenu: NSMenu!
	@IBOutlet public var channelViewGeneralMenu: NSMenu!
	@IBOutlet public var channelViewURLMenu: NSMenu!
	@IBOutlet public var dockMenu: NSMenu!
	@IBOutlet public var mainMenuNavigationChannelListMenu: NSMenu!
	@IBOutlet public var mainMenuChannelMenu: NSMenu!
	@IBOutlet public var mainMenuQueryMenu: NSMenu!
	@IBOutlet public var mainMenuChannelMenuItem: NSMenuItem!
	@IBOutlet public var mainMenuQueryMenuItem: NSMenuItem!
	@IBOutlet public var mainMenuServerMenuItem: NSMenuItem!
	@IBOutlet @objc(mainWindowSegmentedControllerCellMenu)
	private var segmentedControllerMenuOutlet: NSMenu!
	@IBOutlet public var serverListNoSelectionMenu: NSMenu!
	@IBOutlet public var userControlMenu: NSMenu!
	@IBOutlet public var muteNotificationsDockMenuItem: NSMenuItem?
	@IBOutlet public var muteNotificationsFileMenuItem: NSMenuItem?
	@IBOutlet public var muteNotificationsSoundsDockMenuItem: NSMenuItem?
	@IBOutlet public var muteNotificationsSoundsFileMenuItem: NSMenuItem?

	public var pointedNickname: String?
	/** Created on first use rather than in prepareInitialState(): menu
	 validation can run before the main window finishes loading (a theme-load
	 alert during launch is enough), and an unset coordinator crashed there. */
	lazy var actionCoordinator = MenuActionCoordinator(menuController: self)

	public var mainWindowSegmentedControllerCellMenu: NSMenu {
		segmentedControllerMenuOutlet
	}

	public func prepareInitialState() {
		actionCoordinator.prepareInitialState()
	}

	public func applySymbols(to menu: NSMenu?) {
		MenuPresentation.apply(to: menu)
	}

	public func prepareForApplicationTermination() {
		menuControllerLogger.debug("Preparing menu controller")
		actionCoordinator.prepareForApplicationTermination()
	}

	public func preferencesChanged() {
		actionCoordinator.preferencesChanged()
	}

	public func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
		actionCoordinator.validate(menuItem)
	}

	public func menuWillOpen(_ menu: NSMenu) {
		actionCoordinator.menuWillOpen(menu)
	}

	public func menuDidClose(_ menu: NSMenu) {
		actionCoordinator.menuDidClose(menu)
	}

	public func resetSelectedItems() {
		actionCoordinator.resetSelectedItems()
	}

	public var selectedClient: IRCClient? {
		actionCoordinator.selectedClient
	}

	public var selectedChannel: IRCChannel? {
		actionCoordinator.selectedChannel
	}

	public var selectedViewController: LogController? {
		actionCoordinator.objcSelectedViewController()
	}

	public var selectedViewControllerBackingView: LogView? {
		actionCoordinator.objcSelectedViewControllerBackingView()
	}

	public func checkSelectedMembers(_ sender: Any) -> Bool {
		selectedMembers(sender).isEmpty == false
	}

	public func selectedMembers(_ sender: Any) -> [ChannelUser] {
		actionCoordinator.selectedMembers(for: sender)
	}

	public func selectedMembersNicknames(_ sender: Any) -> [String] {
		actionCoordinator.selectedNicknames(for: sender)
	}

	public func deselectMembers(_ sender: Any) {
		actionCoordinator.deselectMembers(for: sender)
	}
}

/** The menus the connection tree feeds. The world tells the controller when the
 shape of that tree changed rather than being called into. */
extension TXMenuController: WorldObserver {
	func worldNavigationListDidChange(_: IRCWorld) {
		populateNavigationChannelList()
	}

	func worldPreferencesDidChange(_: IRCWorld) {
		preferencesChanged()
	}
}

/// The sheets the IRC layer raises. Every requirement already existed.
extension TXMenuController: ClientMenuPresenting {}
