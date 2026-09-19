// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import Foundation
import SwiftUI

/** The rows of the sidebar. The filter field that narrows them belongs to the
 window toolbar, not to this list: `MainWindowRootView` owns it and writes
 through `Sidebar.filterText`. */
struct SidebarView: View {
	let model: Sidebar
	let redirectTyping: (String) -> Void

	var body: some View {
		List(selection: selection) {
			/* A real outline rather than a hand-rolled chevron and a literal
			 indent: the disclosure control, the left and right arrow keys that
			 work it, the Option-click that opens every server at once and the
			 Expand/Collapse VoiceOver announces all come with it. */
			ForEach(model.rows) { server in
				if server.showsDisclosure {
					DisclosureGroup(isExpanded: disclosure(of: server)) {
						conversationRows(server)
					} label: {
						ServerRowView(server: server)
					}
					.tag(server.id)
				} else {
					ServerRowView(server: server)
						.tag(server.id)
				}
			}
			/* Reordering is the list's own, which is what draws the insertion
			 line between rows and keeps the drag off the pasteboard: the row
			 used to export its identifier, so dropping a conversation into any
			 other application pasted a bare UUID. */
			.onMove { offsets, destination in
				model.moveServers(fromOffsets: offsets, toOffset: destination)
			}
		}
		.listStyle(.sidebar)
		/* No forced overlay scrollers here, and the member list beside it still
		 has them. Writing the scroller style onto the list's own scroll view is
		 a write AppKit answers by tiling it, and the tile resizes the outline
		 inside SwiftUI's next list update: the outline lays a row out there to
		 place its disclosure control, the row's hosting view renders inside the
		 update that is already running, and the process aborts with
		 "AttributeGraph precondition failure: setting value during update".
		 Measured at launch with the reader's own servers: every run with the
		 style forced, none without. Only an outline runs that row layout, which
		 is why the flat lists keep the modifier. */
		.accessibilityIdentifier("sidebar")
		.scrollContentBackground(.hidden)
		/* A filter that matches nothing left a blank sidebar, which reads as a
		 lost account rather than as a search with no answer. */
		.overlay {
			if model.hasNoFilterMatches {
				ContentUnavailableView.search(text: model.filterText)
			}
		}
		.contextMenu(forSelectionType: String.self) { identifiers in
			let clickedItem = identifiers.first.flatMap(model.item(withID:))
			if let commands = AppServices.delegate.menuController,
			   let menu = commands.contextMenu(for: clickedItem)
			{
				MenuContentView(menu: menu.menu, context: menu.context) {
					if let clickedItem {
						model.selectFromSwiftUI(clickedItem.uniqueIdentifier)
					}
				}
			}
		} primaryAction: { identifiers in
			guard let identifier = identifiers.first else { return }
			model.selectFromSwiftUI(identifier)
			model.mainWindow?.sidebarItemDoubleClicked()
		}
		.redirectsPrintableInput(to: redirectTyping)
	}

	private func conversationRows(_ server: ServerRow) -> some View {
		ForEach(server.conversations) { conversation in
			ConversationRowView(conversation: conversation)
				.tag(conversation.id)
		}
		.onMove { offsets, destination in
			model.moveConversations(onServerWithID: server.id, fromOffsets: offsets, toOffset: destination)
		}
	}

	private var selection: Binding<String?> {
		Binding(
			get: { model.selectedItemIdentifier },
			set: { model.selectFromSwiftUI($0) }
		)
	}

	private func disclosure(of server: ServerRow) -> Binding<Bool> {
		Binding(
			get: { server.isExpanded },
			set: { model.setExpanded($0, forServerID: server.id) }
		)
	}
}

private struct ServerRowView: View {
	let server: ServerRow

	var body: some View {
		HStack(spacing: UISpacing.regular) {
			Text(server.title)
				.fontWeight(.semibold)
				.foregroundStyle(server.isActive ? Color.primary : Color(nsColor: .tertiaryLabelColor))
				.lineLimit(1)
				.truncationMode(.tail)

			if server.isSecured {
				Image(systemName: "lock.fill")
					.font(.caption2.weight(.semibold))
					.imageScale(.small)
					.foregroundStyle(.secondary)
					/* The row's own label already says the connection is
					 encrypted; the padlock is for the pointer, which has
					 nothing else to read it with. */
					.help(String(localized: .MainWindow.connectionSecurity))
					.accessibilityHidden(true)
			}

			Spacer(minLength: UISpacing.tight)
		}
		/* No fixed height: the sidebar style sizes its own cells, and content
		 pinned shorter than the cell sat 4 pt below its origin, which is where
		 a ghost of the selected row's label was drawn. */
		.contentShape(Rectangle())
		.accessibilityLabel(accessibilityDescription)
	}

