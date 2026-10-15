// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** What an ISUPPORT line asks the session to do, beyond the values it recorded.

 ``ISupport`` reads tokens and does nothing else: it writes no line and touches
 no capability state, so it needs no way back to the session that owns it. A
 token that means more than the value it carries says so here instead, and the
 session applies it. */
nonisolated struct ISupportEffects: Sendable, Equatable {
	/** A capability an ISUPPORT token stands in for on a server that never
	 offered it through `CAP`, and the pre-CAP line that turns it on. */
	nonisolated struct LegacyCapability: Sendable, Equatable {
		let capability: CapabilitySet
		let command: String
	}

	/// Capabilities the tokens prove the server has.
	var enabledCapabilities: CapabilitySet = []
	/// Capability facts the tokens that went away took with them.
	var withdrawnCapabilities: CapabilitySet = []
	/// Legacy capabilities to turn on, in the order their tokens arrived.
	var legacyCapabilities: [LegacyCapability] = []
}
