// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import SwiftUI

struct ServerEndpointListView: View {
	@Bindable var model: ServerEndpointListModel
	let submit: () -> Void
	let cancel: () -> Void

	var body: some View {
		VStack(spacing: 0) {
			SheetHeading(.ServerProperties.endpointListWindowTitle, subtitle: Text(.ServerProperties.explanation))

			endpointTable

			VStack(alignment: .leading, spacing: UISpacing.tight) {
				ForEach(model.faults, id: \.self) { fault in
					ValidationMessageLabel(String(localized: fault.message))
				}
				Text(.ServerProperties.endpointListServerPasswordHelp)
					.font(.caption)
					.foregroundStyle(.secondary)
			}
			.frame(maxWidth: .infinity, alignment: .leading)
			.padding(.horizontal, SheetMetrics.margin)
			.padding(.vertical, UISpacing.regular)

			/* The list is handed back to the connection sheet, which is what
			 saves it. */
			SheetActions(
				confirmTitle: .sheetConfirmation,
				confirmIsDisabled: model.faults.isEmpty == false,
				confirm: submit,
				cancel: cancel
			) {
				Button(action: model.addEntry) {
					Image(systemName: "plus")
				}
				.help(.ServerProperties.addServer)
				.accessibilityLabel(.ServerProperties.addServer)

				Button(role: .destructive, action: model.removeSelection) {
					Image(systemName: "minus")
				}
				.disabled(model.selectedID == nil)
				.help(.ServerProperties.removeServer)
				.accessibilityLabel(.ServerProperties.removeServer)

				Divider().frame(height: 18)

				Button { model.moveSelection(by: -1) } label: {
					Image(systemName: "arrow.up")
				}
				.disabled(model.canMoveSelectionUp == false)
				.help(.ServerProperties.moveUp)
				.accessibilityLabel(.ServerProperties.moveUp)

				Button { model.moveSelection(by: 1) } label: {
					Image(systemName: "arrow.down")
				}
				.disabled(model.canMoveSelectionDown == false)
				.help(.ServerProperties.moveDown)
				.accessibilityLabel(.ServerProperties.moveDown)
			}
		}
		.frame(
			minWidth: 620,
			idealWidth: 700,
			maxWidth: .infinity,
			minHeight: 360,
			idealHeight: 440,
			maxHeight: .infinity
		)
	}

	/** The endpoints, as a table rather than a stack of rows under hand-drawn
	 headings.

	 A `Table` column names itself, sizes itself and can be resized by the
	 person, none of which the header row of literal widths could do. Its
	 columns hand back the row's value rather than a binding into the list, so
	 the editors take theirs from the model by identity. */
	private var endpointTable: some View {
		Table(of: ServerEndpointDraft.self, selection: $model.selectedID) {
			TableColumn(String(localized: .ServerProperties.serverAddress)) { entry in
				TextField(.ServerProperties.serverAddress, text: model.address(for: entry.id))
					.labelsHidden()
					.accessibilityLabel(.ServerProperties.serverAddress)
			}
			.width(min: 160, ideal: 240)

			TableColumn(String(localized: .ServerProperties.port)) { entry in
				TextField(.ServerProperties.port, text: model.port(for: entry.id))
					.labelsHidden()
					.accessibilityLabel(.ServerProperties.port)
			}
			.width(min: 60, ideal: 80)

			TableColumn(String(localized: .ServerProperties.endpointListSecureColumn)) { entry in
				Toggle(.ServerProperties.endpointListSecureColumn, isOn: model.isSecured(for: entry.id))
					.labelsHidden()
					.accessibilityLabel(.ServerProperties.endpointListSecureColumn)
			}
			.width(min: 52, ideal: 64)

			TableColumn(String(localized: .ServerProperties.serverPassword)) { entry in
				SecureField(.ServerProperties.serverPassword, text: model.password(for: entry.id))
					.labelsHidden()
					.accessibilityLabel(.ServerProperties.serverPassword)
			}
			.width(min: 120, ideal: 200)
		} rows: {
			ForEach(model.entries) { entry in
				TableRow(entry)
					.draggable(entry.id)
			}
			.dropDestination(for: String.self) { destination, identifiers in
				model.moveEntries(identifiedBy: identifiers, to: destination)
			}
		}
		.onDeleteCommand(perform: model.removeSelection)
		.contextMenu(forSelectionType: ServerEndpointDraft.ID.self) { selection in
			Button(.ServerProperties.moveUp) { move(selection, by: -1) }
				.disabled(selection.count != 1)
			Button(.ServerProperties.moveDown) { move(selection, by: 1) }
				.disabled(selection.count != 1)
			Divider()
			Button(.ServerProperties.removeServer, role: .destructive) {
				guard let id = selection.first else { return }
				model.selectedID = id
				model.removeSelection()
			}
			.disabled(selection.isEmpty)
		}
		.accessibilityLabel(.ServerProperties.serverList)
	}

	private func move(_ selection: Set<ServerEndpointDraft.ID>, by offset: Int) {
		guard let id = selection.first else { return }
		model.selectedID = id
		model.moveSelection(by: offset)
	}
}
