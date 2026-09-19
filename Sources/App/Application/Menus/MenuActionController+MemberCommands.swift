// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2020 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import CocoaExtensions

// MARK: - Member commands

/* The items these answer are only ever menu items, so the sender is one: what a
 command is aimed at comes off the item, and `MenuContextResolver` turns it into
 the connection, the conversation and the nicknames the command applies to. */

extension MenuActionController {
	@objc func memberAddIgnore(_ sender: NSMenuItem?) {
		performIgnore(sender: sender, remove: false)
	}

	@objc func memberRemoveIgnore(_ sender: NSMenuItem?) {
		performIgnore(sender: sender, remove: true)
	}

	@objc func memberModifyIgnore(_ sender: NSMenuItem?) {
		modifyIgnore(sender: sender)
	}

	@objc func memberSendWhois(_ sender: NSMenuItem?) {
		performForNicknames(sender: sender) { $0.sendWhois($1) }
	}

	@objc func memberStartDirectConversation(_ sender: NSMenuItem?) {
		startDirectConversation(sender: sender)
	}

	@objc func memberChangeColor(_ sender: NSMenuItem?) {
		guard let target = context.commandTarget(for: sender),
		      let nickname = target.nicknames.first
		else { return }

		showNicknameColorSheet(for: nickname)
	}

	@objc func memberSendCTCPPing(_ sender: NSMenuItem?) {
		performForNicknames(sender: sender) { $0.sendCTCPPing($1) }
	}

	@objc func memberSendCTCPFinger(_ sender: NSMenuItem?) {
		performCTCP("FINGER", sender: sender)
	}

	@objc func memberSendCTCPTime(_ sender: NSMenuItem?) {
		performCTCP("TIME", sender: sender)
	}

	@objc func memberSendCTCPVersion(_ sender: NSMenuItem?) {
		performCTCP("VERSION", sender: sender)
	}

	@objc func memberSendCTCPUserinfo(_ sender: NSMenuItem?) {
		performCTCP("USERINFO", sender: sender)
	}

	@objc func memberSendCTCPClientInfo(_ sender: NSMenuItem?) {
		performCTCP("CLIENTINFO", sender: sender)
	}

	@objc func memberModeGiveOp(_ sender: NSMenuItem?) {
		performMode("OP", sender: sender)
	}

	@objc func memberModeTakeOp(_ sender: NSMenuItem?) {
		performMode("DEOP", sender: sender)
	}

	@objc func memberModeGiveHalfop(_ sender: NSMenuItem?) {
		performMode("HALFOP", sender: sender)
	}

	@objc func memberModeTakeHalfop(_ sender: NSMenuItem?) {
		performMode("DEHALFOP", sender: sender)
	}

	@objc func memberModeGiveVoice(_ sender: NSMenuItem?) {
		performMode("VOICE", sender: sender)
	}

	@objc func memberModeTakeVoice(_ sender: NSMenuItem?) {
		performMode("DEVOICE", sender: sender)
	}

	@objc func memberKickFromChannel(_ sender: NSMenuItem?) {
		performChannelModeration(sender: sender) { session, channel, nickname in
			session.kick(nickname, in: channel)
		}
	}

	@objc func memberBanFromChannel(_ sender: NSMenuItem?) {
		performChannelModeration(sender: sender) { session, channel, nickname in
			session.sendCommand("BAN \(nickname)", completeTarget: true, target: channel.name)
		}
	}

	@objc func memberKickbanFromChannel(_ sender: NSMenuItem?) {
		performChannelModeration(sender: sender) { session, channel, nickname in
			session.sendCommand(
				MemberModerationCommand.kickban(nickname, reason: SettingsKeys.Commands.kickMessage.value),
				completeTarget: true,
				target: channel.name
			)
		}
	}

	@objc func memberKillFromServer(_ sender: NSMenuItem?) {
		performOperatorCommand("KILL", reason: SettingsKeys.Commands.irCopKillMessage.value, sender: sender)
	}

	@objc func memberShunOnServer(_ sender: NSMenuItem?) {
		performOperatorCommand("SHUN", reason: SettingsKeys.Commands.irCopShunMessage.value, sender: sender)
	}

	@objc func memberBanFromServer(_ sender: NSMenuItem?) {
		performGline(sender: sender)
	}

	@objc func memberSetVirtualHost(_ sender: NSMenuItem?) {
		showSetVirtualHostPrompt(sender: sender)
	}

