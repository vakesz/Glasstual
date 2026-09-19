// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import SwiftUI

struct ChannelSpotlightScene: Scene {
	let window: ChannelSpotlightWindow

	var body: some Scene {
		WindowGroup(
			String(localized: .ChannelSpotlight.windowTitle),
			id: ApplicationSceneID.channelSpotlight,
			for: SingletonSceneValue.self
		) { _ in
			ChannelSpotlightSceneRoot(window: window)
				.containerBackground(.clear, for: .window)
				.toolbarVisibility(.hidden, for: .windowToolbar)
				.windowMinimizeBehavior(.disabled)
		} defaultValue: { .instance }
			.windowResizability(.contentSize)
			// A plain borderless window cannot become key, leaving search typing
			// in the chat composer. Keep a titled window's keyboard behavior while
			// hiding its title and letting the search content draw the background.
			.windowStyle(.hiddenTitleBar)
			.windowLevel(.floating)
			.windowBackgroundDragBehavior(.disabled)
			.defaultPosition(.center)
			.restorationBehavior(.disabled)
	}
}

private struct ChannelSpotlightSceneRoot: View {
	@Environment(\.dismissWindow) private var dismissWindow
	@Environment(\.controlActiveState) private var controlActiveState
	@State private var activation = ChannelSpotlightActivation()
	@State private var topInset: CGFloat = 0
	let window: ChannelSpotlightWindow

	var body: some View {
		if let model = window.current {
			ChannelSpotlightView(
				model: model,
				select: { result in
					model.select(result)
					dismiss()
				},
				close: dismiss
			)
			.background(ChannelSpotlightWindowGeometry(topInset: $topInset))
			.padding(.top, -topInset)
			.onDisappear {
				activation = ChannelSpotlightActivation()
				window.didClose()
			}
			.onChange(of: controlActiveState, initial: true) { _, state in
				guard activation.shouldDismiss(after: state) else { return }
				dismiss()
			}
		}
	}

	private func dismiss() {
		dismissWindow(id: ApplicationSceneID.channelSpotlight)
	}
}

/// Opening a scene can report inactive states before its window becomes key.
/// Only losing acquired keyboard focus dismisses the search.
struct ChannelSpotlightActivation {
	private var hasBecomeKey = false

	mutating func shouldDismiss(after state: ControlActiveState) -> Bool {
		if state == .key {
			hasBecomeKey = true
			return false
		}
		guard hasBecomeKey else { return false }
		hasBecomeKey = false
		return true
	}
}

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
	@Environment(\.controlActiveState) private var controlActiveState
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
				TextField(.ChannelSpotlight.searchPlaceholder, text: $model.searchText)
					.textFieldStyle(.plain)
					.accessibilityIdentifier("channel-search-field")
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
						String(localized: .ChannelSpotlight.noResults),
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
		.defaultFocus($searchIsFocused, true)
		.onChange(of: controlActiveState, initial: true) { _, state in
			if state == .key {
				searchIsFocused = true
			}
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
				Button {
					select(result)
				} label: {
					ChannelSpotlightRow(
						result: result,
						shortcut: shortcut(for: result)
					)
					.contentShape(.rect)
				}
				.buttonStyle(.plain)
				.listRowInsets(EdgeInsets())
				.listRowSeparator(.hidden)
			}
			.listStyle(.plain)
			.scrollContentBackground(.hidden)
			.onChange(of: model.selectedResultID) { _, identifier in
				guard let identifier else { return }
				guard reduceMotion == false else {
					proxy.scrollTo(identifier, anchor: .center)
					return
				}
				withAnimation { proxy.scrollTo(identifier, anchor: .center) }
			}
		}
		.accessibilityLabel(.ChannelSpotlight.resultsAccessibilityLabel)
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
				.accessibilityHidden(true)
		}
		.padding(.horizontal, UISpacing.loose)
		.frame(height: ChannelSpotlightLayout.rowHeight)
	}
}
