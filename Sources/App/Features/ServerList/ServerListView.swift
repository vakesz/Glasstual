/* *********************************************************************
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
import SwiftUI

private enum ServerListLayout {
	static let rowHeight: CGFloat = 28
	static let disclosureWidth: CGFloat = 12
	static let disclosureSpacing: CGFloat = 6
	static let outlineIndentation: CGFloat = 14
	static let channelLeadingPadding = disclosureWidth + disclosureSpacing + outlineIndentation
	static let rowInsets = EdgeInsets(top: 0, leading: 10, bottom: 0, trailing: 10)
}

struct ServerListView: View {
	@Bindable var model: ServerList
	let redirectTyping: (String) -> Void

	var body: some View {
		List(selection: selection) {
			ForEach(model.rows) { server in
				ServerDisclosureRow(model: model, server: server)
					.tag(server.id)
					.listRowInsets(ServerListLayout.rowInsets)
					.listRowSeparator(.hidden)

				ForEach(server.channels) { channel in
					ChannelRowView(model: model, channel: channel)
						.padding(.leading, ServerListLayout.channelLeadingPadding)
						.tag(channel.id)
						.listRowInsets(ServerListLayout.rowInsets)
						.listRowSeparator(.hidden)
				}
			}
		}
		.listStyle(.sidebar)
		.scrollContentBackground(.hidden)
		.searchable(
			text: $model.filterText,
			placement: .sidebar,
			prompt: Text(MainWindowStrings.InputBar.searchChannels)
		)
		.environment(\.defaultMinListRowHeight, ServerListLayout.rowHeight)
		.contextMenu(forSelectionType: String.self) { identifiers in
			if let menu = model.menu(for: identifiers) {
				AppMenuContent(menu: menu) {
					if let identifier = identifiers.first {
						model.selectFromSwiftUI(identifier)
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

	private var selection: Binding<String?> {
		Binding(
			get: { model.selectedItemIdentifier },
			set: { model.selectFromSwiftUI($0) }
		)
	}
}

private struct ServerDisclosureRow: View {
	let model: ServerList
	let server: ServerRow

	var body: some View {
		HStack(spacing: ServerListLayout.disclosureSpacing) {
			Button {
				model.toggleExpanded(serverID: server.id)
			} label: {
				Image(systemName: server.isExpanded ? "chevron.down" : "chevron.right")
					.font(.system(size: 9, weight: .semibold))
					.foregroundStyle(.secondary)
					.frame(width: ServerListLayout.disclosureWidth, height: ServerListLayout.rowHeight)
					.contentShape(Rectangle())
			}
			.buttonStyle(.plain)
			.accessibilityLabel(server.title)

			ServerRowView(model: model, server: server)
		}
	}
}

/// What a server row and a channel row share: the frame, the drag handle and
/// the drop target, keyed by the tree item's identity.
private struct SidebarRowChrome: ViewModifier {
	let model: ServerList
	let id: String
	let accessibilityLabel: String

	func body(content: Content) -> some View {
		content
			.frame(height: ServerListLayout.rowHeight)
			.contentShape(Rectangle())
			.accessibilityLabel(accessibilityLabel)
			.draggable(id)
			.dropDestination(for: String.self) { identifiers, _ in
				guard let identifier = identifiers.first else { return false }
				return model.move(draggedIdentifier: identifier, beforeIdentifier: id)
			}
	}
}

private struct ServerRowView: View {
	let model: ServerList
	let server: ServerRow

	var body: some View {
		HStack(spacing: 7) {
			Text(server.title)
				.fontWeight(.semibold)
				.foregroundStyle(server.isActive ? Color.primary : Color(nsColor: .tertiaryLabelColor))
				.lineLimit(1)
				.truncationMode(.tail)

			if server.isSecured {
				Image(systemName: "lock.fill")
					.font(.system(size: 9, weight: .semibold))
					.foregroundStyle(.secondary)
					.accessibilityLabel(MainWindowStrings.Toolbar.connectionSecurity)
			}

			Spacer(minLength: 4)
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
		HStack(spacing: 7) {
			if let symbolName {
				Image(systemName: symbolName)
					.font(.system(size: 12, weight: .medium))
					.foregroundStyle(channel.isActive ? .secondary : .tertiary)
					.frame(width: 16)
					.accessibilityHidden(true)
			}

			Text(channel.title)
				.foregroundStyle(labelColor)
				.lineLimit(1)
				.truncationMode(.tail)

			Spacer(minLength: 4)

			if channel.showsUnreadBadge {
				Text(channel.unreadCount, format: .number)
					.font(.system(size: 11, weight: .semibold, design: .rounded))
					.monospacedDigit()
					.foregroundStyle(channel.isEmphasized ? Color.white : Color.primary)
					.padding(.horizontal, 7)
					.frame(minWidth: 22, minHeight: 18)
					.background(badgeBackground, in: Capsule())
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

	private var badgeBackground: Color {
		guard channel.isEmphasized else {
			return Color(nsColor: .quaternaryLabelColor)
		}
		if let color = TextualUserDefaults.container
			.storedColor(for: Preferences.Badges.serverListUnreadHighlight),
			color.alphaComponent > 0
		{
			return Color(nsColor: color)
		}
		return .accentColor
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
