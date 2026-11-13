// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** What the active Focus asks of Glasstual, as the Focus filter delivered it.

 `nil` in the owner means no filter applies. The value holds identifiers and
 flags only, so it crosses from the intent to the sessions as a snapshot. */
nonisolated struct FocusFilterState: Codable, Equatable, Sendable {
	enum Mode: String, Codable, CaseIterable, Sendable {
		case muteNotifications
		case setAway
		case muteAndSetAway

		var mutesNotifications: Bool {
			self != .setAway
		}

		var setsAway: Bool {
			self != .muteNotifications
		}
	}

	/// Which conversations a filter reaches.
	enum ConversationKind: String, Codable, CaseIterable, Sendable {
		case all
		case channels
		case directMessages
	}

	var mode = Mode.muteNotifications
	/// Server configuration identifiers the filter reaches. Empty means every network.
	var networkIdentifiers: Set<String> = []
	var conversationKind = ConversationKind.all
	/// Whether highlights and direct messages still notify while muted.
	var exemptsHighlightsAndDirectMessages = false
	var awayMessage: String?

	func reaches(network identifier: String) -> Bool {
		networkIdentifiers.isEmpty || networkIdentifiers.contains(identifier)
	}

	func setsAway(onNetwork identifier: String) -> Bool {
		mode.setsAway && reaches(network: identifier)
	}

	/** Whether the filter silences `event`.

	 `isDirect` is `nil` for an event that belongs to no conversation. File
	 transfer questions are never silenced, matching a muted conversation. */
	func suppresses(event: UserNotificationEvent, network identifier: String, isDirect: Bool?) -> Bool {
		guard mode.mutesNotifications, reaches(network: identifier), event.isFileTransfer == false else {
			return false
		}

		switch conversationKind {
		case .all: break
		case .channels: guard isDirect == false else { return false }
		case .directMessages: guard isDirect == true else { return false }
		}

		if exemptsHighlightsAndDirectMessages {
			switch event {
			case .highlight, .newPrivateMessage, .privateMessage: return false
			default: if isDirect == true {
					return false
				}
			}
		}

		return true
	}
}
