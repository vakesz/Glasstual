// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2020 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import CocoaExtensions
import os

private let menuWindowLogger = Logger(
	subsystem: LogSubsystem.current,
	category: "MenuActionController"
)

// MARK: - Window, appearance and application-wide commands

extension MenuActionController {
	@objc func closeWindow(_ sender: Any?) {
		let action = SettingsKeys.Input.commandWKeyAction.value
		if action == .closeWindow || mainWindow.isKeyWindow == false {
			(NSApp.keyWindow ?? NSApp.mainWindow)?.performClose(sender)
			return
		}
		guard let session = context.selectedSession else { return }
		switch action {
		case .closeConversation:
			guard let conversation = context.selectedConversation else { return }
			if conversation.isChannel {
				guard conversation.isActive else { return }
				session.part(conversation)
			} else {
				chatSession?.destroyConversation(conversation)
			}
		case .disconnect:
			guard session.isConnecting || session.isConnected else { return }
			session.quit()
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

	/// Sorts every server's conversations, channels first. One-to-one
	/// conversations sit in the same list and are sorted with it.
	@objc func sortConversationList(_: Any?) {
		guard let chatSession else { return }
		for session in chatSession.sessions {
			let sorted = session.conversationList.sorted(by: MenuWindowPolicy.channelsOrderedBeforeDirectConversations)
			chatSession.setConversationList(sorted, on: session)
		}
		chatSession.save()
	}

	@objc func focusSearchField(_: Any?) {
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
		guard let appearance = MenuWindowPolicy.appearance(for: sender?.command) else { return }
		SettingsKeys.Appearance.preferredAppearance.value = appearance
		SettingsReload.perform(.appearance)
	}

	@objc func toggleSidebarVisibility(_: Any?) {
		mainWindow.toggleSidebarVisibility()
	}

	@objc func toggleMemberListVisibility(_: Any?) {
		mainWindow.toggleMemberListVisibility()
	}

	@objc func toggleDeveloperMode(_: Any?) {
		SettingsKeys.Commands.developerMode.value.toggle()
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
		mainWindow.chrome.areNotificationsDisabled = muted
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

	@objc func openAcknowledgements(_: Any?) {
		guard let url = Bundle.main.url(
			forResource: "Acknowledgements",
			withExtension: "pdf",
			subdirectory: "Documentation"
		) else {
			menuWindowLogger.error("Acknowledgements.pdf is missing from the application bundle")
			return
		}
		NSWorkspace.shared.open(url)
	}

	@objc func connectToGlasstualHelpChannel(_: Any?) {
		ServerConnection.connect(to: .help)
	}

	@objc func connectToGlasstualTestingChannel(_: Any?) {
		ServerConnection.connect(to: .testing)
	}
}
