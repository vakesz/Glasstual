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
import CocoaExtensions

enum MenuWindowPolicy {
	static let alertSuppressionPrefix = Preferences.Families.alertSuppression.pattern

	static func appearance(for command: MenuCommand?) -> PreferredAppearance? {
		switch command {
		case .appearanceSystem: .inherited
		case .appearanceLight: .light
		case .appearanceDark: .dark
		default: nil
		}
	}

	static func channelsOrderedBeforeQueries(_ lhs: Channel, _ rhs: Channel) -> Bool {
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

// MARK: - Window, appearance and application-wide commands

public extension MenuActionCoordinator {
	@objc func closeWindow(_ sender: Any?) {
		let action = Preferences.Input.commandWKeyAction.value
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
				world?.destroyChannel(channel)
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

	@objc func showMainWindow(_ sender: Any?) {
		mainWindow.makeKeyAndOrderFront(sender)
	}

	@objc func centerMainWindow(_: Any?) {
		mainWindow.ce_exactlyCenter()
	}

	@objc func resetMainWindowFrame(_ sender: Any?) {
		if mainWindow.ceIsInFullscreenMode {
			mainWindow.toggleFullScreen(sender)
		}
		mainWindow.setFrame(mainWindow.defaultWindowFrame, display: true, animate: true)
		mainWindow.ce_exactlyCenter()
	}

	@objc func sortChannelListNames(_: Any?) {
		guard let world else { return }
		for client in world.clientList {
			let sortedChannels = client.channelList.sorted(by: MenuWindowPolicy.channelsOrderedBeforeQueries)
			world.setChannelList(sortedChannels, on: client)
		}
		world.save()
	}

	@objc func focusSearchField(_: Any?) {
		mainWindow.presentationModel.focusSearchField()
	}

	@objc func markAllAsRead(_: Any?) {
		mainWindow.markAllAsRead()
	}

	@objc func importSettings(_: Any?) {
		mainWindow.presentationModel.preferencesTransfer.requestImport()
	}

	@objc func exportSettings(_: Any?) {
		mainWindow.presentationModel.preferencesTransfer.requestExport()
	}

	/** Cuts the notification being spoken short and moves on to the next one.

	 This was a bare Command+Period registration on the window, which is the
	 system's Cancel: every sheet, panel and alert in the application answers
	 that key, and nothing in any menu said the window had taken it. */
	@objc func skipSpokenNotification(_: Any?) {
		SharedApplication.sharedSpeechSynthesizer().stopSpeakingAndMoveForward()
	}

	@objc func toggleMuteOnNotificationSounds(_: Any?) {
		setNotificationSoundsMuted(Preferences.Notifications.soundIsMuted.value == false)
	}

	@objc func toggleMuteOnNotifications(_: Any?) {
		setNotificationsMuted(SharedApplication.sharedNotificationController().areNotificationsDisabled == false)
	}

	@objc func changeAppearance(_ sender: Any?) {
		guard let appearance = MenuWindowPolicy.appearance(for: (sender as? NSMenuItem)?.command) else { return }
		Preferences.Appearance.preferredAppearance.value = appearance
		TextualPreferences.performReloadAction(.appearance)
	}

	@objc func toggleServerListVisibility(_: Any?) {
		mainWindow.toggleServerListVisibility()
	}

	@objc func toggleMemberListVisibility(_: Any?) {
		mainWindow.toggleMemberListVisibility()
	}

	@objc func toggleDeveloperMode(_: Any?) {
		Preferences.Commands.developerMode.value.toggle()
	}

	@objc func resetSuppressedWarnings(_: Any?) {
		let defaults = TextualUserDefaults.container
		for key in defaults.dictionaryRepresentation().keys
			where key.hasPrefix(MenuWindowPolicy.alertSuppressionPrefix)
		{
			defaults.set(false, forKey: key)
		}
	}

	func setNotificationsMuted(_ muted: Bool) {
		SharedApplication.sharedNotificationController().areNotificationsDisabled = muted
		/* The sidebar's overflow menu names the next press from this. */
		mainWindow.presentationModel.areNotificationsDisabled = muted
		let state: NSControl.StateValue = muted ? .on : .off
		menuController?.muteNotificationsFileMenuItem?.state = state
		menuController?.muteNotificationsDockMenuItem?.state = state
	}

	func setNotificationSoundsMuted(_ muted: Bool) {
		Preferences.Notifications.soundIsMuted.value = muted
		SharedApplication.sharedSpeechSynthesizer().setNotificationsMuted(
			muted || SharedApplication.sharedNotificationController().areNotificationsDisabled
		)
		let state: NSControl.StateValue = muted ? .on : .off
		menuController?.muteNotificationsSoundsDockMenuItem?.state = state
		menuController?.muteNotificationsSoundsFileMenuItem?.state = state
	}
}
