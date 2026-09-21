// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import SwiftUI

/// A bounded command list above the editor. The model supplies its height so
/// the transcript can reserve room without measuring SwiftUI during layout.
struct SlashCommandDiscoveryView: View {
	let model: SlashCommandDiscoveryModel
	let insert: (SlashCommandSuggestion) -> Void

	static let rowHeight: CGFloat = 32
	private static let detailHeight: CGFloat = 84
	private static let footerHeight: CGFloat = 22
	private static let verticalPadding: CGFloat = 8
	private static let maximumVisibleRows = 5

	static func height(for model: SlashCommandDiscoveryModel) -> CGFloat {
		guard model.isVisible else { return 0 }
		let listHeight = model.isEditingCommand
			? CGFloat(min(maximumVisibleRows, model.suggestions.count)) * rowHeight + 1 + footerHeight
			: 0
		return detailHeight + verticalPadding * 2 + listHeight
	}

	var body: some View {
		if let selected = model.selectedSuggestion {
			VStack(spacing: 0) {
				if model.isEditingCommand {
					commandList
					Divider()
				}
				detail(selected)
				if model.isEditingCommand {
					Text(keyboardHint)
						.font(.caption2)
						.foregroundStyle(.secondary)
						.lineLimit(1)
						.frame(maxWidth: .infinity, alignment: .leading)
						.frame(height: Self.footerHeight)
						.padding(.horizontal, UISpacing.regular)
				}
			}
			.padding(.vertical, Self.verticalPadding)
			.frame(height: Self.height(for: model))
			.glassEffect(.regular, in: .rect(cornerRadius: 12))
			.accessibilityElement(children: .contain)
			.accessibilityLabel(String(localized: .SlashCommands.commandSuggestions))
			.accessibilityIdentifier("slash-command-discovery")
		}
	}

	private var keyboardHint: String {
		SettingsKeys.Input.tabKeyAction.value == .nicknameComplete
			? String(localized: .SlashCommands.keyboardHint)
			: String(localized: .SlashCommands.keyboardHintWithoutTab)
	}

	private var commandList: some View {
		ScrollViewReader { scroll in
			ScrollView {
				LazyVStack(spacing: 0) {
					ForEach(model.suggestions) { suggestion in
						commandRow(suggestion)
							.id(suggestion.id)
					}
				}
			}
			.frame(height: CGFloat(min(Self.maximumVisibleRows, model.suggestions.count)) * Self.rowHeight)
			.onChange(of: model.selectedSuggestion?.id) { _, identifier in
				if let identifier {
					scroll.scrollTo(identifier)
				}
			}
		}
	}

	private func commandRow(_ suggestion: SlashCommandSuggestion) -> some View {
		let selected = model.selectedSuggestion?.id == suggestion.id
		return Button {
			insert(suggestion)
		} label: {
			HStack(spacing: UISpacing.regular) {
				Text("/" + suggestion.name)
					.font(.system(.body, design: .monospaced))
					.foregroundStyle(.primary)
				Text(suggestion.description)
					.font(.callout)
					.foregroundStyle(.secondary)
					.frame(maxWidth: .infinity, alignment: .leading)
			}
			.lineLimit(1)
			.padding(.horizontal, UISpacing.regular)
			.frame(height: Self.rowHeight)
			.frame(maxWidth: .infinity, alignment: .leading)
			.background(selected ? Color.accentColor.opacity(0.16) : .clear)
			.contentShape(.rect)
		}
		.buttonStyle(.plain)
		.focusable(false)
		.help(suggestion.syntax + "\n" + suggestion.argumentHint)
		.accessibilityAddTraits(selected ? .isSelected : [])
		.accessibilityIdentifier("slash-command-" + suggestion.name)
	}

	private func detail(_ suggestion: SlashCommandSuggestion) -> some View {
		VStack(alignment: .leading, spacing: UISpacing.tight) {
			ScrollView(.horizontal) {
				Text(suggestion.syntax)
					.font(.system(.callout, design: .monospaced).weight(.medium))
					.fixedSize()
			}
			.scrollIndicators(.hidden)
			Text(model.isEditingCommand ? suggestion.argumentHint : suggestion.description + " " + suggestion.argumentHint)
				.font(.caption)
				.foregroundStyle(.secondary)
				.lineLimit(3)
				.help(suggestion.description + "\n" + suggestion.argumentHint)
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.frame(height: Self.detailHeight, alignment: .center)
		.padding(.horizontal, UISpacing.regular)
		.accessibilityElement(children: .combine)
	}
}
