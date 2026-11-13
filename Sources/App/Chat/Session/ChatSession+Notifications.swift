// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

struct ChatSessionListWasModified: SubjectMessage {
	typealias Subject = ChatSession

	nonisolated static let name = Notification.Name("Glasstual.chatSessionListWasModified")

	let subject: ChatSession
}

struct ChatSessionWillDestroySession: SubjectMessage {
	typealias Subject = ServerSession

	nonisolated static let name = Notification.Name("Glasstual.chatSessionWillDestroySession")

	let subject: ServerSession
}
