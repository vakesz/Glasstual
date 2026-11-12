// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import SwiftUI

struct ChannelMaskListScene: Scene {
	let window: ChannelMaskListWindow

	var body: some Scene {
		WindowGroup(
			String(localized: .ChannelProperties.accessList),
			id: ApplicationSceneID.channelMaskList,
			for: SingletonSceneValue.self
		) { _ in
			ChannelMaskListSceneRoot(window: window)
		} defaultValue: { .instance }
			/* A list of the channel's current bans, not a document: what it shows is
			 whatever the server answers when it is opened, so there is nothing worth
			 restoring into an empty table on the next launch. */
			.restorationBehavior(.disabled)
	}
}

private struct ChannelMaskListSceneRoot: View {
	let window: ChannelMaskListWindow

	var body: some View {
		if let session = window.current {
			ChannelMaskListView(session: session)
				.navigationTitle(session.heading)
				.onDisappear {
					window.didClose()
				}
		} else {
			ContentUnavailableView(
				String(localized: .ChannelProperties.emptyTitle),
				systemImage: "checkmark.shield",
				description: Text(.ChannelProperties.emptyDescription)
			)
			.frame(minWidth: 480, minHeight: 300)
		}
	}
}

struct ChannelMaskListView: View {
	let session: ChannelMaskListSession

	@FocusState private var fieldIsFocused: Bool

	var body: some View {
		@Bindable var model = session.model
		let canEdit = session.canEdit

		VStack(spacing: 0) {
			editor(canEdit: canEdit)

			Table(model.entries, selection: $model.selection, sortOrder: $model.sortOrder) {
				TableColumn(
					.ChannelProperties.hostmask,
					sortUsing: ChannelMaskListComparator(field: .mask, order: .forward)
				) { entry in
					Text(verbatim: entry.entryMask)
						.lineLimit(1)
						.help(entry.entryMaskDescription ?? entry.entryMask)
						.accessibilityLabel(
							String(
								localized: .ChannelProperties.rowDescription(
									entry.entryMask,
									entry.entryAuthor,
									entry.entryCreationDateString
								)
							)
						)
				}
				.width(min: 220, ideal: 360)

				TableColumn(
					.ChannelProperties.addedBy,
					sortUsing: ChannelMaskListComparator(field: .author, order: .forward)
				) { entry in
					Text(verbatim: entry.entryAuthor).lineLimit(1)
				}
				.width(min: 100, ideal: 140)

				TableColumn(
					.ChannelProperties.created,
					sortUsing: ChannelMaskListComparator(field: .creationDate, order: .forward)
				) { entry in
					Text(verbatim: entry.entryCreationDateString).lineLimit(1)
				}
				.width(min: 120, ideal: 160)
			}
			.overlay {
				if model.entries.isEmpty, model.isRefreshing == false {
					ContentUnavailableView(
						String(localized: session.maskKind.emptyTitle),
						systemImage: "checkmark.shield",
						description: Text(.ChannelProperties.emptyDescription)
					)
				}
			}
			.alternatingRowBackgrounds(model.entries.isEmpty ? .disabled : .enabled)
			.copyable(model.selectedMasks)
			.onDeleteCommand(perform: session.removeSelectedEntries)
			.contextMenu(forSelectionType: ChannelMaskListEntry.ID.self) { selection in
				/* Only what can be done to these rows: an operator command the
				 reader is not allowed to send is not offered at all. */
				if canEdit, selection.count == 1 {
					Button(.ChannelProperties.editSelected) {
						model.selection = selection
						edit()
					}
				}
				if canEdit, selection.isEmpty == false {
					Button(.ChannelProperties.removeSelected, role: .destructive) {
						model.selection = selection
						session.removeSelectedEntries()
					}
				}
			} primaryAction: { selection in
				model.selection = selection
				edit()
			}
			.onChange(of: model.sortOrder) { _, newOrder in model.sort(using: newOrder) }
			.accessibilityLabel(.ChannelProperties.accessList)

			if let notice = model.truncationNotice {
				Text(notice)
					.font(.callout)
					.foregroundStyle(.secondary)
					.frame(maxWidth: .infinity, alignment: .leading)
					.padding(.horizontal, SheetMetrics.margin)
					.padding(.top, UISpacing.regular)
			}

			/* Add, remove and the list's other commands under the table, as
			 every editable list has them. An entry is edited by
			 double-clicking it or pressing Return. */
			ListEditingControls(
				addLabel: Text(.ChannelProperties.addEntryButton),
				removeLabel: Text(.ChannelProperties.removeSelected),
				canAdd: canEdit,
				canRemove: canEdit && model.selection.isEmpty == false,
				add: beginAdding,
				remove: session.removeSelectedEntries
			) {
				Button(.ChannelProperties.editSelected, action: edit)
					.keyboardShortcut("e", modifiers: .command)
					.disabled(canEdit == false || model.selection.count != 1)
			}
			.padding(.horizontal, UISpacing.wide)
			.padding(.vertical, UISpacing.regular)
		}
		.frame(
			minWidth: 580,
			idealWidth: 680,
			minHeight: 320,
			idealHeight: 400
		)
		/* How much of the list arrived is a subtitle, as in the channel list
		 window; refreshing it is the window's toolbar command. */
		.navigationSubtitle(model.entryCountDescription)
		.toolbar {
			ToolbarItem(placement: .primaryAction) {
				if model.isRefreshing {
					ProgressView()
						.controlSize(.small)
						.accessibilityLabel(.ChannelProperties.loadingList)
				} else {
					Button(action: session.updateList) {
						Label(.ChannelProperties.updateList, systemImage: "arrow.clockwise")
					}
					.keyboardShortcut("r", modifiers: .command)
					.help(Text(.ChannelProperties.updateList))
				}
			}
		}
		.defaultFocus($fieldIsFocused, true)
	}

