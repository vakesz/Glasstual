// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import SwiftUI

/// A bounded command list above the editor. The model supplies its height so
/// the transcript can reserve room without measuring SwiftUI during layout.
struct SlashCommandDiscoveryView: View {
	let model: SlashCommandDiscoveryModel
	let insert: (SlashCommandSuggestion) -> Void

	/** The panel's parts, from the text styles they are set in, so the panel
	 grows with the reader's text size the way a completion list does. Each is
	 one or more lines of its style and the system spacing around them; the
	 transcript reserves the same numbers, which is why they are computed from
	 fonts rather than measured from SwiftUI. */
	static var rowHeight: CGFloat {
		lineHeight(.body) + UISpacing.regular * 2
	}

	private static var detailHeight: CGFloat {
		lineHeight(.callout) + UISpacing.tight + lineHeight(.caption1) * CGFloat(detailLineLimit) + UISpacing.regular * 2
	}

	private static var footerHeight: CGFloat {
		lineHeight(.caption2) + UISpacing.regular
	}

	private static let verticalPadding = UISpacing.regular
	private static let maximumVisibleRows = 5
	private static let detailLineLimit = 3

	private static func lineHeight(_ style: NSFont.TextStyle) -> CGFloat {
		ceil(TextLineMetrics.lineHeight(for: .preferredFont(forTextStyle: style)))
	}

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
			.inputAccessorySurface()
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
					.foregroundStyle(selected ? Color(nsColor: .alternateSelectedControlTextColor) : .primary)
				Text(suggestion.description)
					.font(.callout)
					.foregroundStyle(selected ? Color(nsColor: .alternateSelectedControlTextColor) : .secondary)
					.frame(maxWidth: .infinity, alignment: .leading)
			}
			.lineLimit(1)
			.padding(.horizontal, UISpacing.regular)
			.frame(height: Self.rowHeight)
			.frame(maxWidth: .infinity, alignment: .leading)
			.background {
				/* The system's selection style, which follows the accent colour,
				 the window's key state and Increase Contrast by itself. */
				if selected {
					RoundedRectangle(cornerRadius: UISpacing.tight).fill(.selection)
				}
			}
			.contentShape(.rect)
		}
		.buttonStyle(.plain)
		.focusable(false)
		.help(String(localized: .SlashCommands.suggestionTooltip(suggestion.syntax, suggestion.argumentHint)))
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
			Text(model.isEditingCommand
				? suggestion.argumentHint
				: String(localized: .SlashCommands.suggestionDescriptionAndHint(suggestion.description, suggestion.argumentHint)))
				.font(.caption)
				.foregroundStyle(.secondary)
				.lineLimit(Self.detailLineLimit)
				.help(String(localized: .SlashCommands.suggestionTooltip(suggestion.description, suggestion.argumentHint)))
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.frame(height: Self.detailHeight, alignment: .center)
		.padding(.horizontal, UISpacing.regular)
		.accessibilityElement(children: .combine)
	}
}
