/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Observation
import SwiftUI

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

	@discardableResult
	func save(_ filter: ChatFilter, replacing identifier: ChatFilter.ID?) -> Bool {
		if let identifier {
			guard let index = filters.firstIndex(where: { $0.id == identifier }) else { return false }
			filters[index] = filter
		} else {
			filters.append(filter)
		}
		selection = filter.id
		didChange(filters)
		return true
	}

	func removeSelection() {
		guard let selectedIndex else { return }
		filters.remove(at: selectedIndex)
		selection = filters.indices.contains(selectedIndex)
			? filters[selectedIndex].id
			: filters.last?.id
		didChange(filters)
	}

	func move(from offsets: IndexSet, to destination: Int) {
		filters.move(fromOffsets: offsets, toOffset: destination)
		didChange(filters)
	}

	var selectedIndex: Int? {
		guard let selection else { return nil }
		return filters.firstIndex { $0.id == selection }
	}

	var selectedFilter: ChatFilter? {
		selectedIndex.map { filters[$0] }
	}
}
