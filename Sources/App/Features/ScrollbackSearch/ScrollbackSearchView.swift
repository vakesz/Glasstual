// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import SwiftUI

struct ScrollbackSearchView: View {
	@Bindable var model: ScrollbackSearchModel

	@State private var showsFilters = false

	var body: some View {
		results
			.frame(minWidth: 520, minHeight: 360)
			.navigationSubtitle(subtitle)
			.searchable(
				text: $model.text,
				placement: .toolbar,
				prompt: Text(.ScrollbackSearch.searchPlaceholder)
			)
			.searchScopes($model.scope) {
				ForEach(ScrollbackSearchScope.allCases.filter(model.isAvailable)) { scope in
					Text(label(for: scope)).tag(scope)
				}
			}
			.onSubmit(of: .search) { Task { await model.openSelection() } }
			.toolbar {
				ToolbarItem(placement: .primaryAction) {
					filtersButton
				}
			}
			.alert(
				String(localized: .ScrollbackSearch.lineNotStored),
				isPresented: revealFailurePresented
			) {}
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

	/// Sender and dates narrow a search the way Mail's filter does: one
	/// toolbar button, filled while a filter applies.
	private var filtersButton: some View {
		Button(
			String(localized: .ScrollbackSearch.filters),
			systemImage: model.hasFilters
				? "line.3.horizontal.decrease.circle.fill"
				: "line.3.horizontal.decrease.circle"
		) {
			showsFilters.toggle()
		}
		.help(String(localized: .ScrollbackSearch.filters))
		.accessibilityIdentifier(AccessibilityIdentifier.scrollbackSearchFilters)
		.popover(isPresented: $showsFilters, arrowEdge: .bottom) {
			ScrollbackSearchFilters(model: model)
		}
	}

	private var subtitle: String {
		guard model.phase == .finished || model.phase == .searching, model.groups.isEmpty == false else { return "" }
		return model.isTruncated
			? String(localized: .ScrollbackSearch.resultCountTruncated(model.resultCount))
			: String(localized: .ScrollbackSearch.resultCount(model.resultCount))
	}

	private var revealFailurePresented: Binding<Bool> {
		Binding(
			get: { model.revealFailed },
			set: {
				if $0 == false {
					model.dismissRevealFailure()
				}
			}
		)
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
		List(selection: $model.selection) {
			ForEach(model.groups) { group in
				Section {
					ForEach(group.rows) { row in
						ScrollbackSearchRowView(row: row, query: model.markedText)
							.tag(row.id)
							.accessibilityAction { Task { await model.open(row) } }
					}
				} header: {
					ScrollbackSearchGroupHeader(group: group)
				}
			}
		}
		.listStyle(.inset)
		.contextMenu(forSelectionType: ScrollbackSearchRow.ID.self) { _ in
		} primaryAction: { _ in
			Task { await model.openSelection() }
		}
		.accessibilityLabel(Text(.ScrollbackSearch.resultsAccessibilityLabel))
	}
}

/// The sender and date filters, in the popover the toolbar's filter button shows.
private struct ScrollbackSearchFilters: View {
	@Bindable var model: ScrollbackSearchModel

	var body: some View {
		Form {
			TextField(
				String(localized: .ScrollbackSearch.sender),
				text: $model.sender,
				prompt: Text(.ScrollbackSearch.senderPlaceholder)
			)
			.accessibilityIdentifier("scrollback-search-sender")
			Toggle(.ScrollbackSearch.limitDates, isOn: $model.restrictsDates)
				.accessibilityIdentifier("scrollback-search-dates")
			if model.restrictsDates {
				DatePicker(.ScrollbackSearch.fromDate, selection: $model.fromDate, displayedComponents: .date)
				DatePicker(.ScrollbackSearch.throughDate, selection: $model.throughDate, displayedComponents: .date)
			}
		}
		.formStyle(.grouped)
		.frame(width: 320)
		.fixedSize(horizontal: false, vertical: true)
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
