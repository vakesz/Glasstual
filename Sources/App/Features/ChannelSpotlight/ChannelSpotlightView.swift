/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import SwiftUI

/// What the spotlight panel is built from. The panel sizes itself to its
/// content, so the heights the rows are drawn at are also the heights the
/// window is asked for; naming them once is what keeps the two in step.
private enum ChannelSpotlightLayout {
	static let width: CGFloat = 600
	static let searchFieldHeight: CGFloat = 76
	static let rowHeight: CGFloat = 54
	static let emptyStateHeight: CGFloat = 72
	/// How many matches the panel grows to before it starts scrolling.
	static let maximumVisibleRows = 6
}

@MainActor
struct ChannelSpotlightView: View {
	@Bindable var model: ChannelSpotlightModel
	let select: (ChannelSpotlightSearchResult) -> Void
	let close: () -> Void

	@FocusState private var searchIsFocused: Bool
	/// Scrolling the result list under the keyboard is motion the system can be
	/// asked to stop making.
	@Environment(\.accessibilityReduceMotion) private var reduceMotion

	private var contentHeight: CGFloat {
		guard model.searchText.isEmpty == false else {
			return ChannelSpotlightLayout.searchFieldHeight
		}
		guard model.displayedResults.isEmpty == false else {
			return ChannelSpotlightLayout.searchFieldHeight + ChannelSpotlightLayout.emptyStateHeight
		}

		let visibleRows = min(model.displayedResults.count, ChannelSpotlightLayout.maximumVisibleRows)
		return ChannelSpotlightLayout.searchFieldHeight
			+ CGFloat(visibleRows) * ChannelSpotlightLayout.rowHeight
	}

	var body: some View {
		VStack(spacing: 0) {
			HStack(spacing: UISpacing.wide) {
				Image(systemName: "magnifyingglass")
					.imageScale(.small)
					.foregroundStyle(.secondary)
				TextField(
					ChannelSpotlightStrings.searchPlaceholder,
					text: $model.searchText
				)
				.textFieldStyle(.plain)
				.focused($searchIsFocused)
				.onSubmit {
					if let result = model.selectedResult {
						select(result)
					}
				}
			}
			.font(.largeTitle.weight(.light))
			.padding(.horizontal, UISpacing.loose)
			.frame(height: ChannelSpotlightLayout.searchFieldHeight)

			if model.searchText.isEmpty == false {
				Divider()
				if model.displayedResults.isEmpty {
					ContentUnavailableView(
						ChannelSpotlightStrings.noResults,
						systemImage: "magnifyingglass"
					)
					.frame(height: ChannelSpotlightLayout.emptyStateHeight)
				} else {
					resultList
				}
			}
		}
		.glassEffect(.regular, in: .rect(cornerRadius: 22))
		.frame(width: ChannelSpotlightLayout.width, height: contentHeight)
		.onAppear {
			searchIsFocused = true
		}
		.onKeyPress(.downArrow) {
			model.selectRelativeResult(offset: 1)
			return .handled
		}
		.onKeyPress(.upArrow) {
			model.selectRelativeResult(offset: -1)
			return .handled
		}
		.onKeyPress(.escape) {
			if model.searchText.isEmpty {
				close()
			} else {
				model.searchText = ""
			}
			return .handled
		}
		.onKeyPress(characters: .decimalDigits, phases: .down) { keyPress in
			guard keyPress.modifiers == .command,
			      let number = Int(keyPress.characters),
			      (0 ... 9).contains(number),
			      let result = model.result(at: number == 0 ? 9 : number - 1)
			else { return .ignored }
			select(result)
			return .handled
		}
	}

	/** The matches, as a list rather than a stack of tapped rectangles.

	 A list is what VoiceOver counts its rows out of, and what the pointer gets
	 the row-sized hit target from. Typing stays in the search field, so the
	 list never takes the keyboard: the arrow keys above move the selection and
	 a single click opens the match under the pointer, the way a search panel
	 answers rather than the way a table is edited. */
	private var resultList: some View {
		ScrollViewReader { proxy in
			List(model.displayedResults, selection: $model.selectedResultID) { result in
				ChannelSpotlightRow(
					result: result,
					shortcut: shortcut(for: result)
				)
				.listRowInsets(EdgeInsets())
				.listRowSeparator(.hidden)
				.contentShape(.rect)
				.onTapGesture { select(result) }
			}
			.listStyle(.plain)
			.scrollContentBackground(.hidden)
			.overlayScrollers()
			.onChange(of: model.selectedResultID) { _, identifier in
				guard let identifier else { return }
				guard reduceMotion == false else {
					proxy.scrollTo(identifier, anchor: .center)
					return
				}
				withAnimation { proxy.scrollTo(identifier, anchor: .center) }
			}
		}
		.accessibilityLabel(ChannelSpotlightStrings.resultsAccessibilityLabel)
	}

	/// The shortcut label for one row: ⌘1 … ⌘0 for the first ten matches, and
	/// the Return key for whichever one Return would open.
	private func shortcut(for result: ChannelSpotlightSearchResult) -> String {
		if model.selectedResultID == result.id {
			return "↩︎"
		}
		guard let index = model.displayedResults.firstIndex(of: result), index < 10 else { return "" }
		return "⌘\(index == 9 ? 0 : index + 1)"
	}
}

@MainActor
private struct ChannelSpotlightRow: View {
	let result: ChannelSpotlightSearchResult
	let shortcut: String

	/// `.increased` is what a list row's ground reports while it is selected,
	/// which is the only way a row knows to stop drawing its own emphasis.
	@Environment(\.backgroundProminence) private var backgroundProminence

	var body: some View {
		HStack(spacing: UISpacing.wide) {
			VStack(alignment: .leading, spacing: 2) {
				Text(verbatim: result.title)
					.font(.headline)
					.lineLimit(1)
				if let activity = result.activity {
					Text(verbatim: activity)
						.font(.caption)
						.foregroundStyle(backgroundProminence == .increased ? .primary : .secondary)
						.lineLimit(1)
				}
			}
			Spacer()
			Text(verbatim: shortcut)
				.font(.callout.monospacedDigit())
				.foregroundStyle(.secondary)
		}
		.padding(.horizontal, UISpacing.loose)
		.frame(height: ChannelSpotlightLayout.rowHeight)
	}
}