	/// The field above the table: add an entry, or replace the one being edited.
	@ViewBuilder
	private func editor(canEdit: Bool) -> some View {
		@Bindable var model = session.model

		/* The tooltip is applied only when the field is read-only:
		 `help("")` installs an empty tooltip that AppKit draws as an empty box. */
		let field = TextField(text: $model.draft, prompt: Text(.ChannelProperties.addPlaceholder)) {
			Text(.ChannelProperties.addFieldLabel)
		}
		.focused($fieldIsFocused)
		.onExitCommand {
			if model.editingMask != nil {
				session.cancelEditing()
			}
		}
		.disabled(canEdit == false)

		VStack(alignment: .leading, spacing: UISpacing.tight) {
			HStack(spacing: UISpacing.regular) {
				if canEdit {
					field
				} else {
					field.help(String(localized: .ChannelProperties.noPermissionHint))
				}

				if model.editingMask != nil {
					Button(.ChannelProperties.cancelEdit, action: session.cancelEditing)
					Button(.ChannelProperties.replaceButton, action: session.submitDraft)
						.keyboardShortcut(.defaultAction)
						.disabled(canEdit == false)
				} else {
					Button(.ChannelProperties.addButton, action: session.submitDraft)
						.keyboardShortcut(.defaultAction)
						.disabled(canEdit == false || model.draft.isEmpty)
				}
			}

			if canEdit == false {
				Text(.ChannelProperties.noPermissionHint)
					.font(.callout)
					.foregroundStyle(.secondary)
			} else if let mask = model.editingMask {
				Text(.ChannelProperties.editingLabel(mask))
					.font(.callout)
					.foregroundStyle(.secondary)
			}

			if let issue = model.issue {
				ValidationMessageLabel(issue.message)
			}
		}
		.padding(.horizontal, SheetMetrics.margin)
		.padding(.vertical, UISpacing.wide)
	}

	private func edit() {
		session.beginEditingSelectedEntry()
		fieldIsFocused = true
	}

	/// The plus starts a new entry in the field above the table.
	private func beginAdding() {
		if session.model.editingMask != nil {
			session.cancelEditing()
		}
		fieldIsFocused = true
	}
}
