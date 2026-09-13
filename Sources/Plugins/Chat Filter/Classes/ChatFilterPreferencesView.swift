/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import SwiftUI
import UniformTypeIdentifiers

private struct ChatFilterEditorPresentation: Identifiable {
	let id = UUID()
	let filter: ChatFilter
	let replacingIdentifier: ChatFilter.ID?
}

/** A filter command that stopped, with the sentence that says what to do next.

 One title per operation: an export that could not be written is not a file
 that could not be read, and saying so is the difference between a message
 someone can act on and one they cannot. */
private struct ChatFilterFailure: Identifiable {
	enum Operation {
		case importing
		case exporting
		case saving

		var title: LocalizedStringResource {
			switch self {
			case .importing: .ChatFilter.importFailedTitle
			case .exporting: .ChatFilter.exportFailedTitle
			case .saving: .ChatFilter.saveFailedTitle
			}
		}

		var recovery: LocalizedStringResource? {
			switch self {
			case .importing: .ChatFilter.importFailedRecovery
			case .exporting: .ChatFilter.exportFailedRecovery
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

struct ChatFilterPreferencesView: View {
	private static let listHeight = 240.0

	@Bindable var store: ChatFilterStore
	let clients: () -> [ChatFilterClientOption]

	@State private var editor: ChatFilterEditorPresentation?
	@State private var showsDeleteConfirmation = false
	@State private var showsImporter = false
	@State private var exportData: Data?
	@State private var showsExporter = false
	@State private var failure: ChatFilterFailure?

	var body: some View {
		Form {
			Section {
				List(selection: $store.selection) {
					ForEach(store.filters) { filter in
						Text(filter.description)
							.tag(filter.id)
							.contentShape(.rect)
							.onTapGesture(count: 2) {
								editor = ChatFilterEditorPresentation(
									filter: filter,
									replacingIdentifier: filter.id
								)
							}
					}
					.onMove(perform: store.move)
				}
				.frame(height: Self.listHeight)
				.overlay {
					if store.filters.isEmpty {
						ContentUnavailableView(
							String(localized: .ChatFilter.noFiltersTitle),
							systemImage: "line.3.horizontal.decrease.circle",
							description: Text(String(localized: .ChatFilter.noFiltersDescription))
						)
					}
				}

				commands
			}
		}
		.formStyle(.grouped)
		.sheet(item: $editor) { presentation in
			ChatFilterEditorView(filter: presentation.filter, clients: clients()) { filter in
				if store.save(filter, replacing: presentation.replacingIdentifier) == false {
					failure = ChatFilterFailure(
						operation: .saving,
						reason: String(localized: .ChatFilter.editedFilterRemoved)
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
			onCompletion: importFilter
		)
		.fileExporter(
			isPresented: $showsExporter,
			item: exportData,
			contentTypes: [.propertyList],
			defaultFilename: "filter.plist"
		) { result in
			if case let .failure(error) = result {
				failure = ChatFilterFailure(operation: .exporting, reason: error.localizedDescription)
			}
			exportData = nil
		}
		.alert(
			failure?.title ?? "",
			isPresented: failureIsPresented,
			presenting: failure
		) { _ in
			Button(String(localized: .ChatFilter.okButton)) {
				failure = nil
			}
		} message: { failure in
			Text(failure.message)
		}
		.alert(
			String(localized: .ChatFilter.deleteFilterTitle),
			isPresented: $showsDeleteConfirmation
		) {
			Button(String(localized: .ChatFilter.deleteFilterButton), role: .destructive) {
				store.removeSelection()
			}
			Button(String(localized: .ChatFilter.cancelButton), role: .cancel) {}
		} message: {
			Text(String(localized: .ChatFilter.deleteFilterMessage))
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
		HStack(spacing: 8) {
			Button {
				editor = ChatFilterEditorPresentation(filter: ChatFilter(), replacingIdentifier: nil)
			} label: {
				Label(String(localized: .ChatFilter.addFilterButton), systemImage: "plus")
			}

			Button {
				showsDeleteConfirmation = true
			} label: {
				Label(String(localized: .ChatFilter.deleteFilterButton), systemImage: "minus")
			}
			.disabled(store.selectedFilter == nil)

			Button {
				editSelection()
			} label: {
				Label(String(localized: .ChatFilter.editFilterButton), systemImage: "pencil")
			}
			.disabled(store.selectedFilter == nil)

			Spacer()

			Menu {
				Button(String(localized: .ChatFilter.duplicateFilterButton)) {
					duplicateSelection()
				}
				.disabled(store.selectedFilter == nil)

				Divider()

				Button(String(localized: .ChatFilter.importFilterButton)) {
					showsImporter = true
				}
				Button(String(localized: .ChatFilter.exportFilterButton)) {
					exportSelection()
				}
				.disabled(store.selectedFilter == nil)
			} label: {
				Label(String(localized: .ChatFilter.moreActionsButton), systemImage: "ellipsis.circle")
			}
			.menuStyle(.borderlessButton)
			.fixedSize()
		}
	}

	private func editSelection() {
		guard let filter = store.selectedFilter else { return }
		editor = ChatFilterEditorPresentation(filter: filter, replacingIdentifier: filter.id)
	}

	private func duplicateSelection() {
		guard var filter = store.selectedFilter else { return }
		filter.id = UUID().uuidString
		filter.title = String(localized: .ChatFilter.duplicateFilterTitle(filter.title))
		editor = ChatFilterEditorPresentation(filter: filter, replacingIdentifier: nil)
	}

	private func exportSelection() {
		guard let filter = store.selectedFilter else { return }
		do {
			exportData = try filter.propertyListData()
			showsExporter = true
		} catch {
			failure = ChatFilterFailure(operation: .exporting, reason: error.localizedDescription)
		}
	}

	private func importFilter(_ result: Result<[URL], any Error>) {
		do {
			guard let url = try result.get().first else { return }
			let canAccess = url.startAccessingSecurityScopedResource()
			defer {
				if canAccess {
					url.stopAccessingSecurityScopedResource()
				}
			}
			var filter = try ChatFilter(contentsOf: url)
			filter.id = UUID().uuidString
			editor = ChatFilterEditorPresentation(filter: filter, replacingIdentifier: nil)
		} catch {
			failure = ChatFilterFailure(operation: .importing, reason: error.localizedDescription)
		}
	}
}
