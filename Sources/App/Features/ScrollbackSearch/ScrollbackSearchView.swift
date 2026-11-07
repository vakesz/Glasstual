// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import SwiftUI

struct ScrollbackSearchView: View {
	@Bindable var model: ScrollbackSearchModel

	@FocusState private var searchIsFocused: Bool

	var body: some View {
		VStack(spacing: 0) {
			filters
			Divider()
			results
		}
		.frame(minWidth: 520, minHeight: 360)
		.defaultFocus($searchIsFocused, true)
		.onAppear { model.refreshTargets() }
		.onKeyPress(.downArrow) {
			model.moveSelection(by: 1)
			return .handled
		}
		.onKeyPress(.upArrow) {
			model.moveSelection(by: -1)
			return .handled
		}
	}

	private var filters: some View {
		VStack(alignment: .leading, spacing: UISpacing.regular) {
			HStack(spacing: UISpacing.wide) {
				Image(systemName: "magnifyingglass")
					.foregroundStyle(.secondary)
					.accessibilityHidden(true)
				TextField(.ScrollbackSearch.searchPlaceholder, text: $model.text)
					.textFieldStyle(.plain)
					.font(.title2)
					.focused($searchIsFocused)
					.accessibilityIdentifier("scrollback-search-field")
					.onSubmit { Task { await model.openSelection() } }
			}
			HStack(spacing: UISpacing.wide) {
				Picker(.ScrollbackSearch.scope, selection: $model.scope) {
					ForEach(ScrollbackSearchScope.allCases) { scope in
						Text(label(for: scope)).tag(scope)
							.disabled(model.isAvailable(scope) == false)
					}
				}
				.pickerStyle(.menu)
				.fixedSize()
				.accessibilityIdentifier("scrollback-search-scope")
				TextField(.ScrollbackSearch.senderPlaceholder, text: $model.sender)
					.frame(maxWidth: 160)
					.accessibilityIdentifier("scrollback-search-sender")
				Toggle(.ScrollbackSearch.limitDates, isOn: $model.restrictsDates)
					.accessibilityIdentifier("scrollback-search-dates")
				if model.restrictsDates {
					DatePicker(.ScrollbackSearch.fromDate, selection: $model.fromDate, displayedComponents: .date)
						.labelsHidden()
					Text(.ScrollbackSearch.dateRangeTo)
						.foregroundStyle(.secondary)
					DatePicker(.ScrollbackSearch.throughDate, selection: $model.throughDate, displayedComponents: .date)
						.labelsHidden()
				}
				Spacer(minLength: 0)
			}
		}
		.padding(UISpacing.loose)
	}

	private func label(for scope: ScrollbackSearchScope) -> String {
		switch scope {
		case .all: String(localized: .ScrollbackSearch.scopeAll)
		case .server: String(localized: .ScrollbackSearch.scopeServer)
		case .conversation: String(localized: .ScrollbackSearch.scopeConversation)
		}
	}

	@ViewBuilder
	private var results: some View {
		switch model.phase {
		case .idle:
			ContentUnavailableView(
				String(localized: .ScrollbackSearch.promptTitle),
				systemImage: "text.magnifyingglass",
				description: Text(.ScrollbackSearch.promptDescription)
			)
		case .searching where model.groups.isEmpty:
			ProgressView()
				.controlSize(.small)
				.frame(maxWidth: .infinity, maxHeight: .infinity)
		case let .failed(reason):
			ContentUnavailableView(
				String(localized: .ScrollbackSearch.failedTitle),
				systemImage: "exclamationmark.triangle",
				description: Text(verbatim: reason)
			)
		case .finished where model.groups.isEmpty:
			ContentUnavailableView.search(text: model.text)
		case .searching, .finished:
			resultList
		}
	}

	private var resultList: some View {
		VStack(spacing: 0) {
			List(selection: $model.selection) {
				ForEach(model.groups) { group in
					Section {
						ForEach(group.rows) { row in
							ScrollbackSearchRowView(row: row, query: model.markedText)
								.tag(row.id)
								.contentShape(.rect)
								.onTapGesture(count: 2) { Task { await model.open(row) } }
								.accessibilityAddTraits(.isButton)
								.accessibilityAction { Task { await model.open(row) } }
						}
					} header: {
						ScrollbackSearchGroupHeader(group: group)
					}
				}
			}
			.listStyle(.inset)
			.accessibilityLabel(Text(.ScrollbackSearch.resultsAccessibilityLabel))
			footer
		}
	}

	private var footer: some View {
		HStack {
			Text(.ScrollbackSearch.resultCount(model.resultCount))
				.foregroundStyle(.secondary)
			if model.isTruncated {
				Text(.ScrollbackSearch.resultsTruncated)
					.foregroundStyle(.secondary)
			}
			if model.revealFailed {
				Text(.ScrollbackSearch.lineNotStored)
					.foregroundStyle(.orange)
			}
			Spacer()
			if model.phase == .searching {
				ProgressView().controlSize(.small)
			}
		}
		.font(.callout)
		.padding(.horizontal, UISpacing.loose)
		.padding(.vertical, UISpacing.regular)
		.background(.bar)
	}
}

private struct ScrollbackSearchGroupHeader: View {
	let group: ScrollbackSearchGroup

	var body: some View {
		HStack(spacing: UISpacing.regular) {
			Text(verbatim: group.conversationName)
				.font(.headline)
			if group.serverName.isEmpty == false {
				Text(verbatim: group.serverName)
					.foregroundStyle(.secondary)
			}
		}
		.accessibilityElement(children: .combine)
		.accessibilityAddTraits(.isHeader)
	}
}

private struct ScrollbackSearchRowView: View {
	let row: ScrollbackSearchRow
	let query: String

	var body: some View {
		VStack(alignment: .leading, spacing: 2) {
			HStack(spacing: UISpacing.regular) {
				Text(verbatim: row.hit.sender)
					.font(.subheadline.weight(.semibold))
				Spacer()
				Text(row.hit.date, format: .dateTime.year().month().day().hour().minute())
					.font(.caption)
					.foregroundStyle(.secondary)
			}
			Text(ScrollbackSearchSnippet.make(text: row.hit.text, query: query))
				.lineLimit(3)
		}
		.padding(.vertical, 2)
		.accessibilityElement(children: .combine)
	}
}
