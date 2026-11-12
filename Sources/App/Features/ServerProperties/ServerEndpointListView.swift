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
				.padding(.horizontal, SheetMetrics.margin)

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

			/* The list is handed back to the Server Properties window, which is
			 what saves it. */
			SheetActions(
				confirmTitle: .sheetConfirmation,
				confirmIsDisabled: model.faults.isEmpty == false,
				confirm: submit,
				cancel: cancel
			) {
				ListEditingControls(
					addLabel: Text(.ServerProperties.addServer),
					removeLabel: Text(.ServerProperties.removeServer),
					canRemove: model.selectedID != nil,
					add: model.addEntry,
					remove: model.removeSelection
				) {
					Button(.ServerProperties.moveUp) { model.moveSelection(by: -1) }
						.disabled(model.canMoveSelectionUp == false)
					Button(.ServerProperties.moveDown) { model.moveSelection(by: 1) }
						.disabled(model.canMoveSelectionDown == false)
				}
				.fixedSize()
			}
		}
		.sheetFrame(.wide, minHeight: 360, idealHeight: 440)
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
			.width(min: 160, ideal: 220)

			TableColumn(String(localized: .ServerProperties.endpointListTransportColumn)) { entry in
				Picker(.ServerProperties.endpointListTransportColumn, selection: model.transport(for: entry.id)) {
					Text(.ServerProperties.transportIrc).tag(ServerTransport.irc)
					Text(.ServerProperties.transportWebSocket).tag(ServerTransport.webSocket)
				}
				.labelsHidden()
				.pickerStyle(.menu)
				.buttonStyle(.borderless)
				.accessibilityLabel(.ServerProperties.endpointListTransportColumn)
				.accessibilityIdentifier("server-endpoint-transport")
			}
			.width(min: 90, ideal: 110)

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

			TableColumn(String(localized: .ServerProperties.endpointListPathColumn)) { entry in
				TextField(.ServerProperties.endpointListPathColumn, text: model.webSocketPath(for: entry.id), prompt: Text(verbatim: "/"))
					.labelsHidden()
					.disabled(entry.transport == .irc)
					.accessibilityLabel(.ServerProperties.endpointListPathColumn)
					.accessibilityIdentifier("server-endpoint-path")
			}
			.width(min: 70, ideal: 100)

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
			if selection.count == 1 {
				Button(.ServerProperties.moveUp) { move(selection, by: -1) }
				Button(.ServerProperties.moveDown) { move(selection, by: 1) }
				Divider()
			}
			if selection.isEmpty == false {
				Button(.ServerProperties.removeServer, role: .destructive) {
					guard let id = selection.first else { return }
					model.selectedID = id
					model.removeSelection()
				}
			}
		}
		.accessibilityLabel(.ServerProperties.serverList)
	}

	private func move(_ selection: Set<ServerEndpointDraft.ID>, by offset: Int) {
		guard let id = selection.first else { return }
		model.selectedID = id
		model.moveSelection(by: offset)
	}
}
