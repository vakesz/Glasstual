// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import SwiftUI

/// The Highlights row: how a keyword is matched, and the two lists of words
/// that raise and suppress a highlight.
struct HighlightsPane: View {
	let model: SettingsModel

	private var matchingMethod: NicknameHighlightMatchMode {
		model.preferences[Preferences.Highlights.matchingMethod]
	}

	private var usesRegularExpression: Bool {
		matchingMethod == .regularExpression
	}

	var body: some View {
		Section {
			Picker(selection: model.preferences.binding(for: Preferences.Highlights.matchingMethod)) {
				Text(.Settings.highlightsMatchTypePartial)
					.tag(NicknameHighlightMatchMode.partial)
				Text(.Settings.highlightsMatchTypeExact)
					.tag(NicknameHighlightMatchMode.exact)
				Text(.Settings.highlightsMatchTypeRegex)
					.tag(NicknameHighlightMatchMode.regularExpression)
			} label: {
				Text(.Settings.highlightsMatchTypeLabel)
			}
			.labelsHidden()
			.accessibilityLabel(Text(.Settings.highlightsMatchTypeLabel))

			SettingsToggle(
				title: .Settings.highlightsLogToWindow,
				isOn: model.preferences.binding(for: Preferences.Logging.logHighlights) { _ in
					PreferenceReload.perform(.highlightLogging)
				}
			)
			SettingsToggle(
				title: .Settings.highlightsTrackLocalNickname,
				isEnabled: usesRegularExpression == false,
				isOn: model.preferences.binding(for: Preferences.Highlights.trackLocalNickname)
			)
		}

		Section {
			SettingsKeywordList(
				title: .Settings.highlightsWordsLabel,
				addLabel: .Settings.highlightsAddKeyword,
				removeLabel: .Settings.highlightsRemoveKeyword,
				keywords: model.preferences.binding(for: Preferences.Highlights.matchKeywords),
				usesRegularExpression: usesRegularExpression
			)
			SettingsKeywordList(
				title: .Settings.highlightsExcludeWordsLabel,
				addLabel: .Settings.highlightsAddExcluded,
				removeLabel: .Settings.highlightsRemoveExcluded,
				keywords: model.preferences.binding(for: Preferences.Highlights.excludeKeywords)
			)
			.disabled(usesRegularExpression)
		}
	}
}

/// One of the two keyword tables in the Highlights pane, with its add and
/// remove buttons.
struct SettingsKeywordList: View {
	private static let listHeight = 140.0

	let title: LocalizedStringResource
	let addLabel: LocalizedStringResource
	let removeLabel: LocalizedStringResource
	@Binding var keywords: [HighlightKeyword]
	/// Whether these keywords are matched as regular expressions, which is what
	/// decides whether an unusable pattern is an error worth showing.
	var usesRegularExpression = false
	/** One identity per row, in the order of `keywords`.

	 Rows identified by their position hand focus and selection to whichever
	 row slides into the place of one that was removed, so a blank row dropped
	 when focus left it took the next row's focus with it. */
	@State private var rowIdentities = SettingsKeywordRowIdentities()
	@State private var selection: UUID?
	@FocusState private var focusedKeyword: UUID?

	var body: some View {
		VStack(alignment: .leading, spacing: SettingsMetrics.spacingMedium) {
			Text(title)

			List(selection: $selection) {
				ForEach(Array(rowIdentities.identities.enumerated()), id: \.element) { index, identity in
					HStack(spacing: SettingsMetrics.spacingSmall) {
						TextField(
							text: binding(for: identity),
							prompt: Text(.Settings.highlightsNewKeyword)
						) {
							Text(title)
						}
						.labelsHidden()
						.textFieldStyle(.plain)
						.focused($focusedKeyword, equals: identity)
						.accessibilityLabel(Text(title))

						if let error = patternError(at: index) {
							Image(systemName: "exclamationmark.triangle.fill")
								.foregroundStyle(.orange)
								.help(Text(verbatim: error))
								.accessibilityLabel(Text(verbatim: error))
						}
					}
				}
			}
			.frame(height: Self.listHeight)
			.accessibilityLabel(Text(title))
			.onChange(of: keywords.count, initial: true) { _, count in
				rowIdentities.match(count: count)
			}
			/* A row that was added and then left blank is one nobody asked for:
			 dropping it here is what keeps a placeholder keyword out of the
			 stored list, which is where the renderer reads it from. */
			.onChange(of: focusedKeyword) { previous, _ in
				guard let previous, let index = index(of: previous), isBlank(at: index) else { return }
				removeRow(at: index)
			}

			HStack(spacing: SettingsMetrics.spacingMedium) {
				Button(action: add) {
					Image(systemName: "plus")
				}
				.help(Text(addLabel))
				.accessibilityLabel(Text(addLabel))

				Button(role: .destructive, action: remove) {
					Image(systemName: "minus")
				}
				.help(Text(removeLabel))
				.accessibilityLabel(Text(removeLabel))
				.disabled(selection == nil)
			}
		}
	}

	/// The keyword at `index` is reported where it is typed, rather than
	/// failing silently in the renderer when the pattern will not compile.
	private func patternError(at index: Int) -> String? {
		guard keywords.indices.contains(index) else { return nil }
		let keyword = keywords[index].string.trimmingCharacters(in: .whitespacesAndNewlines)
		guard keyword.isEmpty == false else { return nil }

		return HighlightKeywordPattern.validationError(
			for: keyword,
			usesRegularExpression: usesRegularExpression
		)
	}

	private func isBlank(at index: Int) -> Bool {
		guard keywords.indices.contains(index) else { return false }
		return keywords[index].string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
	}

	private func index(of identity: UUID) -> Int? {
		guard let index = rowIdentities.identities.firstIndex(of: identity), keywords.indices.contains(index) else {
			return nil
		}
		return index
	}

	private func binding(for identity: UUID) -> Binding<String> {
		Binding(
			get: { index(of: identity).map { keywords[$0].string } ?? "" },
			set: { newValue in
				guard let index = index(of: identity) else { return }
				keywords[index].string = newValue
			}
		)
	}

	private func add() {
		rowIdentities.match(count: keywords.count)
		let identity = rowIdentities.append()
		keywords.append(HighlightKeyword(string: ""))
		selection = identity
		focusedKeyword = identity
	}

	private func remove() {
		guard let selection, let index = index(of: selection) else { return }
		removeRow(at: index)
	}

	private func removeRow(at index: Int) {
		let identity = rowIdentities.remove(at: index)
		keywords.remove(at: index)
		if selection == identity {
			selection = nil
		}
	}
}

/** The identities of a keyword list's rows.

 The stored list has no identity of its own — a keyword is its text, and two
 rows can hold the same text — so the rows get one here. A list that changed
 length without going through this, an import say, is given fresh identities. */
struct SettingsKeywordRowIdentities {
	private(set) var identities: [UUID] = []

	/// Gives every row of a list with `count` rows an identity, keeping the
	/// ones it has while the count still agrees.
	mutating func match(count: Int) {
		guard identities.count != count else { return }
		identities = (0 ..< count).map { _ in UUID() }
	}

	/// Records a row appended to the end of the list.
	mutating func append() -> UUID {
		let identity = UUID()
		identities.append(identity)
		return identity
	}

	/// Forgets the row at `index`, returning its identity.
	mutating func remove(at index: Int) -> UUID {
		identities.remove(at: index)
	}
}
