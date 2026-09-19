// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import SwiftUI

/* The connection sheet's three editable lists. Each is the same list with the
 same three buttons over different contents, which is what
 `ServerPropertiesListKind` names; what differs is the row. */

struct ServerPropertiesChannelListPane: View {
	@Bindable var model: ServerPropertiesModel
	/// Weak for the same reason `ServerPropertiesView`'s is: the sheet holds the
	/// view that holds this pane.
	weak var commands: (any ServerPropertiesCommands)?

	var body: some View {
		VStack(alignment: .leading, spacing: UISpacing.wide) {
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

			ServerPropertiesListButtons(
				kind: .channels,
				hasSelection: model.selectedChannelID != nil,
				commands: commands
			)
		}
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
		VStack(alignment: .leading, spacing: UISpacing.wide) {
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

			ServerPropertiesListButtons(
				kind: .highlights,
				hasSelection: model.selectedHighlightID != nil,
				commands: commands
			)
		}
	}
}

struct ServerPropertiesAddressBookPane: View {
	@Bindable var model: ServerPropertiesModel
	weak var commands: (any ServerPropertiesCommands)?

	var body: some View {
		VStack(alignment: .leading, spacing: UISpacing.wide) {
			List(selection: $model.selectedAddressBookEntryID) {
				ForEach(model.config.ignoreList, id: \.uniqueIdentifier) { entry in
					VStack(alignment: .leading) {
						Text(verbatim: entry.hostmask)
						Text(entry.entryType.listTitle)
							.font(.caption).foregroundStyle(.secondary)
					}.tag(entry.uniqueIdentifier)
				}
			}
			.listCommands(.addressBook, commands: commands, selection: $model.selectedAddressBookEntryID)

			HStack {
				/* A menu rather than a button, because an entry is either an
				 ignore or a tracked user and this one list holds both. */
				Menu {
					Button(.ServerProperties.addUserIgnoreEntry) { commands?.addIgnoreEntry() }
					Button(.ServerProperties.addUserTrackingEntry) { commands?.addTrackingEntry() }
				} label: {
					Image(systemName: "plus")
				}
				.menuIndicator(.hidden)
				.help(ServerPropertiesListKind.addressBook.addLabel)
				.accessibilityLabel(ServerPropertiesListKind.addressBook.addLabel)

				ServerPropertiesListEditButtons(
					kind: .addressBook,
					hasSelection: model.selectedAddressBookEntryID != nil,
					commands: commands
				)
				Spacer()
			}
			.buttonStyle(.borderless)
			.padding(.horizontal, SheetMetrics.margin)
			.padding(.bottom, UISpacing.wide)
		}
	}
}

/// Add, edit and remove under a list whose plus adds one kind of entry.
private struct ServerPropertiesListButtons: View {
	let kind: ServerPropertiesListKind
	let hasSelection: Bool
	weak var commands: (any ServerPropertiesCommands)?

	var body: some View {
		HStack {
			Button { kind.add(with: commands) } label: { Image(systemName: "plus") }
				.help(kind.addLabel)
				.accessibilityLabel(kind.addLabel)
			ServerPropertiesListEditButtons(kind: kind, hasSelection: hasSelection, commands: commands)
			Spacer()
		}
		.buttonStyle(.borderless)
		.padding(.horizontal, SheetMetrics.margin)
		.padding(.bottom, UISpacing.wide)
	}
}

/** Edit and remove the selected row.

 Every button under these lists is an icon and nothing else, so each one carries
 the name of what it does -- as a help tag for the pointer and as a label for
 VoiceOver. */
private struct ServerPropertiesListEditButtons: View {
	let kind: ServerPropertiesListKind
	let hasSelection: Bool
	weak var commands: (any ServerPropertiesCommands)?

	var body: some View {
		Button { kind.edit(with: commands) } label: { Image(systemName: "pencil") }
			.disabled(hasSelection == false)
			.help(kind.editLabel)
			.accessibilityLabel(kind.editLabel)
		Button(role: .destructive) { kind.remove(with: commands) } label: { Image(systemName: "minus") }
			.disabled(hasSelection == false)
			.help(kind.removeLabel)
			.accessibilityLabel(kind.removeLabel)
	}
}

private extension View {
	/** The keyboard and context menu every one of the sheet's lists answers to.

	 The three lists were selection and two buttons and nothing else: Delete did
	 nothing, a secondary click offered nothing, and opening a row meant finding
	 the pencil. `primaryAction` is the double-click and Return at once. */
	func listCommands(
		_ kind: ServerPropertiesListKind,
		commands: (any ServerPropertiesCommands)?,
		selection: Binding<String?>
	) -> some View {
		onDeleteCommand { kind.remove(with: commands) }
			.contextMenu(forSelectionType: String.self) { identifiers in
				Button(kind.editLabel) {
					selection.wrappedValue = identifiers.first
					kind.edit(with: commands)
				}
				.disabled(identifiers.count != 1)
				Divider()
				Button(kind.removeLabel, role: .destructive) {
					selection.wrappedValue = identifiers.first
					kind.remove(with: commands)
				}
				.disabled(identifiers.isEmpty)
			} primaryAction: { identifiers in
				guard identifiers.count == 1 else { return }
				selection.wrappedValue = identifiers.first
				kind.edit(with: commands)
			}
	}
}
