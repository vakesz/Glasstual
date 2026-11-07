// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/// What tearing a conversation down does beyond removing it. Named options rather
/// than positional booleans, so a call site says which of them it means.
struct ConversationDestruction: OptionSet, Sendable {
	let rawValue: Int

	/// Move the selection off the conversation and redraw the navigation list. The
	/// session drops the conversation either way; this names the redraw.
	static let reloadsSidebar = Self(rawValue: 1 << 0)
	/// Send `PART` for a channel that is still joined.
	static let partsChannel = Self(rawValue: 1 << 1)
	/// Keep the conversation's logs, keychain item and input history.
	static let preservesLocalData = Self(rawValue: 1 << 2)

	/// What the user asking to close a conversation means.
	static let `default`: Self = [.reloadsSidebar, .partsChannel]
}
