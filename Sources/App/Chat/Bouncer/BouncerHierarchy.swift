// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** Which connections are accounts and which are networks of an account.

 The chat session keeps one flat list. A network connection nests under the
 connection it was discovered on, in the order the flat list holds them; one
 whose account is gone is shown at the top level rather than lost. */
@MainActor
struct BouncerHierarchy {
	/// Every connection that is not nested under another.
	let roots: [ServerSession]
	private let childrenByParent: [String: [ServerSession]]

	init(sessions: [ServerSession]) {
		let present = Set(sessions.map(\.uniqueIdentifier))
		var roots: [ServerSession] = []
		var children: [String: [ServerSession]] = [:]
		for session in sessions {
			if let parent = session.config.bouncerNetwork?.parentIdentifier, present.contains(parent) {
				children[parent, default: []].append(session)
			} else {
				roots.append(session)
			}
		}
		self.roots = roots
		childrenByParent = children
	}

	func children(of session: ServerSession) -> [ServerSession] {
		childrenByParent[session.uniqueIdentifier] ?? []
	}

	/// Parents followed by their networks, in the order the sidebar draws them.
	var ordered: [ServerSession] {
		roots.flatMap { [$0] + children(of: $0) }
	}
}
