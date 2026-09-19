// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
@testable import Glasstual
import SwiftUI
import Testing

extension MenuContentViewTests {
	@Test("Channel menus disable unauthorized writes while keeping list queries available")
	func channelMenuPermissions() async throws {
		try await withChannelMenu { controller, _, session, _ in
			let channel = try preparePermissionChannel(session)
			_ = channel.modeInfo?.updateModes("+t")
			controller.context.withContext(.sidebarItem(channel)) {
				for command in [MenuCommand.modifyTopic, .modes, .channelModeManageAll, .channelModeModerated, .channelModeInviteOnly] {
					let item = NSMenuItem()
					item.command = command
					#expect(controller.validateMenuItem(item) == false, "\(command)")
					#expect(item.isHidden == false)
				}
				let bans = NSMenuItem()
				bans.command = .bans
				#expect(controller.validateMenuItem(bans))
				_ = channel.modeInfo?.updateModes("-t")
				let topic = NSMenuItem()
				topic.command = .modifyTopic
				#expect(controller.validateMenuItem(topic))
			}
		}
	}

	@Test("Direct mode actions and already-open native menus recheck current channel privileges")
	func modeActionsRecheckPermissions() async throws {
		try await withChannelMenu { controller, _, session, _ in
			let channel = try preparePermissionChannel(session)
			controller.context.withContext(.sidebarItem(channel)) {
				controller.toggleChannelModerationMode(nil)
				controller.toggleChannelInviteMode(nil)
			}
			#expect(session.sentLines.count == 0)
			channel.changeMember(session.userNickname, mode: ChannelModeSymbol(Character("o")), value: true)
			let native = MenuContentView.nativeMenu(
				menu: controller.mainMenuChannelMenu,
				context: MenuTargetContext(coordinator: controller, item: channel),
				prepareSelection: {}
			)
			let item = try #require(native.item(for: .channelModeModerated))
			try #require(item.isEnabled)
			#expect(try NSApp.sendAction(#require(item.action), to: item.target, from: item))
			#expect(session.sentLines.compactMap { $0 as? String } == ["MODE #permissions +m"])
			channel.changeMember(session.userNickname, mode: ChannelModeSymbol(Character("o")), value: false)
			#expect(try NSApp.sendAction(#require(item.action), to: item.target, from: item))
			#expect(session.sentLines.count == 1)
		}
	}

	@Test("Unauthorized sheet commands leave an existing editor intact")
	func unauthorizedSheetsPreserveExistingEditor() async throws {
		try await withChannelMenu { controller, window, session, _ in
			let channel = try preparePermissionChannel(session)
			_ = channel.modeInfo?.updateModes("+t")
			let owner = NSObject()
			window.sheetModel.presentSheet(MainWindowSheet(owner: owner, content: EmptyView(), onDismiss: {}))
			defer { window.sheetModel.dismissPresentedSheet() }
			controller.context.withContext(.sidebarItem(channel)) {
				controller.showChannelModifyTopicSheet(nil)
				controller.showChannelModifyModesSheet(nil)
			}
			MenuSheetPresenter.presentChannelTopic(for: channel)
			MenuSheetPresenter.presentChannelModes(for: channel)
			#expect(window.sheetModel.presentedSheet?.owner === owner)
		}
	}

	@Test("Topic submission rechecks a restriction added while the editor is open")
	func topicSubmissionRechecksRestriction() async throws {
		try await withChannelMenu { _, window, session, _ in
			let channel = try preparePermissionChannel(session)
			defer { window.sheetModel.dismissPresentedSheet() }
			MenuSheetPresenter.presentChannelTopic(for: channel)
			let sheet = try #require(window.sheetModel.presentedSheet?.owner as? ChannelTopicSheet)
			sheet.model.formattedTopic = "Updated topic"
			_ = channel.modeInfo?.updateModes("+t")
			sheet.submit()
			#expect(session.sentLines.count == 0)
			_ = channel.modeInfo?.updateModes("-t")
			MenuSheetPresenter.presentChannelTopic(for: channel)
			let allowed = try #require(window.sheetModel.presentedSheet?.owner as? ChannelTopicSheet)
			allowed.model.formattedTopic = "Allowed topic"
			allowed.submit()
			#expect(session.sentLines.compactMap { $0 as? String } == ["TOPIC #permissions :Allowed topic"])
		}
	}

	@Test("Mode submission rechecks privilege or membership lost while editing", arguments: [false, true])
	func modeSubmissionRechecksMembership(parted: Bool) async throws {
		try await withChannelMenu { _, window, session, _ in
			let channel = try preparePermissionChannel(session)
			channel.changeMember(session.userNickname, mode: ChannelModeSymbol(Character("o")), value: true)
			defer { window.sheetModel.dismissPresentedSheet() }
			MenuSheetPresenter.presentChannelModes(for: channel)
			let sheet = try #require(window.sheetModel.presentedSheet?.owner as? ChannelModesSheet)
			sheet.model.setMode(.moderated, enabled: true)
			if parted {
				channel.deactivate()
			} else {
				channel.changeMember(session.userNickname, mode: ChannelModeSymbol(Character("o")), value: false)
			}
			sheet.submit()
			#expect(session.sentLines.count == 0)
		}
	}

	private func preparePermissionChannel(_ session: TestServerSession) throws -> Conversation {
		session.userNickname = "local"
		session.markAsLoggedIn()
		let channel = try #require(session.findConversationOrCreate("#permissions"))
		channel.activate()
		channel.addUser(session.findUserOrCreate(session.userNickname))
		session.sentLines.removeAllObjects()
		return channel
	}
}
