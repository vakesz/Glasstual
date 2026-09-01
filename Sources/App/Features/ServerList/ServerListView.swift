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
			ForEach(model.clients, id: \.uniqueIdentifier) { client in
				ServerDisclosureRow(model: model, client: client)
					.tag(client.uniqueIdentifier)
					.listRowInsets(ServerListLayout.rowInsets)
					.listRowSeparator(.hidden)

				if model.isExpanded(client) {
					ForEach(client.channelList, id: \.uniqueIdentifier) { channel in
						ServerListRow(model: model, item: channel)
							.padding(.leading, ServerListLayout.channelLeadingPadding)
							.tag(channel.uniqueIdentifier)
							.listRowInsets(ServerListLayout.rowInsets)
							.listRowSeparator(.hidden)
					}
				}
			}
		}
		.listStyle(.plain)
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
		.overlay {
			Color.clear
				.id(model.presentationRevision)
				.allowsHitTesting(false)
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
	let client: IRCClient

	var body: some View {
		HStack(spacing: ServerListLayout.disclosureSpacing) {
			Button {
				model.setExpanded(model.isExpanded(client) == false, for: client)
			} label: {
				Image(systemName: model.isExpanded(client) ? "chevron.down" : "chevron.right")
					.font(.system(size: 9, weight: .semibold))
					.foregroundStyle(.secondary)
					.frame(width: ServerListLayout.disclosureWidth, height: ServerListLayout.rowHeight)
					.contentShape(Rectangle())
			}
			.buttonStyle(.plain)
			.accessibilityLabel(client.label)

			ServerListRow(model: model, item: client)
		}
	}
}

private struct ServerListRow: View {
	let model: ServerList
	let item: IRCTreeItem

	var body: some View {
		HStack(spacing: 7) {
			if let channel = item as? IRCChannel {
				Image(systemName: symbolName(for: channel))
					.font(.system(size: 12, weight: .medium))
					.foregroundStyle(channel.isActive ? .secondary : .tertiary)
					.frame(width: 16)
					.accessibilityHidden(true)
			}

			Text(item.label)
				.fontWeight(item.isClient ? .semibold : .regular)
				.foregroundStyle(labelColor)
				.lineLimit(1)
				.truncationMode(.tail)

			if let client = item as? IRCClient, client.isSecured {
				Image(systemName: "lock.fill")
					.font(.system(size: 9, weight: .semibold))
					.foregroundStyle(.secondary)
					.accessibilityLabel(MainWindowStrings.Toolbar.connectionSecurity)
			}

			Spacer(minLength: 4)

			if let channel = item as? IRCChannel,
			   channel.config.showTreeBadgeCount,
			   channel.treeUnreadCount > 0
			{
				Text(channel.treeUnreadCount, format: .number)
					.font(.system(size: 11, weight: .medium, design: .monospaced))
					.foregroundStyle(badgeForeground(for: channel))
					.padding(.horizontal, 7)
					.frame(minWidth: 22, minHeight: 16)
					.background(badgeBackground(for: channel), in: Capsule())
					.accessibilityHidden(true)
			}
		}
		.frame(height: ServerListLayout.rowHeight)
		.contentShape(Rectangle())
		.accessibilityLabel(accessibilityDescription)
		.draggable(item.uniqueIdentifier)
		.dropDestination(for: String.self) { identifiers, _ in
			guard let identifier = identifiers.first else { return false }
			return model.move(draggedIdentifier: identifier, before: item)
		}
	}

	private var labelColor: Color {
		guard let channel = item as? IRCChannel else { return .primary }
		if channel.errorOnLastJoinAttempt {
			return .red
		}
		if channel.isActive, channel.nicknameHighlightCount > 0, channel.config.ignoreHighlights == false {
			return .blue
		}
		return channel.isActive ? .primary : Color(nsColor: .tertiaryLabelColor)
	}

	private func symbolName(for channel: IRCChannel) -> String {
		if channel.isChannel {
			return "number"
		}
		if channel.isDirectChat {
			return "bubble.left.and.bubble.right.fill"
		}
		return "person.fill"
	}

	private func badgeBackground(for channel: IRCChannel) -> Color {
		guard channel.nicknameHighlightCount > 0, channel.config.ignoreHighlights == false else {
			return Color(nsColor: .secondarySystemFill)
		}
		if let color = TextualUserDefaults.container
			.storedColor(for: Preferences.Badges.serverListUnreadHighlight),
			color.alphaComponent > 0
		{
			return Color(nsColor: color)
		}
		return .accentColor
	}

	private func badgeForeground(for channel: IRCChannel) -> Color {
		channel.nicknameHighlightCount > 0 && channel.config.ignoreHighlights == false ? .white : .secondary
	}

	private var accessibilityDescription: String {
		if let client = item as? IRCClient {
			return client.isActive
				? AccessibilityStrings.connectedServer(client.label)
				: AccessibilityStrings.disconnectedServer(client.label)
		}

		guard let channel = item as? IRCChannel else { return item.label }
		var description: String = if channel.isChannel == false {
			AccessibilityStrings.privateMessageQuery(with: channel.label)
		} else if channel.isActive {
			AccessibilityStrings.joinedChannel(channel.label)
		} else {
			AccessibilityStrings.unjoinedChannel(channel.label)
		}

		if channel.treeUnreadCount > 0 {
			description = ChannelSpotlightStrings.combined(
				description,
				ChannelSpotlightStrings.unreadMessages(channel.treeUnreadCount)
			)
		}
		if channel.nicknameHighlightCount > 0, channel.config.ignoreHighlights == false {
			description = ChannelSpotlightStrings.combined(
				description,
				ChannelSpotlightStrings.highlights(channel.nicknameHighlightCount)
			)
		}
		return description
	}
}
