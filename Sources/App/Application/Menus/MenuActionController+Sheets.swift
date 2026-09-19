// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2020 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit

// MARK: - Sheets, panels and windows

/* Each command checks it can act before ``MenuSheetPresenter`` takes down the
 sheet already on screen. The other order dismissed an unrelated sheet, and the
 edits in it, for a command that then did nothing. */

extension MenuActionController {
	@objc func showChannelPropertiesSheet(_: Any?) {
		guard let channel = context.selectedConversation, channel.isChannel else { return }
		MenuSheetPresenter.presentChannelProperties(for: channel, on: channel.associatedSession)
	}

	@objc func memberSendInvite(_ sender: NSMenuItem?) {
		guard let target = context.commandTarget(for: sender),
		      target.session.isLoggedIn, target.conversation.isChannel, target.conversation.isActive,
		      target.nicknames.isEmpty == false
		else { return }
		context.deselectMembers(for: sender)
		let channels = target.session.conversationList.compactMap { channel in
			channel !== target.conversation && channel.isChannel ? channel.name : nil
		}
		guard channels.isEmpty == false else { return }
		MenuSheetPresenter.presentChannelInvite(for: target.nicknames, on: target.session, to: channels)
	}

	@objc func showAddressBook(_: Any?) {
		presentServerPropertiesForSelectedSession(at: .addressBook)
	}

	@objc func showOnboardingWindow(_: Any?) {
		mainWindow.sheetModel.dismissPresentedSheet()
		AppServices.scenes.open(ApplicationSceneID.onboarding)
	}

	@objc func showAboutWindow(_: Any?) {
		AppServices.scenes.open(ApplicationSceneID.about)
	}

	@objc func showServerPropertiesSheet(_: Any?) {
		presentServerPropertiesForSelectedSession(at: .default)
	}

	/// A window rather than a sheet: the list exists to jump into the transcript
	/// with, and a sheet had to be dismissed to get there and reopened for the
	/// next highlight.
	@objc func showHighlightLog(_: Any?) {
		guard let session = context.selectedSession else { return }
		AppServices.highlightLogs.open(for: session)
	}

	@objc func showChannelModifyTopicSheet(_: Any?) {
		guard let channel = context.selectedConversation, channel.isChannel else { return }
		MenuSheetPresenter.presentChannelTopic(for: channel)
	}

	@objc func showChannelModifyModesSheet(_: Any?) {
		guard let channel = context.selectedConversation, channel.isChannel else { return }
		MenuSheetPresenter.presentChannelModes(for: channel)
	}

	@objc func showChannelSpotlightWindow(_: Any?) {
		AppServices.channelSpotlight.open()
	}

	@objc func showServerChangeNicknameSheet(_: Any?) {
		guard let session = context.selectedSession, session.isLoggedIn else { return }
		MenuSheetPresenter.presentNicknameChange(for: session)
	}

	@objc func showSettingsWindow(_: Any?) {
		AppServices.scenes.openSettings(.default)
	}

	@objc func showHiddenSettings(_: Any?) {
		AppServices.scenes.openSettings(.hiddenSettings)
	}

	/// Swift-only: the notification the alert answers carries no menu item.
	func showNotificationSettings() {
		AppServices.scenes.openSettings(.notifications)
	}

	@objc func showFileTransfersWindow(_: Any?) {
		AppServices.fileTransfers.present()
	}

	/// Named for its argument so that the member-list menu can own the plain
	/// `memberChangeColor:` selector.
	func showNicknameColorSheet(for nickname: String) {
		guard context.selectedSession != nil else { return }
		MenuSheetPresenter.presentNicknameColor(for: nickname)
	}

	private func presentServerPropertiesForSelectedSession(at destination: ServerPropertiesDestination) {
		guard let session = context.selectedSession else { return }
		MenuSheetPresenter.presentServerProperties(for: session, at: destination)
	}
}
