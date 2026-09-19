// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import SwiftUI

@MainActor
final class AddressBookEntrySheet: SheetSession {
	let model: AddressBookEntryModel

	private let onSave: (AddressBookEntry) -> Void

	convenience init(entryType: AddressBookEntryKind, onSave: @escaping (AddressBookEntry) -> Void) {
		self.init(model: AddressBookEntryModel(entryType: entryType), onSave: onSave)
	}

	convenience init(entry: AddressBookEntry, onSave: @escaping (AddressBookEntry) -> Void) {
		self.init(model: AddressBookEntryModel(entry: entry), onSave: onSave)
	}

	private init(model: AddressBookEntryModel, onSave: @escaping (AddressBookEntry) -> Void) {
		self.model = model
		self.onSave = onSave
		super.init(window: nil)
		setContent(AddressBookEntryView(
			model: model,
			submit: { [weak self] in self?.submit() },
			cancel: { [weak self] in self?.cancel() }
		))
	}

	override func submit() {
		guard let entry = model.validatedEntry() else { return }

		onSave(entry)
		super.submit()
	}
}

struct AddressBookEntryView: View {
	@Bindable var model: AddressBookEntryModel
	let submit: () -> Void
	let cancel: () -> Void

	@FocusState private var hostmaskFieldIsFocused: Bool

	var body: some View {
		VStack(spacing: 0) {
			SheetHeading(
				model.entryType.sheetTitle,
				subtitle: Text(model.entryType.sheetDescription)
			)

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

			/* The entry is only written back into the connection the sheet
			 belongs to, which is what saves it; the confirmation says the
			 editor is done with it. */
			SheetActions(
				confirmTitle: .sheetConfirmation,
				confirmIsDisabled: model.validationMessage != nil,
				confirm: submit,
				cancel: cancel
			)
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

	private var identitySection: some View {
		Section {
			LabeledContent(model.entryType.identityLabel) {
				TextField(model.entryType.identityPlaceholder, text: $model.entry.hostmask)
					.labelsHidden()
					.textFieldStyle(.roundedBorder)
					.focused($hostmaskFieldIsFocused)
					.accessibilityLabel(model.entryType.identityLabel)
			}

			if let validationMessage = model.validationMessage {
				ValidationMessageLabel(validationMessage)
			}
		}
	}

	private var trackingSection: some View {
		Section {
			Toggle(.AddressBook.displayMessageWhenUserBecomesAvailable, isOn: $model.entry.trackUserActivity)
		} footer: {
			Text(.AddressBook.trackingMethodDescription)
		}
	}

	private var ignoreSection: some View {
		Section(.AddressBook.ignoredMessages) {
			Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 10) {
				GridRow {
					Toggle(.AddressBook.publicMessages, isOn: $model.entry.ignorePublicMessages)
					Toggle(.AddressBook.privateMessages, isOn: $model.entry.ignorePrivateMessages)
				}
				GridRow {
					Toggle(.AddressBook.noticeMessages, isOn: $model.entry.ignoreNoticeMessages)
					Toggle(.AddressBook.clientToClientCtcp, isOn: $model.entry.ignoreClientToClientProtocol)
				}
				GridRow {
					Toggle(.AddressBook.publicHighlights, isOn: $model.entry.ignorePublicMessageHighlights)
					Toggle(.AddressBook.privateHighlights, isOn: $model.entry.ignorePrivateMessageHighlights)
				}
				GridRow {
					Toggle(.AddressBook.generalEventMessages, isOn: $model.entry.ignoreGeneralEventMessages)
					Toggle(.AddressBook.fileTransferRequests, isOn: $model.entry.ignoreFileTransferRequests)
				}
				GridRow {
					Toggle(.AddressBook.inlineMedia, isOn: $model.entry.ignoreInlineMedia)
				}
			}
			.toggleStyle(.checkbox)
		}
	}

	private var hostmaskHelp: some View {
		Section {
			DisclosureGroup(.AddressBook.hostmaskFormatAndExamples) {
				Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 5) {
					GridRow {
						Text(.AddressBook.format)
							.fontWeight(.semibold)
						Text(.AddressBook.nicknameUsernameAddress)
							.textSelection(.enabled)
					}
					GridRow {
						Text(.AddressBook.examples)
							.fontWeight(.semibold)
						VStack(alignment: .leading, spacing: 3) {
							ForEach(Self.hostmaskExamples, id: \.key) { example in
								Text(example).textSelection(.enabled)
							}
						}
					}
				}
				.font(.caption)
				.foregroundStyle(.secondary)
				.padding(.top, UISpacing.tight)
			}
		}
	}

	private static let hostmaskExamples: [LocalizedStringResource] = [
		.AddressBook.matchesEveryPossibleUser,
		.AddressBook.matchesNicknamesStartingWithFrank,
		.AddressBook.matchesUsernameMatt,
		.AddressBook.matchesAddressesEndingInInfo,
	]
}