	@objc func memberSendFileRequest(_ sender: NSMenuItem?) {
		showFilePicker(sender: sender)
	}

	/// The member list's own double click. It carries no menu item, so the
	/// command applies to the row the list just recorded.
	func memberInMemberListDoubleClicked() {
		guard mainWindow.memberList.primaryInteractedMember != nil else { return }
		performDoubleClick(sender: nil)
	}

	/// The same, for a nickname double-clicked in the transcript: the name is
	/// already in `pointedNickname`.
	func memberInTranscriptDoubleClicked() {
		performDoubleClick(sender: nil)
	}
}

private extension MenuActionController {
	func performIgnore(sender: NSMenuItem?, remove: Bool) {
		guard let target = context.commandTarget(for: sender),
		      let nickname = target.nicknames.first
		else { return }
		context.deselectMembers(for: sender)
		let command = remove ? MemberModerationCommand.unignore(nickname) : MemberModerationCommand.ignore(nickname)
		target.session.sendCommand(command, completeTarget: true, target: target.conversation.name)
	}

	func modifyIgnore(sender: NSMenuItem?) {
		guard let session = context.selectedSession else { return }
		let selectedMembers = context.selectedMembers(for: sender)
		context.deselectMembers(for: sender)
		guard selectedMembers.count == 1,
		      let hostmask = selectedMembers.first?.user.hostmask
		else { return }
		let ignores = session.findIgnores(forHostmask: hostmask)
		if ignores.count == 1 {
			MenuSheetPresenter.presentServerProperties(for: session, at: .editIgnoreEntry(ignores[0]))
		} else {
			MenuSheetPresenter.presentServerProperties(for: session, at: .addressBook)
		}
	}

	func performDoubleClick(sender: NSMenuItem?) {
		switch SettingsKeys.Input.userDoubleClickAction.value {
		case .whois:
			performForNicknames(sender: sender) { $0.sendWhois($1) }
		case .startDirectConversation:
			startDirectConversation(sender: sender)
		case .insertTextField:
			insertNicknames(sender: sender)
		@unknown default:
			break
		}
	}

	func insertNicknames(sender: NSMenuItem?) {
		guard let target = context.commandTarget(for: sender),
		      target.nicknames.isEmpty == false
		else { return }
		context.deselectMembers(for: sender)

		guard let textView = mainWindow.inputTextField else { return }
		let selectedRange = textView.selectedRange
		var insertion = ""
		if selectedRange.location > 0 {
			/* selectedRange is measured in UTF-16 code units, so it must be
			 read back through NSString. Feeding it to String.index(_:offsetBy:)
			 counts Characters and lands on the wrong one — or traps — as soon
			 as the field holds an emoji. */
			let text = textView.stringValue as NSString
			let previous = text.character(at: selectedRange.location - 1)
			/* A surrogate half is never whitespace, so nil reads as false. */
			let isWhitespace = Unicode.Scalar(previous).map { scalar in
				CharacterSet.whitespacesAndNewlines.contains(scalar)
			} ?? false
			if isWhitespace == false {
				insertion.append(" ")
			}
		}
		insertion += target.nicknames.joined(separator: ", ")
		insertion += SettingsKeys.Input.tabCompletionSuffix.storedValue ?? ""
		/* Through the editing pair, so the bar resizes, the placeholder hides,
		 the typing state is sent and the insertion is undoable. */
		guard textView.shouldChangeText(in: selectedRange, replacementString: insertion) else { return }
		textView.replaceCharacters(in: selectedRange, with: insertion)
		/* The text that was there is gone: what has to be recoloured is what
		 replaced it. Reusing the pre-edit range walks off the end of a storage
		 the replacement shrank -- select eleven characters, insert a nickname
		 shorter than that, and the range check throws. */
		textView.resetFontColor(
			in: MenuInsertionRangePolicy.insertedRange(replacing: selectedRange, with: insertion)
		)
		textView.didChangeText()
		textView.focus()
	}

	func performForNicknames(sender: NSMenuItem?, action: (ServerSession, String) -> Void) {
		guard let target = context.commandTarget(for: sender) else { return }
		for nickname in target.nicknames {
			action(target.session, nickname)
		}
		context.deselectMembers(for: sender)
	}

