/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import SwiftUI

struct ServerEndpointListView: View {
	@Bindable var model: ServerEndpointListModel
	let submit: () -> Void
	let cancel: () -> Void

	var body: some View {
		VStack(spacing: 0) {
			VStack(alignment: .leading, spacing: 6) {
				Text(verbatim: ServerEndpointStrings.windowTitle)
					.font(.title2.weight(.semibold))
				Text(verbatim: ServerEndpointStrings.explanation)
					.foregroundStyle(.secondary)
					.fixedSize(horizontal: false, vertical: true)
			}
			.frame(maxWidth: .infinity, alignment: .leading)
			.padding([.horizontal, .top], 20)
			.padding(.bottom, 12)

			endpointTable

			VStack(alignment: .leading, spacing: 4) {
				ForEach(model.faults, id: \.self) { fault in
					ValidationMessageLabel(fault.message)
				}
				Text(verbatim: ServerEndpointStrings.serverPasswordHelp)
					.font(.caption)
					.foregroundStyle(.secondary)
			}
			.frame(maxWidth: .infinity, alignment: .leading)
			.padding(.horizontal, 20)
			.padding(.vertical, 8)

			Divider()
			HStack(spacing: 8) {
				Button(action: model.addEntry) {
					Image(systemName: "plus")
				}
				.help(ServerEndpointStrings.addServer)
				.accessibilityLabel(ServerEndpointStrings.addServer)

				Button(role: .destructive, action: model.removeSelection) {
					Image(systemName: "minus")
				}
				.disabled(model.selectedID == nil)
				.help(ServerEndpointStrings.removeServer)
				.accessibilityLabel(ServerEndpointStrings.removeServer)

				Divider().frame(height: 18)

				Button { model.moveSelection(by: -1) } label: {
					Image(systemName: "arrow.up")
				}
				.disabled(model.canMoveSelectionUp == false)
				.help(ServerEndpointStrings.moveUp)
				.accessibilityLabel(ServerEndpointStrings.moveUp)

				Button { model.moveSelection(by: 1) } label: {
					Image(systemName: "arrow.down")
				}
				.disabled(model.canMoveSelectionDown == false)
				.help(ServerEndpointStrings.moveDown)
				.accessibilityLabel(ServerEndpointStrings.moveDown)

				Spacer()
				Button(PromptStrings.Action.cancel, action: cancel)
					.keyboardShortcut(.cancelAction)
				/* The list is handed back to the connection sheet, which is
				 what saves it. */
				Button(PromptStrings.Action.confirmation, action: submit)
					.keyboardShortcut(.defaultAction)
					.disabled(model.faults.isEmpty == false)
			}
			.padding(12)
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
		Table(model.entries, selection: $model.selectedID) {
			TableColumn(ServerEndpointStrings.serverAddress) { entry in
				TextField(
					ServerEndpointStrings.serverAddress,
					text: model.address(for: entry.id)
				)
				.labelsHidden()
				.accessibilityLabel(ServerEndpointStrings.serverAddress)
			}
			.width(min: 160, ideal: 240)

			TableColumn(ServerEndpointStrings.port) { entry in
				TextField(ServerEndpointStrings.port, text: model.port(for: entry.id))
					.labelsHidden()
					.accessibilityLabel(ServerEndpointStrings.port)
			}
			.width(min: 60, ideal: 80)

			TableColumn(ServerEndpointStrings.connectSecurely) { entry in
				Toggle(ServerEndpointStrings.connectSecurely, isOn: model.isSecured(for: entry.id))
					.labelsHidden()
					.accessibilityLabel(ServerEndpointStrings.connectSecurely)
			}
			.width(min: 52, ideal: 64)

			TableColumn(ServerEndpointStrings.serverPassword) { entry in
				SecureField(
					ServerEndpointStrings.serverPassword,
					text: model.password(for: entry.id)
				)
				.labelsHidden()
				.accessibilityLabel(ServerEndpointStrings.serverPassword)
			}
			.width(min: 120, ideal: 200)
		}
		.onDeleteCommand(perform: model.removeSelection)
		.contextMenu(forSelectionType: ServerEndpointDraft.ID.self) { selection in
			Button(ServerEndpointStrings.moveUp) { move(selection, by: -1) }
				.disabled(selection.count != 1)
			Button(ServerEndpointStrings.moveDown) { move(selection, by: 1) }
				.disabled(selection.count != 1)
			Divider()
			Button(ServerEndpointStrings.removeServer, role: .destructive) {
				guard let id = selection.first else { return }
				model.selectedID = id
				model.removeSelection()
			}
			.disabled(selection.isEmpty)
		}
		.accessibilityLabel(ServerEndpointStrings.serverList)
	}

	private func move(_ selection: Set<ServerEndpointDraft.ID>, by offset: Int) {
		guard let id = selection.first else { return }
		model.selectedID = id
		model.moveSelection(by: offset)
	}
}
