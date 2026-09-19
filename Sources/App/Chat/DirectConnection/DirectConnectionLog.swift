// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
import os

/** Logging for the peer-to-peer connections, split the way the folder is:
 the transport both features are built on, the file transfers, and the chats. */
nonisolated enum DirectConnectionLog {
	static let transport = Logger(
		subsystem: LogSubsystem.current, category: "DirectConnection.Transport"
	)

	static let transfer = Logger(
		subsystem: LogSubsystem.current, category: "DirectConnection.Transfer"
	)

	static let chat = Logger(
		subsystem: LogSubsystem.current, category: "DirectConnection.Chat"
	)
}
