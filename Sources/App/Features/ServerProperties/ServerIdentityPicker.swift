// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import SwiftUI

/// Edits the sheet's draft configuration. Saving the sheet applies the same
/// identity to the server and its conversations in Favorites.
struct ServerIdentityPicker: View {
	@Binding var style: ServerIdentityStyle
	let name: String

	var body: some View {
		Section {
			LabeledContent {
				Label(name, systemImage: style.icon.symbolName)
					.labelStyle(ServerIdentityPreviewStyle(tint: Color(nsColor: style.color.nsColor)))
					.accessibilityElement(children: .ignore)
					.accessibilityLabel(name)
					.accessibilityValue(style.color.title + ", " + style.icon.title)
			} label: {
				Text(.ServerIdentity.preview)
			}

			LabeledContent {
				HStack(spacing: UISpacing.tight) {
					ForEach(ServerIdentityStyle.Color.allCases, id: \.self) { color in
						colorButton(color)
					}
				}
			} label: {
				Text(.ServerIdentity.color)
			}

			Picker(.ServerIdentity.icon, selection: $style.icon) {
				ForEach(ServerIdentityStyle.Icon.allCases, id: \.self) { icon in
					Label(icon.title, systemImage: icon.symbolName).tag(icon)
				}
			}
			.pickerStyle(.menu)
			.accessibilityIdentifier("server-identity-icon")

			Button(.ServerIdentity.reset) { style = ServerIdentityStyle() }
				.disabled(style == ServerIdentityStyle())
		} header: {
			Text(.ServerIdentity.appearance)
		} footer: {
			Text(.ServerIdentity.appearanceHelp)
		}
	}

	private func colorButton(_ color: ServerIdentityStyle.Color) -> some View {
		let selected = style.color == color
		return Button {
			style.color = color
		} label: {
			Circle()
				.fill(Color(nsColor: color.nsColor))
				.frame(width: 18, height: 18)
				.overlay {
					if selected {
						Image(systemName: "checkmark")
							.font(.caption2.weight(.bold))
							.foregroundStyle(Color(nsColor: color.nsColor.legibleForeground))
					}
				}
				.padding(4)
				.overlay {
					Circle().strokeBorder(selected ? Color.primary : .clear, lineWidth: 1)
				}
				.contentShape(.circle)
		}
		.buttonStyle(.plain)
		.help(color.title)
		.accessibilityLabel(color.title)
		.accessibilityAddTraits(selected ? .isSelected : [])
		.accessibilityIdentifier("server-identity-color-" + color.rawValue)
	}
}

private struct ServerIdentityPreviewStyle: LabelStyle {
	let tint: Color

	func makeBody(configuration: Configuration) -> some View {
		HStack(spacing: UISpacing.regular) {
			configuration.icon.foregroundStyle(tint)
			configuration.title.foregroundStyle(.primary)
		}
		.font(.body.weight(.semibold))
	}
}
