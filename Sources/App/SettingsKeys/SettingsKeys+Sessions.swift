// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

nonisolated extension SettingsKeys {
	/// The servers the application connects to, and everything hanging off
	/// them: conversations, per-server address book entries, per-server
	/// highlights.
	enum Sessions {
		private static let group = "Sessions -> "

		/** Every configured server, as the property list the chat session writes.

		 The single most valuable thing in the store, so it is declared here
		 beside every other name rather than as a global beside the code that
		 decodes it. Decoding stays with that code; the name is a setting. */
		static let serverSessions = UntypedSettingsKey(group + "Server Sessions")

		static let all: [any AnySettingsKey] = [serverSessions]
	}
}
