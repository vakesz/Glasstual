// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2020 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import CocoaExtensions

// MARK: - Window, appearance and application-wide commands

extension MenuActionController {
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
				clientDirectory?.destroyChannel(channel)
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
		mainWindow.centerOnScreen()
	}

	@objc func resetMainWindowFrame(_ sender: Any?) {
		if mainWindow.styleMask.contains(.fullScreen) {
			mainWindow.toggleFullScreen(sender)
		}
		mainWindow.setFrame(mainWindow.defaultWindowFrame, display: true, animate: true)
		mainWindow.centerOnScreen()
	}

	@objc func sortChannelListNames(_: Any?) {
		guard let clientDirectory else { return }
		for client in clientDirectory.clientList {
			let sortedChannels = client.channelList.sorted(by: MenuWindowPolicy.channelsOrderedBeforeQueries)
			clientDirectory.setChannelList(sortedChannels, on: client)
		}
		clientDirectory.save()
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

	@objc func toggleMuteOnNotificationSounds(_: Any?) {
		setNotificationSoundsMuted(Preferences.Notifications.soundIsMuted.value == false)
	}

	@objc func toggleMuteOnNotifications(_: Any?) {
		setNotificationsMuted(AppServices.notifications.areNotificationsDisabled == false)
	}

	@objc func changeAppearance(_ sender: Any?) {
		guard let appearance = MenuWindowPolicy.appearance(for: (sender as? NSMenuItem)?.command) else { return }
		Preferences.Appearance.preferredAppearance.value = appearance
		PreferenceReload.perform(.appearance)
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
		let defaults = GlasstualUserDefaults.container
		for key in defaults.dictionaryRepresentation().keys
			where key.hasPrefix(MenuWindowPolicy.alertSuppressionPrefix)
		{
			defaults.set(false, forKey: key)
		}
	}

	func setNotificationsMuted(_ muted: Bool) {
		AppServices.notifications.areNotificationsDisabled = muted
		/* The sidebar's overflow menu names the next press from this. */
		mainWindow.presentationModel.areNotificationsDisabled = muted
		let state: NSControl.StateValue = muted ? .on : .off
		muteNotificationsFileMenuItem?.state = state
		muteNotificationsDockMenuItem?.state = state
	}

	func setNotificationSoundsMuted(_ muted: Bool) {
		Preferences.Notifications.soundIsMuted.value = muted
		let state: NSControl.StateValue = muted ? .on : .off
		muteNotificationsSoundsDockMenuItem?.state = state
		muteNotificationsSoundsFileMenuItem?.state = state
	}
}
