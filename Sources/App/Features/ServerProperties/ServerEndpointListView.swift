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
			}
			.frame(maxWidth: .infinity, alignment: .leading)
			.padding([.horizontal, .top], 20)
			.padding(.bottom, 12)

			columnHeader

			List(selection: $model.selectedID) {
				ForEach($model.entries) { $entry in
					ServerEndpointRow(
						entry: $entry,
						addressIsInvalid: model.invalidAddressIDs.contains(entry.id),
						portIsInvalid: model.invalidPortIDs.contains(entry.id),
						securedDidChange: { model.setSecured($0, for: entry.id) },
						addressDidChange: { model.addressDidChange(for: entry.id) },
						portDidChange: { model.portDidChange(for: entry.id) }
					)
					.tag(entry.id)
				}
				.onDelete(perform: model.removeEntries)
				.onMove(perform: model.moveEntries)
			}
			.accessibilityLabel(ServerEndpointStrings.serverList)

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
				Button(PromptStrings.Action.save, action: submit)
					.keyboardShortcut(.defaultAction)
			}
			.padding(12)
		}
		.onExitCommand(perform: cancel)
		.frame(
			minWidth: 560,
			idealWidth: 640,
			maxWidth: .infinity,
			minHeight: 360,
			idealHeight: 440,
			maxHeight: .infinity
		)
	}

	private var columnHeader: some View {
		HStack(spacing: 12) {
			Text(verbatim: ServerEndpointStrings.serverAddress)
				.frame(maxWidth: .infinity, alignment: .leading)
			Text(verbatim: ServerEndpointStrings.port)
				.frame(width: 80, alignment: .leading)
			Text(verbatim: ServerEndpointStrings.connectSecurely)
				.frame(width: 72, alignment: .center)
			Text(verbatim: ServerEndpointStrings.serverPassword)
				.frame(maxWidth: .infinity, alignment: .leading)
		}
		.font(.caption.weight(.semibold))
		.foregroundStyle(.secondary)
		.padding(.horizontal, 28)
		.padding(.vertical, 6)
	}
}

private struct ServerEndpointRow: View {
	@Binding var entry: ServerEndpointDraft
	let addressIsInvalid: Bool
	let portIsInvalid: Bool
	let securedDidChange: @MainActor @Sendable (Bool) -> Void
	let addressDidChange: () -> Void
	let portDidChange: () -> Void

	var body: some View {
		VStack(alignment: .leading, spacing: 4) {
			HStack(spacing: 12) {
				TextField(ServerEndpointStrings.serverAddress, text: $entry.address)
					.textFieldStyle(.roundedBorder)
					.onChange(of: entry.address) { addressDidChange() }

				TextField(ServerEndpointStrings.port, text: $entry.port)
					.textFieldStyle(.roundedBorder)
					.frame(width: 80)
					.onChange(of: entry.port) { portDidChange() }

				Toggle(
					ServerEndpointStrings.connectSecurely,
					isOn: Binding(
						get: { entry.prefersSecuredConnection },
						set: securedDidChange
					)
				)
				.labelsHidden()
				.frame(width: 72)

				SecureField(ServerEndpointStrings.serverPassword, text: $entry.password)
					.textFieldStyle(.roundedBorder)
					.help(ServerEndpointStrings.serverPasswordHelp)
			}

			if addressIsInvalid {
				Text(verbatim: ServerEndpointStrings.invalidAddressDescription)
					.foregroundStyle(.red)
					.font(.caption)
			} else if portIsInvalid {
				Text(verbatim: ServerEndpointStrings.invalidPortRecoverySuggestion)
					.foregroundStyle(.red)
					.font(.caption)
			}
		}
		.padding(.vertical, 3)
	}
}
