// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

struct ServerSessionWillConnect: SubjectMessage {
	typealias Subject = ServerSession

	nonisolated static let name = Notification.Name("Glasstual.serverSessionWillConnect")

	let subject: ServerSession
}

struct ServerSessionDidConnect: SubjectMessage {
	typealias Subject = ServerSession

	nonisolated static let name = Notification.Name("Glasstual.serverSessionDidConnect")

	let subject: ServerSession
}

struct ServerSessionWillSendQuit: SubjectMessage {
	typealias Subject = ServerSession

	nonisolated static let name = Notification.Name("Glasstual.serverSessionWillSendQuit")

	let subject: ServerSession
}

struct ServerSessionWillDisconnect: SubjectMessage {
	typealias Subject = ServerSession

	nonisolated static let name = Notification.Name("Glasstual.serverSessionWillDisconnect")

	let subject: ServerSession
}

struct ServerSessionDidDisconnect: SubjectMessage {
	typealias Subject = ServerSession

	nonisolated static let name = Notification.Name("Glasstual.serverSessionDidDisconnect")

	let subject: ServerSession
}
