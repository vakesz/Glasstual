// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppIntents

nonisolated extension IntentActionError: CustomLocalizedStringResourceConvertible {
	var localizedStringResource: LocalizedStringResource {
		switch self {
		case .applicationNotReady: .ShortcutIntents.errorNotReady
		case .serverNotFound: .ShortcutIntents.errorServerNotFound
		case .conversationNotFound: .ShortcutIntents.errorConversationNotFound
		case .notConnected: .ShortcutIntents.errorNotConnected
		case .invalidChannelName: .ShortcutIntents.errorInvalidChannel
		case .emptyMessage: .ShortcutIntents.errorEmptyMessage
		case .messageTooLong: .ShortcutIntents.errorMessageTooLong
		}
	}
}
