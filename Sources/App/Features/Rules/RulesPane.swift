// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import SwiftUI
import UniformTypeIdentifiers

private struct RuleEditorPresentation: Identifiable {
	let id = UUID()
	let rule: MessageRule
	let replacingIdentifier: MessageRule.ID?
}

/** A rule command that stopped, with the sentence that says what to do next.

 One title per operation: an export that could not be written is not a file
 that could not be read, and saying so is the difference between a message
 someone can act on and one they cannot. */
private struct RuleEditorFailure: Identifiable {
	enum Operation {
		case importing
		case exporting
		case saving

		var title: LocalizedStringResource {
			switch self {
			case .importing: .Rules.importFailedTitle
			case .exporting: .Rules.exportFailedTitle
			case .saving: .Rules.saveFailedTitle
			}
		}

		var recovery: LocalizedStringResource? {
			switch self {
			case .importing: .Rules.importFailedRecovery
			case .exporting: .Rules.exportFailedRecovery
			case .saving: nil
			}
		}
	}

	let id = UUID()
	let operation: Operation
	let reason: String

	var title: String {
		String(localized: operation.title)
	}

	var message: String {
		guard let recovery = operation.recovery else { return reason }
		return "\(reason)\n\n\(String(localized: recovery))"
	}
}

/// The Rules row of the Settings window: the rule list and the commands that
/// edit it, as sections of the window's own form.
struct RulesPane: View {
	private static let listHeight = 240.0

	@Bindable private var controller = AppServices.messageRules

	@State private var editor: RuleEditorPresentation?
	@State private var showsDeleteConfirmation = false
	@State private var showsImporter = false
	@State private var exportData: Data?
	@State private var showsExporter = false
	@State private var failure: RuleEditorFailure?

	var body: some View {
		Section {
			List(selection: $controller.selection) {
				ForEach(controller.rules) { rule in
					Text(rule.description)
						.tag(rule.id)
						.contentShape(.rect)
						.onTapGesture(count: 2) {
							editor = RuleEditorPresentation(
								rule: rule,
								replacingIdentifier: rule.id
							)
						}
				}
				.onMove(perform: controller.move)
			}
			.frame(height: Self.listHeight)
			.overlay {
				if controller.rules.isEmpty {
					ContentUnavailableView(
						String(localized: .Rules.noFiltersTitle),
						systemImage: "line.3.horizontal.decrease.circle",
						description: Text(String(localized: .Rules.noFiltersDescription))
					)
				}
			}

			commands
		}
		.sheet(item: $editor) { presentation in
			RuleEditorView(rule: presentation.rule, sessions: MessageRuleSessionOption.current()) { rule in
				if controller.save(rule, replacing: presentation.replacingIdentifier) == false {
					failure = RuleEditorFailure(
						operation: .saving,
						reason: String(localized: .Rules.editedFilterRemoved)
					)
				}
				editor = nil
			} onCancel: {
				editor = nil
			}
		}
		.fileImporter(
			isPresented: $showsImporter,
			allowedContentTypes: [.propertyList],
			allowsMultipleSelection: false,
			onCompletion: importRule
		)
		.fileExporter(
			isPresented: $showsExporter,
			item: exportData,
			contentTypes: [.propertyList],
			defaultFilename: "filter.plist"
		) { result in
			if case let .failure(error) = result {
				failure = RuleEditorFailure(operation: .exporting, reason: error.localizedDescription)
			}
			exportData = nil
		}
		.alert(
			failure?.title ?? "",
			isPresented: failureIsPresented,
			presenting: failure
		) { _ in
			Button(String(localized: .Rules.okButton)) {
				failure = nil
			}
		} message: { failure in
			Text(failure.message)
		}
		.alert(
			String(localized: .Rules.deleteFilterTitle),
			isPresented: $showsDeleteConfirmation
		) {
			Button(String(localized: .Rules.deleteFilterButton), role: .destructive) {
				controller.removeSelection()
			}
			Button(String(localized: .Rules.cancelButton), role: .cancel) {}
		} message: {
			Text(String(localized: .Rules.deleteFilterMessage))
		}
	}

	private var failureIsPresented: Binding<Bool> {
		Binding(
			get: { failure != nil },
			set: {
				if $0 == false {
					failure = nil
				}
			}
		)
	}

	private var commands: some View {
		HStack(spacing: UISpacing.regular) {
			Button {
				editor = RuleEditorPresentation(rule: MessageRule(), replacingIdentifier: nil)
			} label: {
				Label(String(localized: .Rules.addFilterButton), systemImage: "plus")
			}

			Button {
				showsDeleteConfirmation = true
			} label: {
				Label(String(localized: .Rules.deleteFilterButton), systemImage: "minus")
			}
			.disabled(controller.selectedRule == nil)

			Button {
				editSelection()
			} label: {
				Label(String(localized: .Rules.editFilterButton), systemImage: "pencil")
			}
			.disabled(controller.selectedRule == nil)

			Spacer()

			Menu {
				Button(String(localized: .Rules.duplicateFilterButton)) {
					duplicateSelection()
				}
				.disabled(controller.selectedRule == nil)

				Divider()

				Button(String(localized: .Rules.importFilterButton)) {
					showsImporter = true
				}
				Button(String(localized: .Rules.exportFilterButton)) {
					exportSelection()
				}
				.disabled(controller.selectedRule == nil)
			} label: {
				Label(String(localized: .Rules.moreActionsButton), systemImage: "ellipsis.circle")
			}
			.menuStyle(.borderlessButton)
			.fixedSize()
		}
	}

	private func editSelection() {
		guard let rule = controller.selectedRule else { return }
		editor = RuleEditorPresentation(rule: rule, replacingIdentifier: rule.id)
	}

	private func duplicateSelection() {
		guard var rule = controller.selectedRule else { return }
		rule.id = UUID().uuidString
		rule.title = String(localized: .Rules.duplicateFilterTitle(rule.title))
		editor = RuleEditorPresentation(rule: rule, replacingIdentifier: nil)
	}

	private func exportSelection() {
		guard let rule = controller.selectedRule else { return }
		do {
			exportData = try rule.propertyListData()
			showsExporter = true
		} catch {
			failure = RuleEditorFailure(operation: .exporting, reason: error.localizedDescription)
		}
	}

	private func importRule(_ result: Result<[URL], any Error>) {
		do {
			guard let url = try result.get().first else { return }
			let canAccess = url.startAccessingSecurityScopedResource()
			defer {
				if canAccess {
					url.stopAccessingSecurityScopedResource()
				}
			}
			var rule = try MessageRule(contentsOf: url)
			rule.id = UUID().uuidString
			editor = RuleEditorPresentation(rule: rule, replacingIdentifier: nil)
		} catch {
			failure = RuleEditorFailure(operation: .importing, reason: error.localizedDescription)
		}
	}
}
