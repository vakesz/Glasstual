// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

@MainActor
extension ServerSession {
	/** IRCv3 `draft/channel-rename`: `RENAME <old> <new> [:reason]`.

	 The server sends it instead of a PART and a JOIN, so the channel the reader
	 is in simply has another name. The conversation is kept, with its members,
	 transcript and history, and only its name changes. A rename the server
	 replays from history describes a name the channel no longer has, so it is
	 not applied. */
	func receiveRename(_ message: Message) {
		guard isCapabilityEnabled(.channelRename), message.isReplayed == false, message.params.count >= 2 else { return }
		let oldName = message.params[0]
		let newName = message.params[1]
		guard stringIsChannelName(oldName), stringIsChannelName(newName),
		      let channel = findConversation(oldName), channel.isChannel,
		      channel.name != newName
		else { return }

		var keptName: String?
		if let existing = findConversation(newName), existing !== channel {
			/* Another entry already carries the new name. One that is not joined
			 is a saved leftover: it is kept, with its history, under a display
			 name that no channel can have. A joined one cannot be told apart
			 from the live channel, so the rename is reported and not applied. */
			guard existing.isChannel, existing.status != .joined, existing.status != .joining else {
				printDebugInformation(
					String(localized: .IRC.channelRenameConflict(oldName, newName)),
					in: channel,
					asCommand: message.command
				)
				return
			}
			keptName = retireUnjoinedChannel(existing, makingRoomFor: newName)
		}

		channel.applyChannelRename(to: newName)
		output?.reloadChatItem(channel)
		output?.updateTitle(for: channel)

		let reason = message.params.count > 2 ? message.params[2] : ""
		let text = reason.isEmpty
			? String(localized: .IRC.channelRenamed(oldName, newName))
			: String(localized: .IRC.channelRenamedWithReason(oldName, newName, reason))
		guard shouldPrintReceivedMessage(message, withText: text, destinedFor: channel) else { return }
		print(text, by: nil, in: channel, as: .debug, command: message.command, receivedAt: message.receivedAt)
		if let keptName {
			print(
				String(localized: .IRC.channelRenameKeptOld(newName, keptName)),
				by: nil, in: channel, as: .debug, command: message.command, receivedAt: message.receivedAt
			)
		}
	}

	/** Renames a saved, unjoined channel out of the way and returns its new name.

	 Nothing is deleted: the conversation keeps its identifier, so its history
	 stays, and only its name changes. The name holds a space, which no IRC
	 channel name can, so it can never equal a name the server sends and a later
	 rename cannot collide with it; a number is added if another entry already
	 uses the same one. Autojoin is turned off, because the name is a label and
	 not something to JOIN. */
	private func retireUnjoinedChannel(_ existing: Conversation, makingRoomFor newName: String) -> String {
		var candidate = String(localized: .IRC.channelRenamePreviousName(newName))
		var number = 2
		while let taken = findConversation(candidate), taken !== existing {
			candidate = String(localized: .IRC.channelRenamePreviousNameNumbered(newName, number))
			number += 1
		}
		existing.autoJoin = false
		existing.applyChannelRename(to: candidate)
		output?.reloadChatItem(existing)
		return candidate
	}
}
