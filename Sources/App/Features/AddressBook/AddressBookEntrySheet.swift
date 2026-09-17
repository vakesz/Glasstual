// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import SwiftUI

@MainActor
final class AddressBookEntrySheet: SheetSession {
	let model: AddressBookEntryModel

	private let onSave: (AddressBookEntry) -> Void

	convenience init(entryType: AddressBookEntryType, onSave: @escaping (AddressBookEntry) -> Void) {
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

	func start() {
		startSheet()
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
			VStack(alignment: .leading, spacing: 6) {
				Text(model.entryType.sheetTitle)
					.font(.title2.weight(.semibold))
				Text(model.entryType.sheetDescription)
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

	private var identitySection: some View {
		Section {
			LabeledContent(model.entryType.identityLabel) {
				TextField(model.entryType.identityPlaceholder, text: $model.hostmask)
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
			Toggle(.AddressBook.displayMessageWhenUserBecomesAvailable, isOn: $model.trackUserActivity)
		} footer: {
			Text(.AddressBook.trackingMethodDescription)
		}
	}

	private var ignoreSection: some View {
		Section(.AddressBook.ignoredMessages) {
			Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 10) {
				GridRow {
					Toggle(.AddressBook.publicMessages, isOn: $model.ignorePublicMessages)
					Toggle(.AddressBook.privateMessages, isOn: $model.ignorePrivateMessages)
				}
				GridRow {
					Toggle(.AddressBook.noticeMessages, isOn: $model.ignoreNoticeMessages)
					Toggle(.AddressBook.clientToClientCtcp, isOn: $model.ignoreClientToClientProtocol)
				}
				GridRow {
					Toggle(.AddressBook.publicHighlights, isOn: $model.ignorePublicMessageHighlights)
					Toggle(.AddressBook.privateHighlights, isOn: $model.ignorePrivateMessageHighlights)
				}
				GridRow {
					Toggle(.AddressBook.generalEventMessages, isOn: $model.ignoreGeneralEventMessages)
					Toggle(.AddressBook.fileTransferRequests, isOn: $model.ignoreFileTransferRequests)
				}
				GridRow {
					Toggle(.AddressBook.inlineMedia, isOn: $model.ignoreInlineMedia)
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
				.padding(.top, 4)
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
