// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2020 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import CocoaExtensions

// MARK: - Window, appearance and application-wide commands

extension MenuActionController {
	@objc func closeWindow(_ sender: Any?) {
		let action = SettingsKeys.Input.commandWKeyAction.value
		guard let behavior = CloseWindowBehavior.resolve(
			action: action,
			isKeyWindow: mainWindow.isKeyWindow,
			hasSession: context.selectedSession != nil
		) else { return }
		switch behavior {
		case .performClose:
			(NSApp.keyWindow ?? NSApp.mainWindow)?.performClose(sender)
			return
		case .partConversation:
			guard let session = context.selectedSession, let conversation = context.selectedConversation else { return }
			if conversation.isChannel {
				guard conversation.isActive else { return }
				session.part(conversation)
			} else {
				chatSession?.destroyConversation(conversation)
			}
		case .disconnect:
			guard let session = context.selectedSession,
			      session.isConnecting || session.isConnected else { return }
			session.quit()
		case .terminate:
			NSApp.terminate(sender)
		}
	}

	@objc func showMainWindow(_ sender: Any?) {
		ApplicationForeground.raise(mainWindow, sender: sender)
	}

	@objc func resetMainWindowFrame(_ sender: Any?) {
		if mainWindow.styleMask.contains(.fullScreen) {
			mainWindow.toggleFullScreen(sender)
		}
		mainWindow.setFrame(mainWindow.defaultWindowFrame, display: true, animate: true)
		mainWindow.centerOnScreen()
	}

	/// Sorts every server's conversations, channels first. One-to-one
	/// conversations sit in the same list and are sorted with it.
	@objc func sortConversationList(_: Any?) {
		guard let chatSession else { return }
		for session in chatSession.sessions {
			let sorted = session.conversationList.sorted(by: ConversationOrdering.channelsFirst)
			chatSession.setConversationList(sorted, on: session)
		}
		chatSession.save()
	}

	@objc func focusSearchField(_: Any?) {
		// The field exists only while its column does.
		if !mainWindow.columnModel.isSidebarVisible {
			mainWindow.toggleSidebarVisibility()
		}
		mainWindow.chrome.focusSearchField()
	}

	@objc func markAllAsRead(_: Any?) {
		mainWindow.markAllAsRead()
	}

	@objc func importSettings(_: Any?) {
		mainWindow.sheetModel.settingsTransfer.requestImport()
	}

	@objc func exportSettings(_: Any?) {
		mainWindow.sheetModel.settingsTransfer.requestExport()
	}

	@objc func toggleMuteOnNotificationSounds(_: Any?) {
		setNotificationSoundsMuted(SettingsKeys.Notifications.soundIsMuted.value == false)
	}

	@objc func toggleMuteOnNotifications(_: Any?) {
		setNotificationsMuted(AppServices.notifications.areNotificationsDisabled == false)
	}

	@objc func changeAppearance(_ sender: NSMenuItem?) {
		guard let appearance = sender?.command?.preferredAppearance else { return }
		SettingsKeys.Appearance.preferredAppearance.value = appearance
		SettingsReload.perform(.appearance)
	}

	@objc func toggleSidebarVisibility(_: Any?) {
		mainWindow.toggleSidebarVisibility()
	}

	@objc func toggleMemberListVisibility(_: Any?) {
		mainWindow.toggleMemberListVisibility()
	}

	func setNotificationsMuted(_ muted: Bool) {
		AppServices.notifications.areNotificationsDisabled = muted
		let state: NSControl.StateValue = muted ? .on : .off
		muteNotificationsFileMenuItem?.state = state
		muteNotificationsDockMenuItem?.state = state
	}

	func setNotificationSoundsMuted(_ muted: Bool) {
		SettingsKeys.Notifications.soundIsMuted.value = muted
		let state: NSControl.StateValue = muted ? .on : .off
		muteNotificationsSoundsDockMenuItem?.state = state
		muteNotificationsSoundsFileMenuItem?.state = state
	}

	// MARK: - Help menu commands

	@objc func showHelpBook(_: Any?) {
		HelpBook.open(.home)
	}

	/// The acknowledgements are the About panel's credits, so a link that asks
	/// for them opens the panel.
	@objc func openAcknowledgements(_ sender: Any?) {
		showAboutWindow(sender)
	}

	@objc func connectToGlasstualHelpChannel(_: Any?) {
		ServerConnection.connect(to: .help)
	}

	@objc func connectToGlasstualTestingChannel(_: Any?) {
		ServerConnection.connect(to: .testing)
	}
}
