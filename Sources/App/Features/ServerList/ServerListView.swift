/* *********************************************************************
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
import SwiftUI

/// The unread badge's own size, and nothing else. Everything the sidebar is
/// spaced and sized by is `UISpacing` and `UIListMetrics`, which the member
/// list beside it shares; indentation, row insets and the disclosure control
/// belong to the sidebar list style.
private enum ServerListLayout {
	static let badgeWidth: CGFloat = 24
	static let badgeHeight: CGFloat = 20
}

/** The rows of the sidebar. The filter field that narrows them belongs to the
 window toolbar, not to this list: `MainWindowRootView` owns it and writes
 through `ServerList.filterText`. */
struct ServerListView: View {
	let model: ServerList
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
						channelRows(server)
					} label: {
						ServerRowView(model: model, server: server)
					}
					.tag(server.id)
					.listRowSeparator(.hidden)
				} else {
					ServerRowView(model: model, server: server)
						.tag(server.id)
						.listRowSeparator(.hidden)
				}
			}
		}
		.listStyle(.sidebar)
		.overlayScrollers()
		.accessibilityIdentifier("server-list")
		.scrollContentBackground(.hidden)
		/* A filter that matches nothing left a blank sidebar, which reads as a
		 lost account rather than as a search with no answer. */
		.overlay {
			if model.hasNoFilterMatches {
				ContentUnavailableView.search(text: model.filterText)
			}
		}
		.contextMenu(forSelectionType: String.self) { identifiers in
			if let menu = model.menu(for: identifiers) {
				AppMenuContent(menu: menu.menu, context: menu.context) {
					if let item = menu.context.treeItem {
						model.selectFromSwiftUI(item.uniqueIdentifier)
					}
				}
			}
		} primaryAction: { identifiers in
			guard let identifier = identifiers.first else { return }
			model.selectFromSwiftUI(identifier)
			model.mainWindow?.serverListItemDoubleClicked()
		}
		.redirectsPrintableInput(to: redirectTyping)
	}

	private func channelRows(_ server: ServerRow) -> some View {
		ForEach(server.channels) { channel in
			ChannelRowView(model: model, channel: channel)
				.tag(channel.id)
				.listRowSeparator(.hidden)
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

/// What a server row and a channel row share: the frame, the drag handle and
/// the drop target, keyed by the tree item's identity.
private struct SidebarRowChrome: ViewModifier {
	let model: ServerList
	let id: String
	let accessibilityLabel: String

	func body(content: Content) -> some View {
		/* No fixed height: the sidebar style sizes its own cells, and content
		 pinned shorter than the cell sat 4 pt below its origin, which is where
		 a ghost of the selected row's label was drawn. */
		content
			.contentShape(Rectangle())
			.accessibilityLabel(accessibilityLabel)
			.draggable(id)
			.dropDestination(for: String.self) { identifiers, _ in
				guard let identifier = identifiers.first else { return false }
				return model.move(draggedIdentifier: identifier, ontoIdentifier: id)
			}
	}
}

private struct ServerRowView: View {
	let model: ServerList
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
					.font(.system(size: 9, weight: .semibold))
					.foregroundStyle(.secondary)
					.help(MainWindowStrings.Toolbar.connectionSecurity)
					.accessibilityLabel(MainWindowStrings.Toolbar.connectionSecurity)
			}

			Spacer(minLength: UISpacing.tight)
		}
		.modifier(SidebarRowChrome(model: model, id: server.id, accessibilityLabel: accessibilityDescription))
	}

	private var accessibilityDescription: String {
		server.isActive
			? AccessibilityStrings.connectedServer(server.title)
			: AccessibilityStrings.disconnectedServer(server.title)
	}
}

private struct ChannelRowView: View {
	let model: ServerList
	let channel: ChannelRow

	var body: some View {
		HStack(spacing: UISpacing.regular) {
			if let symbolName {
				Image(systemName: symbolName)
					.font(.system(size: 12, weight: .medium))
					.foregroundStyle(channel.isActive ? .secondary : .tertiary)
					.frame(width: UIListMetrics.glyphWidth)
					.accessibilityHidden(true)
			}

			Text(channel.title)
				.foregroundStyle(labelColor)
				.lineLimit(1)
				.truncationMode(.tail)

			Spacer(minLength: UISpacing.tight)

			if channel.showsUnreadBadge {
				Text(channel.unreadCount, format: .number)
					.font(.system(size: 11, weight: .semibold, design: .rounded))
					.monospacedDigit()
					.foregroundStyle(badgeForeground)
					.padding(.horizontal, UISpacing.regular)
					.frame(minWidth: ServerListLayout.badgeWidth, minHeight: ServerListLayout.badgeHeight)
					.background(badgeBackground, in: Capsule())
					/* The row's label already counts what is unread for VoiceOver;
					 the tooltip says it to a pointer, which the digits alone do
					 not tell what they are counting. */
					.help(ChannelSpotlightStrings.unreadMessages(channel.unreadCount))
					.accessibilityHidden(true)
			}
		}
		.modifier(SidebarRowChrome(model: model, id: channel.id, accessibilityLabel: accessibilityDescription))
	}

	private var labelColor: Color {
		if channel.hasJoinError {
			return .red
		}
		if channel.isActive, channel.isEmphasized {
			return .blue
		}
		return channel.isActive ? .primary : Color(nsColor: .tertiaryLabelColor)
	}

	/// A channel's name already carries its `#`; only a conversation that is
	/// not a channel needs a glyph to say what it is.
	private var symbolName: String? {
		switch channel.kind {
		case .channel: nil
		case .directChat: "bubble.left.and.bubble.right.fill"
		case .privateMessage, .utility: "person.fill"
		}
	}

	/** The chip a badge that asks for attention sits on.

	 `selectedContentBackgroundColor` is the colour the reader chose for
	 selection, and the one AppKit desaturates while the window is not key; the
	 accent colour it replaces answered for neither, so a badge stayed vivid
	 beside a grey selection in a background window. */
	private var badgeBackground: Color {
		guard channel.isEmphasized else {
			return Color(nsColor: .quaternaryLabelColor)
		}

		return channel.unreadBadgeTint ?? Color(nsColor: .selectedContentBackgroundColor)
	}

	private var badgeForeground: Color {
		channel.isEmphasized ? Color(nsColor: .selectedMenuItemTextColor) : .primary
	}

	private var accessibilityDescription: String {
		var description: String = if channel.kind != .channel {
			AccessibilityStrings.privateMessageQuery(with: channel.title)
		} else if channel.isActive {
			AccessibilityStrings.joinedChannel(channel.title)
		} else {
			AccessibilityStrings.unjoinedChannel(channel.title)
		}

		if channel.unreadCount > 0 {
			description = ChannelSpotlightStrings.combined(
				description,
				ChannelSpotlightStrings.unreadMessages(channel.unreadCount)
			)
		}
		if channel.highlightCount > 0 {
			description = ChannelSpotlightStrings.combined(
				description,
				ChannelSpotlightStrings.highlights(channel.highlightCount)
			)
		}
		return description
	}
}
