/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
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
import CocoaExtensions

enum MenuWindowPolicy {
	static let alertSuppressionPrefix = Preferences.Families.alertSuppression.pattern

	static func nextAppearance(current: TXPreferredAppearance, systemIsDark: Bool) -> TXPreferredAppearance {
		switch current {
		case .inherited: systemIsDark ? .light : .dark
		case .light: .dark
		case .dark: .light
		@unknown default: .inherited
		}
	}

	static func channelsOrderedBeforeQueries(_ lhs: IRCChannel, _ rhs: IRCChannel) -> Bool {
		/* Both directions have to be answered. Without the second branch a
		 query and a channel compare as "unordered" one way and "ordered" the
		 other, which is not a strict weak ordering and lets sort(by:) produce
		 garbage. */
		if lhs.isChannel != rhs.isChannel {
			return lhs.isChannel
		}
		return lhs.name.lowercased().compare(rhs.name.lowercased()) == .orderedAscending
	}
}

@MainActor
public extension MenuActionCoordinator {
	@objc(performWindowAction:sender:)
	func performWindowAction(_ action: TXMenuWindowAction, sender: Any?) {
		switch action {
		case .close: closeWindow(sender)
		case .showMainWindow: mainWindow.makeKeyAndOrderFront(sender)
		case .centerMainWindow: mainWindow.ce_exactlyCenter()
		case .resetMainWindowFrame: resetMainWindowFrame(sender)
		case .sortChannelList: sortChannelList()
		case .markAllAsRead: mainWindow.markAllAsRead()
		case .importPreferences: PreferencesImportExport.import(in: mainWindow)
		case .exportPreferences: PreferencesImportExport.export(in: mainWindow)
		case .toggleNotificationSounds: setNotificationSoundsMuted(TextualPreferences.soundIsMuted() == false)
		case .toggleNotifications:
			setNotificationsMuted(SharedApplication.sharedNotificationController().areNotificationsDisabled == false)
		case .resetAppearance: setAppearance(.inherited)
		case .toggleAppearance: toggleAppearance()
		case .toggleServerList: mainWindow.toggleServerListVisibility()
		case .toggleMemberList:
			mainWindow.toggleMemberListVisibility()
		case .reloadTheme: mainWindow.reloadTheme()
		case .toggleDeveloperMode: toggleDeveloperMode()
		case .resetSuppressedWarnings: resetSuppressedWarnings()
		@unknown default: break
		}
	}

	@objc(setNotificationsMuted:)
	func setNotificationsMuted(_ muted: Bool) {
		SharedApplication.sharedNotificationController().areNotificationsDisabled = muted
		let state: NSControl.StateValue = muted ? .on : .off
		menuController?.muteNotificationsFileMenuItem?.state = state
		menuController?.muteNotificationsDockMenuItem?.state = state
	}

	@objc(setNotificationSoundsMuted:)
	func setNotificationSoundsMuted(_ muted: Bool) {
		TextualPreferences.setSoundIsMuted(muted)
		let state: NSControl.StateValue = muted ? .on : .off
		menuController?.muteNotificationsSoundsDockMenuItem?.state = state
		menuController?.muteNotificationsSoundsFileMenuItem?.state = state
	}

	private func closeWindow(_ sender: Any?) {
		let action = TextualPreferences.commandWKeyAction()
		if action == .closeWindow || mainWindow.isKeyWindow == false {
			(NSApp.keyWindow ?? NSApp.mainWindow)?.performClose(sender)
			return
		}
		guard let client = selectedClient else { return }
		switch action {
		case .partChannel:
			guard let channel = selectedChannel else { return }
			if channel.isChannel {
				guard channel.isActive else { return }
				client.part(channel)
			} else {
				world?.destroy(channel)
			}
		case .disconnect:
			guard client.isConnecting || client.isConnected else { return }
			client.quit()
		case .terminate:
			NSApp.terminate(sender)
		case .closeWindow:
			break
		@unknown default:
			break
		}
	}

	private func resetMainWindowFrame(_ sender: Any?) {
		if mainWindow.ceIsInFullscreenMode {
			mainWindow.toggleFullScreen(sender)
		}
		mainWindow.setFrame(mainWindow.defaultWindowFrame, display: true, animate: true)
		mainWindow.ce_exactlyCenter()
	}

	private func sortChannelList() {
		guard let world else { return }
		for client in world.clientList {
			let sortedChannels = client.channelList.sorted(by: MenuWindowPolicy.channelsOrderedBeforeQueries)
			guard sortedChannels != client.channelList else { continue }
			client.channelList = sortedChannels
			client.reloadServerListItems()
		}
		world.save()
	}

	private func setAppearance(_ appearance: TXPreferredAppearance) {
		TextualPreferences.setAppearance(appearance)
		TextualPreferences.performReloadAction(.appearance)
	}

	private func toggleAppearance() {
		setAppearance(MenuWindowPolicy.nextAppearance(
			current: TextualPreferences.appearance(),
			systemIsDark: SharedApplication.sharedAppearance().properties.isDarkAppearance
		))
	}

	private func toggleDeveloperMode() {
		TextualPreferences.setDeveloperModeEnabled(TextualPreferences.developerModeEnabled() == false)
		TextualPreferences.performReloadAction(.ircCommandCache)
	}

	private func resetSuppressedWarnings() {
		let defaults = TextualUserDefaults.shared()
		for key in defaults.dictionaryRepresentation().keys
			where key.hasPrefix(MenuWindowPolicy.alertSuppressionPrefix)
		{
			defaults.set(false, forKey: key)
		}
	}
}
