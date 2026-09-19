// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit

enum SidebarNodeID: Hashable {
	case server(String)
	case conversation(String)

	var itemIdentifier: String {
		switch self {
		case let .server(identifier), let .conversation(identifier): identifier
		}
	}
}

/// A value delivered to the native outline. Hidden filtered items remain known
/// so removing a filter restores the same node identities.
struct SidebarOutlineSnapshot: Equatable {
	let rows: [ServerRow]
	let selectedIdentifier: String?
	let isFiltering: Bool
	let knownIdentifiers: Set<SidebarNodeID>

	init(model: Sidebar) {
		rows = model.rows
		selectedIdentifier = model.selectedItemIdentifier
		isFiltering = model.isFiltering
		knownIdentifiers = Set(model.sessions.flatMap { session in
			[SidebarNodeID.server(session.uniqueIdentifier)]
				+ session.conversationList.map { SidebarNodeID.conversation($0.uniqueIdentifier) }
		})
	}
}

/// NSOutlineView identifies items by object identity. This object stays alive
/// while its chat item exists; only the snapshot it draws changes.
final class SidebarOutlineNode: NSObject {
	enum Content: Equatable {
		case server(ServerRow)
		case conversation(ConversationRow)
	}

	let identity: SidebarNodeID
	var content: Content
	var children: [SidebarOutlineNode] = []
	var parentIdentifier: String?

	init(identity: SidebarNodeID, content: Content) {
		self.identity = identity
		self.content = content
	}

	var accessibilityDescription: String {
		switch content {
		case let .server(server):
			var phrases = [server.isActive
				? AccessibilityStrings.connectedServer(server.title)
				: AccessibilityStrings.disconnectedServer(server.title)]
			if server.isSecured {
				phrases.append(String(localized: .MainWindow.connectionSecurity))
			}
			return phrases.formatted(.list(type: .and))
		case let .conversation(conversation):
			let identity = if conversation.kind != .channel {
				AccessibilityStrings.directConversation(with: conversation.title)
			} else if conversation.isActive {
				AccessibilityStrings.joinedChannel(conversation.title)
			} else {
				AccessibilityStrings.unjoinedChannel(conversation.title)
			}
			var phrases = [identity]
			if conversation.hasJoinError {
				phrases.append(String(localized: .MainWindow.sidebarJoinFailed))
			}
			if conversation.unreadCount > 0 {
				phrases.append(String(localized: .ChannelSpotlight.unreadMessageCount(conversation.unreadCount)))
			}
			if conversation.highlightCount > 0 {
				phrases.append(String(localized: .ChannelSpotlight.highlightCount(conversation.highlightCount)))
			}
			return phrases.formatted(.list(type: .and))
		}
	}
}

final class SidebarOutlineTree {
	private(set) var roots: [SidebarOutlineNode] = []
	private(set) var nodes: [SidebarNodeID: SidebarOutlineNode] = [:]

	/// Returns whether the outline's hierarchy or order changed. Metadata-only
	/// refreshes do not reload, replace, or animate native rows.
	@discardableResult
	func apply(_ snapshot: SidebarOutlineSnapshot) -> Bool {
		let previousOrder = roots.map { [$0.identity] + $0.children.map(\.identity) }
		roots = snapshot.rows.map { server in
			let parent = node(.server(server.id), content: .server(server))
			parent.children = server.conversations.map { conversation in
				let child = node(.conversation(conversation.id), content: .conversation(conversation))
				child.parentIdentifier = server.id
				return child
			}
			return parent
		}
		nodes = nodes.filter { snapshot.knownIdentifiers.contains($0.key) }
		return previousOrder != roots.map { [$0.identity] + $0.children.map(\.identity) }
	}

	func node(withItemIdentifier identifier: String) -> SidebarOutlineNode? {
		nodes[.server(identifier)] ?? nodes[.conversation(identifier)]
	}

	private func node(_ identity: SidebarNodeID, content: SidebarOutlineNode.Content) -> SidebarOutlineNode {
		if let existing = nodes[identity] {
			existing.content = content
			return existing
		}
		let created = SidebarOutlineNode(identity: identity, content: content)
		nodes[identity] = created
		return created
	}
}
