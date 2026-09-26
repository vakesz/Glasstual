// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import SwiftUI

struct SettingsTransferPresentation: ViewModifier {
	@Bindable var session: SettingsTransferSession
	let host: SettingsTransferHost
	/// The sheet outlives `session.preview` by one dismissal animation, and an
	/// alert raised in that window would land behind it.
	@State private var previewIsPresented = false

	/// Whether this host is the one that should be answering for the workflow.
	private var ownsPresentation: Bool {
		session.host == host && session.preview == nil && previewIsPresented == false
	}

	func body(content: Content) -> some View {
		content
			.sheet(item: Binding(
				get: { session.host == host ? session.preview : nil },
				set: { preview in
					if preview == nil, session.host == host {
						session.cancelPreview()
					}
				}
			), onDismiss: { previewIsPresented = false }, content: { preview in
				SettingsTransferPreviewView(session: session, presented: preview)
					.onAppear { previewIsPresented = true }
			})
			.modifier(SettingsTransferAlert(
				message: ownsPresentation ? session.pendingMessage : nil,
				acknowledge: session.acknowledge
			))
	}
}

// MARK: - Export options

/** The export options sheet, and the choice it hands back.

 The choice is applied on dismissal because the save panel that follows is a
 sheet of its own, and the two cannot be on screen at once. */
struct SettingsExportOptionsPresentation: ViewModifier {
	@Binding var isPresented: Bool
	let export: (Bool) -> Void
	@State private var confirmedChoice: Bool?

	func body(content: Content) -> some View {
		content.sheet(isPresented: $isPresented, onDismiss: {
			if let choice = confirmedChoice {
				confirmedChoice = nil
				export(choice)
			}
		}, content: {
			SettingsExportOptionsView { includeCommands in
				confirmedChoice = includeCommands
				isPresented = false
			}
		})
	}
}

/// Both export entry points require an explicit selection, reset to OFF for each export.
private struct SettingsExportOptionsView: View {
	let confirm: (Bool) -> Void
	@Environment(\.dismiss) private var dismiss
	@State private var includeConnectCommands = false

	var body: some View {
		VStack(alignment: .leading, spacing: UISpacing.loose) {
			Text(.SettingsTransfer.exportOptions).font(.title2)
			Toggle(.SettingsTransfer.includeConnectCommands, isOn: $includeConnectCommands)
			Text(.SettingsTransfer.connectCommandsWarning).font(.callout).foregroundStyle(.secondary)
			HStack {
				Spacer()
				Button(PromptStrings.Action.cancel) { dismiss() }.keyboardShortcut(.cancelAction)
				Button(PromptStrings.Action.saveFile) { confirm(includeConnectCommands) }
					.keyboardShortcut(.defaultAction)
			}
		}
		.padding(SettingsWindowMetrics.sheetInset)
		.frame(width: 460)
		.onAppear { includeConnectCommands = false }
	}
}
