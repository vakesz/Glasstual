// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** What a session needs from outside itself: the setting values it branches
 on and the services it calls into.

 It is main-actor state, because `services` is a box of main-actor references
 and every reader of the setting half is on the main actor too. What crosses
 a boundary is `ChatSettings` on its own: it is a `Sendable` value, so a
 caller that needs it elsewhere copies it out rather than carrying this. */
struct ChatEnvironment {
	var settings: ChatSettings
	var services: ChatServices

	var output: (any ServerSessionPresenting)? {
		services.output
	}

	var menu: (any MenuPresenting)? {
		services.menu
	}

	var chatSession: ChatSession? {
		services.chatSession
	}
}

/// Shorthands so the connection code reads `output?.…` rather than reaching
/// through the environment at every call.
@MainActor
extension ServerSession {
	var output: (any ServerSessionPresenting)? {
		environment.services.output
	}

	var menu: (any MenuPresenting)? {
		environment.services.menu
	}

	var channelListPresentation: (any ChannelListPresenting)? {
		environment.services.channelList
	}

	var chatSession: ChatSession? {
		environment.services.chatSession
	}
}