	func startDirectConversation(sender: NSMenuItem?) {
		guard let target = context.commandTarget(for: sender) else { return }
		for nickname in target.nicknames {
			guard let direct = target.session.findConversationOrCreate(nickname, isDirect: true) else { continue }
			mainWindow.select(direct)
		}
		context.deselectMembers(for: sender)
	}

	func performCTCP(_ command: String, sender: NSMenuItem?) {
		performForNicknames(sender: sender) { $0.sendCTCPQuery($1, command: command, text: nil) }
	}

	func performMode(_ command: String, sender: NSMenuItem?) {
		guard let target = context.commandTarget(for: sender),
		      target.session.isLoggedIn, target.conversation.isChannel
		else { return }
		context.deselectMembers(for: sender)
		target.session.sendCommand(
			MemberModerationCommand.mode(command, nicknames: target.nicknames),
			completeTarget: true,
			target: target.conversation.name
		)
	}

	/// Kick, ban and kickban only mean anything inside a `#channel`, so the one
	/// guard they share sits here.
	func performChannelModeration(sender: NSMenuItem?, action: (ServerSession, Conversation, String) -> Void) {
		guard let target = context.commandTarget(for: sender),
		      target.session.isLoggedIn, target.conversation.isChannel
		else { return }
		for nickname in target.nicknames {
			action(target.session, target.conversation, nickname)
		}
		context.deselectMembers(for: sender)
	}

	func performOperatorCommand(_ command: String, reason: String, sender: NSMenuItem?) {
		guard let target = context.commandTarget(for: sender), target.session.isLoggedIn else { return }
		for nickname in target.nicknames {
			target.session.sendCommand(
				MemberModerationCommand.operatorCommand(command, nickname: nickname, reason: reason)
			)
		}
		context.deselectMembers(for: sender)
	}

	func performGline(sender: NSMenuItem?) {
		guard let target = context.commandTarget(for: sender), target.session.isLoggedIn else { return }
		for nickname in target.nicknames {
			if target.session.nicknameIsMyself(nickname) {
				target.session.printDebugInformation(
					String(localized: .IRC.glasstualHasPreventedYouFromBanning(target.session.serverAddress ?? "")),
					in: target.conversation
				)
				continue
			}
			target.session.sendCommand(MemberModerationCommand.operatorCommand(
				"GLINE",
				nickname: nickname,
				reason: SettingsKeys.Commands.irCopGlineMessage.value
			))
		}
		context.deselectMembers(for: sender)
	}

	func showSetVirtualHostPrompt(sender: NSMenuItem?) {
		guard let target = context.commandTarget(for: sender), target.session.isLoggedIn,
		      target.nicknames.isEmpty == false
		else { return }
		context.deselectMembers(for: sender)
		let session = target.session
		let nicknames = target.nicknames
		mainWindow.sheetModel.presentInputPrompt(InputPromptRequest(
			title: PromptStrings.VirtualHost.title,
			message: PromptStrings.VirtualHost.body,
			placeholder: PromptStrings.VirtualHost.placeholder,
			submitButtonTitle: PromptStrings.Action.confirmation,
			cancelButtonTitle: PromptStrings.Action.cancel
		)) { outcome in
			guard case let .submitted(input) = outcome else { return }
			let vhost = input.firstToken
			guard vhost.isEmpty == false else { return }
			for nickname in nicknames {
				session.sendCommand(
					MemberModerationCommand.setVhost(vhost, nickname: nickname),
					completeTarget: false,
					target: nil
				)
			}
		}
	}

	func showFilePicker(sender: NSMenuItem?) {
		guard let target = context.commandTarget(for: sender), target.session.isLoggedIn,
		      target.nicknames.isEmpty == false
		else { return }
		context.deselectMembers(for: sender)
		let session = target.session
		let nicknames = target.nicknames
		mainWindow.sheetModel.chooseTransferFiles { urls in
			guard session.isLoggedIn else { return }
			for nickname in nicknames {
				for url in urls {
					AppServices.fileTransfers.offerSender(
						for: session,
						nickname: nickname,
						path: url.path,
						autoOpen: true,
						accessURL: url
					)
				}
			}
		}
	}
}

/// Where the nickname insertion above landed once it has replaced a selection.
/// The replaced range describes storage that no longer exists, so nothing may
/// be measured against it afterwards.
nonisolated enum MenuInsertionRangePolicy {
	static func insertedRange(replacing replaced: NSRange, with insertion: String) -> NSRange {
		NSRange(location: replaced.location, length: insertion.utf16.count)
	}
}
