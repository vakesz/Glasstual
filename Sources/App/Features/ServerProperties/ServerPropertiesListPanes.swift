// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import SwiftUI

/* The Server Properties window's three editable lists. Each is the same
 bordered list with the same add and remove buttons under it, which is what
 `ServerPropertiesListKind` names; what differs is the row. A row is edited by
 double-clicking it or pressing Return. */

struct ServerPropertiesChannelListPane: View {
	@Bindable var model: ServerPropertiesModel
	/// Weak for the same reason `ServerPropertiesView`'s is: the editor holds
	/// the view that holds this pane.
	weak var commands: (any ServerPropertiesCommands)?

	var body: some View {
		VStack(alignment: .leading, spacing: UISpacing.regular) {
			List(selection: $model.selectedChannelID) {
				ForEach(model.displayedChannels, id: \.uniqueIdentifier) { channel in
					HStack {
						Toggle(
							.ChannelProperties.joinOnConnect,
							isOn: autoJoinBinding(channel.uniqueIdentifier)
						).labelsHidden()
						Text(verbatim: channel.name)
						Spacer()
						if model.channelHasSecretKey(channel) {
							Image(systemName: "key.fill")
								.accessibilityLabel(.ChannelProperties.passwordLabel)
						}
					}.tag(channel.uniqueIdentifier)
				}
			}
			.listCommands(.channels, commands: commands, selection: $model.selectedChannelID)
			.overlay {
				if model.displayedChannels.isEmpty {
					ServerPropertiesEmptyList(kind: .channels)
				}
			}

			ServerPropertiesListButtons(
				kind: .channels,
				hasSelection: model.selectedChannelID != nil,
				commands: commands
			)
		}
		.padding(SheetMetrics.margin)
	}

	private func autoJoinBinding(_ identifier: String) -> Binding<Bool> {
		Binding(
			get: { model.config.conversationList.first { $0.uniqueIdentifier == identifier }?.autoJoin ?? false },
			set: { value in
				guard let index = model.config.conversationList.firstIndex(where: { $0.uniqueIdentifier == identifier })
				else { return }
				model.config.conversationList[index].autoJoin = value
			}
		)
	}
}

struct ServerPropertiesHighlightsPane: View {
	@Bindable var model: ServerPropertiesModel
	weak var commands: (any ServerPropertiesCommands)?

	var body: some View {
		VStack(alignment: .leading, spacing: UISpacing.regular) {
			List(selection: $model.selectedHighlightID) {
				ForEach(model.config.highlightList, id: \.uniqueIdentifier) { entry in
					VStack(alignment: .leading) {
						Text(verbatim: entry.matchKeyword)
						Text(HighlightMatchBehavior(excludesMatches: entry.matchIsExcluded).title)
							.font(.caption).foregroundStyle(.secondary)
					}.tag(entry.uniqueIdentifier)
				}
			}
			.listCommands(.highlights, commands: commands, selection: $model.selectedHighlightID)
			.overlay {
				if model.config.highlightList.isEmpty {
					ServerPropertiesEmptyList(kind: .highlights)
				}
			}

			ServerPropertiesListButtons(
				kind: .highlights,
				hasSelection: model.selectedHighlightID != nil,
				commands: commands
			)
		}
		.padding(SheetMetrics.margin)
	}
}

private struct ServerPropertiesEmptyList: View {
	let kind: ServerPropertiesListKind

	var body: some View {
		ContentUnavailableView(
			String(localized: kind.emptyTitle),
			systemImage: kind.pane.symbol,
			description: Text(kind.emptyDescription)
		)
	}
}

/// Add and remove under a list whose plus adds one kind of entry.
private struct ServerPropertiesListButtons: View {
	let kind: ServerPropertiesListKind
	let hasSelection: Bool
	weak var commands: (any ServerPropertiesCommands)?

	var body: some View {
		ListEditingControls(
			addLabel: Text(kind.addLabel),
			removeLabel: Text(kind.removeLabel),
			canRemove: hasSelection,
			add: { kind.add(with: commands) },
			remove: { kind.remove(with: commands) }
		)
	}
}

private extension View {
	/** The keyboard and context menu every one of the window's lists answers to.

	 `primaryAction` is the double-click and Return at once, which is how a row
	 is edited; Delete removes it. The context menu offers only what applies to
	 the rows it was opened on. */
	func listCommands(
		_ kind: ServerPropertiesListKind,
		commands: (any ServerPropertiesCommands)?,
		selection: Binding<String?>
	) -> some View {
		onDeleteCommand { kind.remove(with: commands) }
			.listStyle(.bordered)
			.contextMenu(forSelectionType: String.self) { identifiers in
				if identifiers.count == 1 {
					Button(kind.editLabel) {
						selection.wrappedValue = identifiers.first
						kind.edit(with: commands)
					}
					Divider()
				}
				if identifiers.isEmpty == false {
					Button(kind.removeLabel, role: .destructive) {
						selection.wrappedValue = identifiers.first
						kind.remove(with: commands)
					}
				}
			} primaryAction: { identifiers in
				guard identifiers.count == 1 else { return }
				selection.wrappedValue = identifiers.first
				kind.edit(with: commands)
			}
	}
}
