// Copyright (c) 2017, 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

/** What the listener does with a connecting peer, decided from the
 code-signing requirement it could build and whether this build may go on
 without one.

 A requirement is always enforced. Without one there is nothing to check the
 peer against, so only a build that allows unverified peers (Debug) accepts it;
 any other build refuses. */
nonisolated enum ConnectionPeerAdmission: Equatable {
	case enforce(requirement: String)
	case acceptUnverified
	case refuse

	static func decide(requirement: String?, allowsUnverifiedPeer: Bool) -> Self {
		if let requirement {
			return .enforce(requirement: requirement)
		}
		return allowsUnverifiedPeer ? .acceptUnverified : .refuse
	}
}
