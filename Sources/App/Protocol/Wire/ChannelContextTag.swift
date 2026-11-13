// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** The `channel-context` client tag: a private message that belongs to a
 channel, such as a bot's private answer to a command typed there.

 The specification now spells it without the `draft/` prefix, while deployed
 clients and bouncers send `+draft/channel-context`. Both are read; the draft
 spelling is sent. */
nonisolated enum ChannelContextTag {
	static let inboundNames = ["+draft/channel-context", "+channel-context"]
	static let outboundName = "+draft/channel-context"

	/// The channel the tags name, or `nil` when neither spelling is present,
	/// the value is empty, or the two spellings disagree.
	static func channelName(in tags: [String: String]?) -> String? {
		guard let tags else { return nil }
		let values = Set(inboundNames.compactMap { tags[$0] })
		guard values.count == 1, let value = values.first, value.isEmpty == false else { return nil }
		return value
	}
}
