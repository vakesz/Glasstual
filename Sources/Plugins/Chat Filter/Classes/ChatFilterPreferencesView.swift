/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Observation
import SwiftUI
import UniformTypeIdentifiers

@Observable
final class ChatFilterStore {
	private(set) var filters: [ChatFilter] = []
	var selection: ChatFilter.ID?

	private let didChange: ([ChatFilter]) -> Void

	init(didChange: @escaping ([ChatFilter]) -> Void) {
		self.didChange = didChange
	}

	func replaceAll(with filters: [ChatFilter]) {
		self.filters = filters
		if selection.map({ selectedID in filters.contains { $0.id == selectedID } }) != true {
			selection = filters.first?.id
		}
	}

	func save(_ filter: ChatFilter, replacing index: Int?) {
		if let index, filters.indices.contains(index) {
			filters[index] = filter
		} else {
			filters.append(filter)
		}
		selection = filter.id
		persist()
	}

	func removeSelection() {
		guard let selectedIndex else { return }
		filters.remove(at: selectedIndex)
		selection = filters.indices.contains(selectedIndex)
			? filters[selectedIndex].id
			: filters.last?.id
		persist()
	}

	func move(from offsets: IndexSet, to destination: Int) {
		filters.move(fromOffsets: offsets, toOffset: destination)
		persist()
	}

	var selectedIndex: Int? {
		guard let selection else { return nil }
		return filters.firstIndex { $0.id == selection }
	}

	var selectedFilter: ChatFilter? {
		selectedIndex.map { filters[$0] }
	}

	private func persist() {
		didChange(filters)
	}
}

private struct ChatFilterEditorPresentation: Identifiable {
	let id = UUID()
	let filter: ChatFilter
	let index: Int?
}

struct ChatFilterPreferencesView: View {
	@Bindable var store: ChatFilterStore
	let clients: () -> [ChatFilterClientOption]

	@State private var editor: ChatFilterEditorPresentation?
	@State private var showsDeleteConfirmation = false
	@State private var showsImporter = false
	@State private var exportData: Data?
	@State private var showsExporter = false
	@State private var importError: String?
	@State private var exportError: String?

	var body: some View {
		VStack(spacing: 0) {
			List(selection: $store.selection) {
				ForEach(Array(store.filters.enumerated()), id: \.element.id) { index, filter in
					Text(filter.description)
						.tag(filter.id)
						.contentShape(.rect)
						.onTapGesture(count: 2) {
							editor = ChatFilterEditorPresentation(filter: filter, index: index)
						}
				}
				.onMove(perform: store.move)
			}
			.listStyle(.inset(alternatesRowBackgrounds: true))
			.overlay {
				if store.filters.isEmpty {
					ContentUnavailableView(
						String(localized: .TPIChatFilterExtension.noFiltersTitle),
						systemImage: "line.3.horizontal.decrease.circle",
						description: Text(String(localized: .TPIChatFilterExtension.noFiltersDescription))
					)
				}
			}

			Divider()

			HStack(spacing: 8) {
				Button {
					editor = ChatFilterEditorPresentation(filter: ChatFilter(), index: nil)
				} label: {
					Label(String(localized: .TPIChatFilterExtension.addFilterButton), systemImage: "plus")
				}

				Button {
					showsDeleteConfirmation = true
				} label: {
					Label(String(localized: .TPIChatFilterExtension.removeFilterButton), systemImage: "minus")
				}
				.disabled(store.selectedFilter == nil)

				Button {
					editSelection()
				} label: {
					Label(String(localized: .TPIChatFilterExtension.editFilterButton), systemImage: "pencil")
				}
				.disabled(store.selectedFilter == nil)

				Spacer()

				Menu {
					Button(String(localized: .TPIChatFilterExtension.duplicateFilterButton)) {
						duplicateSelection()
					}
					.disabled(store.selectedFilter == nil)

					Divider()

					Button(String(localized: .TPIChatFilterExtension.importFilterButton)) {
						showsImporter = true
					}
					Button(String(localized: .TPIChatFilterExtension.exportFilterButton)) {
						if let filter = store.selectedFilter {
							do {
								exportData = try filter.propertyListData()
								showsExporter = true
							} catch {
								exportError = error.localizedDescription
							}
						}
					}
					.disabled(store.selectedFilter == nil)
				} label: {
					Label(String(localized: .TPIChatFilterExtension.moreActionsButton), systemImage: "ellipsis.circle")
				}
				.menuStyle(.borderlessButton)
			}
			.padding(12)
		}
		.frame(minWidth: 520, minHeight: 300)
		.sheet(item: $editor) { presentation in
			ChatFilterEditorView(filter: presentation.filter, clients: clients()) { filter in
				store.save(filter, replacing: presentation.index)
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
				exportError = error.localizedDescription
			}
			exportData = nil
		}
		.alert(
			String(localized: .TPIChatFilterExtension.unreadableConfigurationTitle),
			isPresented: Binding(
				get: { importError != nil },
				set: {
					if !$0 {
						importError = nil
					}
				}
			)
		) {
			Button(String(localized: .TPIChatFilterExtension.okButton)) {
				importError = nil
			}
		} message: {
			Text(importError ?? "")
		}
		.alert(
			String(localized: .TPIChatFilterExtension.unreadableConfigurationTitle),
			isPresented: Binding(
				get: { exportError != nil },
				set: {
					if !$0 {
						exportError = nil
					}
				}
			)
		) {
			Button(String(localized: .TPIChatFilterExtension.okButton)) {
				exportError = nil
			}
		} message: {
			Text(exportError ?? "")
		}
		.alert(
			String(localized: .TPIChatFilterExtension.deleteFilterTitle),
			isPresented: $showsDeleteConfirmation
		) {
			Button(String(localized: .TPIChatFilterExtension.deleteFilterButton), role: .destructive) {
				store.removeSelection()
			}
			Button(String(localized: .TPIChatFilterExtension.cancelButton), role: .cancel) {}
		} message: {
			Text(String(localized: .TPIChatFilterExtension.deleteFilterMessage))
		}
	}

	private func editSelection() {
		guard let index = store.selectedIndex else { return }
		editor = ChatFilterEditorPresentation(filter: store.filters[index], index: index)
	}

	private func duplicateSelection() {
		guard var filter = store.selectedFilter else { return }
		filter.id = UUID().uuidString
		filter.title = String(localized: .TPIChatFilterExtension.duplicateFilterTitle(filter.title))
		editor = ChatFilterEditorPresentation(filter: filter, index: nil)
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
			editor = ChatFilterEditorPresentation(filter: filter, index: nil)
		} catch {
			importError = error.localizedDescription
		}
	}
}
