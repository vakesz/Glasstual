/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Combine
import SwiftUI

@MainActor
struct ChannelSpotlightView: View {
	@Bindable var model: ChannelSpotlightModel
	let select: (ChannelSpotlightSearchResult) -> Void
	let close: () -> Void

	@FocusState private var searchIsFocused: Bool

	private var contentHeight: CGFloat {
		if model.searchText.isEmpty {
			return 76
		}
		if model.displayedResults.isEmpty {
			return 148
		}
		return 76 + CGFloat(min(model.displayedResults.count, 6)) * 54
	}

	var body: some View {
		VStack(spacing: 0) {
			HStack(spacing: 12) {
				Image(systemName: "magnifyingglass")
					.font(.system(size: 20, weight: .medium))
					.foregroundStyle(.secondary)
				TextField(
					ChannelSpotlightStrings.searchPlaceholder,
					text: $model.searchText
				)
				.textFieldStyle(.plain)
				.font(.system(size: 25, weight: .light))
				.focused($searchIsFocused)
				.onSubmit {
					if let result = model.selectedResult {
						select(result)
					}
				}
			}
			.padding(.horizontal, 16)
			.frame(height: 76)

			if model.searchText.isEmpty == false {
				Divider()
				if model.displayedResults.isEmpty {
					ContentUnavailableView(
						ChannelSpotlightStrings.noResults,
						systemImage: "magnifyingglass"
					)
					.frame(height: 72)
				} else {
					ScrollViewReader { proxy in
						ScrollView {
							LazyVStack(spacing: 0) {
								ForEach(Array(model.displayedResults.enumerated()), id: \.element.id) { index, result in
									ChannelSpotlightRow(
										result: result,
										shortcut: shortcut(for: index),
										isSelected: model.selectedResultID == result.id
									)
									.contentShape(.rect)
									.onTapGesture(count: 2) { select(result) }
									.onTapGesture { model.selectedResultID = result.id }
									.id(result.id)
								}
							}
						}
						.onChange(of: model.selectedResultID) { _, identifier in
							guard let identifier else { return }
							withAnimation { proxy.scrollTo(identifier, anchor: .center) }
						}
					}
					.accessibilityLabel(ChannelSpotlightStrings.resultsAccessibilityLabel)
				}
			}
		}
		.glassEffect(.regular, in: .rect(cornerRadius: 22))
		.frame(width: 600, height: contentHeight)
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

	private func shortcut(for index: Int) -> String {
		guard index < 10 else { return "" }
		if model.displayedResults[index].id == model.selectedResultID {
			return "↩︎"
		}
		return "⌘\(index == 9 ? 0 : index + 1)"
	}
}

@MainActor
private struct ChannelSpotlightRow: View {
	let result: ChannelSpotlightSearchResult
	let shortcut: String
	let isSelected: Bool

	/* The counts live on an `NSObject` the row cannot observe, so the two tasks
	 below mirror them into state. Storing them is what redraws the row; giving
	 the row a new identity would tear the observations down with it. */
	@State private var highlightCount = 0
	@State private var unreadCount = 0

	private var channel: IRCChannel? {
		result.channel
	}

	var body: some View {
		HStack(spacing: 12) {
			VStack(alignment: .leading, spacing: 2) {
				Text(verbatim: channelTitle)
					.font(.headline)
					.lineLimit(1)
				Text(verbatim: unreadDescription)
					.font(.caption)
					.foregroundStyle(isSelected ? .primary : .secondary)
					.lineLimit(1)
			}
			Spacer()
			Text(verbatim: shortcut)
				.font(.callout.monospacedDigit())
				.foregroundStyle(.secondary)
		}
		.padding(.horizontal, 16)
		.frame(height: 54)
		.background(isSelected ? Color.accentColor : .clear)
		.foregroundStyle(isSelected ? Color.white : Color.primary)
		.task(id: channel?.uniqueIdentifier) {
			guard let channel else { return }
			highlightCount = Int(channel.nicknameHighlightCount)
			for await count in channel.publisher(for: \.nicknameHighlightCount, options: [.new]).bufferedValues {
				highlightCount = Int(count)
			}
		}
		.task(id: channel?.uniqueIdentifier) {
			guard let channel else { return }
			unreadCount = Int(channel.treeUnreadCount)
			for await count in channel.publisher(for: \.treeUnreadCount, options: [.new]).bufferedValues {
				unreadCount = Int(count)
			}
		}
	}

	private var channelTitle: String {
		guard let channel else { return "" }
		return ChannelSpotlightStrings.channelName(channel.name)
			+ ChannelSpotlightStrings.networkSuffix(channel.associatedClient?.networkNameAlt ?? "")
	}

	private var unreadDescription: String {
		guard channel != nil else { return "" }
		return ChannelSpotlightStrings.combined(
			ChannelSpotlightStrings.highlights(highlightCount),
			ChannelSpotlightStrings.unreadMessages(unreadCount)
		)
	}
}
