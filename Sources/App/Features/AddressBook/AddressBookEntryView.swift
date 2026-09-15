/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import SwiftUI

struct AddressBookEntryView: View {
	@Bindable var model: AddressBookEntryModel
	let submit: () -> Void
	let cancel: () -> Void

	@FocusState private var hostmaskFieldIsFocused: Bool

	var body: some View {
		VStack(spacing: 0) {
			VStack(alignment: .leading, spacing: 6) {
				Text(verbatim: model.title)
					.font(.title2.weight(.semibold))
				Text(verbatim: description)
					.foregroundStyle(.secondary)
					.fixedSize(horizontal: false, vertical: true)
			}
			.frame(maxWidth: .infinity, alignment: .leading)
			.padding([.horizontal, .top], 20)
			.padding(.bottom, 12)

			Form {
				identitySection

				if model.editsIgnoreSettings {
					ignoreSection
				}
				if model.editsTracking {
					trackingSection
				}
				if model.editsIgnoreSettings {
					hostmaskHelp
				}
			}
			.formStyle(.grouped)

			Divider()
			HStack {
				Spacer()
				Button(PromptStrings.Action.cancel, action: cancel)
					.keyboardShortcut(.cancelAction)
				/* The entry is only written back into the connection the sheet
				 belongs to, which is what saves it; this one says the editor is
				 done with it. */
				Button(PromptStrings.Action.confirmation, action: submit)
					.keyboardShortcut(.defaultAction)
					.disabled(model.validationMessage != nil)
			}
			.padding(12)
		}
		.frame(
			minWidth: 480,
			idealWidth: 540,
			maxWidth: .infinity,
			minHeight: 360,
			idealHeight: 440,
			maxHeight: .infinity
		)
		.onAppear { hostmaskFieldIsFocused = true }
	}

	private var description: String {
		model.entryType == .userTracking
			? AddressBookStrings.trackingDescription
			: AddressBookStrings.ignoreDescription
	}

	private var identitySection: some View {
		Section {
			LabeledContent(model.entryType == .userTracking
				? AddressBookStrings.nickname
				: AddressBookStrings.hostmask)
			{
				TextField(placeholder, text: $model.hostmask)
					.textFieldStyle(.roundedBorder)
					.focused($hostmaskFieldIsFocused)
					.accessibilityLabel(model.entryType == .userTracking
						? AddressBookStrings.nickname
						: AddressBookStrings.hostmask)
			}

			if let validationMessage = model.validationMessage {
				ValidationMessageLabel(validationMessage)
			}
		}
	}

	private var placeholder: String {
		model.entryType == .userTracking
			? AddressBookStrings.nicknamePlaceholder
			: AddressBookStrings.hostmaskPlaceholder
	}

	private var trackingSection: some View {
		Section {
			Toggle(AddressBookStrings.displayAvailabilityMessage, isOn: $model.trackUserActivity)
		} footer: {
			Text(verbatim: AddressBookStrings.trackingMethodDescription)
		}
	}

	private var ignoreSection: some View {
		Section(AddressBookStrings.ignoredMessages) {
			Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 10) {
				GridRow {
					Toggle(AddressBookStrings.publicMessages, isOn: $model.ignorePublicMessages)
					Toggle(AddressBookStrings.privateMessages, isOn: $model.ignorePrivateMessages)
				}
				GridRow {
					Toggle(AddressBookStrings.noticeMessages, isOn: $model.ignoreNoticeMessages)
					Toggle(
						AddressBookStrings.clientToClientProtocol,
						isOn: $model.ignoreClientToClientProtocol
					)
				}
				GridRow {
					Toggle(AddressBookStrings.publicHighlights, isOn: $model.ignorePublicMessageHighlights)
					Toggle(AddressBookStrings.privateHighlights, isOn: $model.ignorePrivateMessageHighlights)
				}
				GridRow {
					Toggle(AddressBookStrings.generalEventMessages, isOn: $model.ignoreGeneralEventMessages)
					Toggle(AddressBookStrings.fileTransferRequests, isOn: $model.ignoreFileTransferRequests)
				}
				GridRow {
					Toggle(AddressBookStrings.inlineMedia, isOn: $model.ignoreInlineMedia)
				}
			}
			.toggleStyle(.checkbox)
		}
	}

	private var hostmaskHelp: some View {
		Section {
			DisclosureGroup(AddressBookStrings.hostmaskHelp) {
				Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 5) {
					GridRow {
						Text(verbatim: AddressBookStrings.format)
							.fontWeight(.semibold)
						Text(verbatim: AddressBookStrings.hostmaskFormat)
							.textSelection(.enabled)
					}
					GridRow {
						Text(verbatim: AddressBookStrings.examples)
							.fontWeight(.semibold)
						VStack(alignment: .leading, spacing: 3) {
							ForEach(AddressBookStrings.hostmaskExamples, id: \.self) { example in
								Text(verbatim: example).textSelection(.enabled)
							}
						}
					}
				}
				.font(.caption)
				.foregroundStyle(.secondary)
				.padding(.top, 4)
			}
		}
	}
}