	private var accessibilityDescription: String {
		var phrases = [
			server.isActive
				? AccessibilityStrings.connectedServer(server.title)
				: AccessibilityStrings.disconnectedServer(server.title),
		]
		/* The padlock is hidden from assistive technology, so whether the
		 connection is encrypted has to be said here or not at all. */
		if server.isSecured {
			phrases.append(String(localized: .MainWindow.connectionSecurity))
		}
		return phrases.formatted(.list(type: .and))
	}
}

private struct ConversationRowView: View {
	let conversation: ConversationRow

	/// `.increased` is what a list row's ground reports while it is selected.
	/// A row that did not ask drew its own accent on top of the selection's.
	@Environment(\.backgroundProminence) private var backgroundProminence
	@ScaledMetric(relativeTo: .caption) private var badgeWidth: CGFloat = 24
	@ScaledMetric(relativeTo: .caption) private var badgeHeight: CGFloat = 20

	var body: some View {
		HStack(spacing: UISpacing.regular) {
			if let symbolName {
				Image(systemName: symbolName)
					.imageScale(.small)
					.foregroundStyle(conversation.isActive ? .secondary : .tertiary)
					.frame(width: UIListMetrics.glyphWidth)
					.accessibilityHidden(true)
			}

			Text(conversation.title)
				.foregroundStyle(labelColor)
				.lineLimit(1)
				.truncationMode(.tail)

			Spacer(minLength: UISpacing.tight)

			if conversation.showsUnreadBadge {
				Text(conversation.unreadCount, format: .number)
					.font(.system(.caption, design: .rounded, weight: .semibold).monospacedDigit())
					.foregroundStyle(badgeForeground)
					.padding(.horizontal, UISpacing.regular)
					.frame(minWidth: badgeWidth, minHeight: badgeHeight)
					.background(badgeBackground, in: Capsule())
					/* The row's label already counts what is unread for VoiceOver;
					 the tooltip says it to a pointer, which the digits alone do
					 not tell what they are counting. */
					.help(.ChannelSpotlight.unreadMessageCount(conversation.unreadCount))
					.accessibilityHidden(true)
			}
		}
		.contentShape(Rectangle())
		.accessibilityLabel(accessibilityDescription)
	}

	private var isSelected: Bool {
		backgroundProminence == .increased
	}

	private var labelColor: Color {
		if conversation.hasJoinError {
			return Color(nsColor: .systemRed)
		}
		/* The reader's accent, and only while the row is not the selected one:
		 a literal blue on the selection's own blue was a label that could not
		 be read, and it claimed a colour the reader had not chosen. */
		if conversation.isActive, conversation.isEmphasized, isSelected == false {
			return .accentColor
		}
		return conversation.isActive ? .primary : Color(nsColor: .tertiaryLabelColor)
	}

	/// A channel's name already carries its `#`; only a conversation that is
	/// not a channel needs a glyph to say what it is.
	private var symbolName: String? {
		switch conversation.kind {
		case .channel: nil
		case .directChat: "bubble.left.and.bubble.right.fill"
		case .direct, .console: "person.fill"
		}
	}

	/** The chip a badge that asks for attention sits on.

	 `selectedContentBackgroundColor` is the colour the reader chose for
	 selection, and the one AppKit desaturates while the window is not key; the
	 accent colour it replaces answered for neither, so a badge stayed vivid
	 beside a grey selection in a background window. */
	private var badgeFill: NSColor {
		guard conversation.isEmphasized else {
			return .quaternaryLabelColor
		}

		return conversation.unreadBadgeTint ?? .selectedContentBackgroundColor
	}

	private var badgeBackground: Color {
		Color(nsColor: badgeFill)
	}

	/// Black or white, whichever the fill can be read against. The menu text
	/// colour this replaces answered for a menu's ground, not for a capsule the
	/// reader may have tinted any colour at all.
	private var badgeForeground: Color {
		guard conversation.isEmphasized else { return .primary }
		return Color(nsColor: badgeFill.legibleForeground)
	}

	private var accessibilityDescription: String {
		let identity: String = if conversation.kind != .channel {
			AccessibilityStrings.directConversation(with: conversation.title)
		} else if conversation.isActive {
			AccessibilityStrings.joinedChannel(conversation.title)
		} else {
			AccessibilityStrings.unjoinedChannel(conversation.title)
		}

		var phrases = [identity]
		if conversation.unreadCount > 0 {
			phrases.append(String(localized: .ChannelSpotlight.unreadMessageCount(conversation.unreadCount)))
		}
		if conversation.highlightCount > 0 {
			phrases.append(String(localized: .ChannelSpotlight.highlightCount(conversation.highlightCount)))
		}
		return phrases.formatted(.list(type: .and))
	}
}
