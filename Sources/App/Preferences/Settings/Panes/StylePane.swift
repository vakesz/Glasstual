/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
import SwiftUI

/// One colour the transcript theme names, with the two wells that set it.
private struct TranscriptThemeColorRole: Identifiable {
	let id: String
	let title: LocalizedStringResource
	let keyPath: WritableKeyPath<TranscriptThemePalette, AdaptiveTranscriptColor>

	static let all = [
		Self(id: "background", title: .TranscriptTheme.background, keyPath: \.background),
		Self(id: "primaryText", title: .TranscriptTheme.primaryText, keyPath: \.primaryText),
		Self(id: "secondaryText", title: .TranscriptTheme.secondaryText, keyPath: \.secondaryText),
		Self(id: "timestampText", title: .TranscriptTheme.timestampText, keyPath: \.timestampText),
		Self(id: "eventText", title: .TranscriptTheme.eventText, keyPath: \.eventText),
		Self(id: "link", title: .TranscriptTheme.links, keyPath: \.link),
		Self(id: "localNickname", title: .TranscriptTheme.yourNickname, keyPath: \.localNickname),
		Self(id: "remoteNickname", title: .TranscriptTheme.otherNicknames, keyPath: \.remoteNickname),
		Self(
			id: "highlightBackground",
			title: .TranscriptTheme.highlightBackground,
			keyPath: \.highlightBackground
		),
		Self(id: "highlightText", title: .TranscriptTheme.highlightText, keyPath: \.highlightText),
		Self(id: "bubbleIncoming", title: .TranscriptTheme.incomingBubble, keyPath: \.bubbleIncoming),
		Self(id: "bubbleOutgoing", title: .TranscriptTheme.outgoingBubble, keyPath: \.bubbleOutgoing),
		Self(id: "unreadMarker", title: .TranscriptTheme.unreadMarker, keyPath: \.unreadMarker),
		Self(id: "failure", title: .TranscriptTheme.failure, keyPath: \.failure),
	]
}

/// The Style row: the transcript theme, the colours and spacing it draws with,
/// and what the transcript shows.
struct StylePane: View {
	private static let scrollbackPresets = [
		"1000", "2000", "3000", "4000", "5000", "10000", "20000", "30000", "40000", "50000",
	]
	/** The default first: a preset list whose first entry is not what the app
	 ships with reads as though the shipped format were a custom one. */
	private static let nicknamePresets = [
		"%@%n:", "%@%n", "%n: ", "%@%n: ", "(%n) ", "<%n> ", "<%@%n> ", "<%@%-9n>",
	]
	/// The default first, for the reason above: what the app ships with is
	/// `%H:%M:%S`, and a list that started with a bracketed format made the
	/// shipped one look like something the person had typed themselves.
	private static let timestampPresets = [
		"%H:%M:%S", "[%H:%M]", "[%H:%M:%S]", "[%I:%M:%S %p]", "[%m/%d/%Y -:- %I:%M:%S %p]",
	]

	let model: SettingsModel
	@State private var confirmsThemeReset = false

	var body: some View {
		Section {
			LabeledContent {
				SettingsCommittedField(title: .TranscriptTheme.themeName, value: themeName)
			} label: {
				Text(.TranscriptTheme.themeName)
			}
			Picker(selection: themeLayout) {
				Text(.TranscriptTheme.lines).tag(TranscriptThemeLayout.lines)
				Text(.TranscriptTheme.bubbles).tag(TranscriptThemeLayout.bubbles)
			} label: {
				Text(.TranscriptTheme.layout)
			}
			fontRow
			HStack {
				Button(String(localized: .TranscriptTheme.importTheme)) { model.importTranscriptTheme() }
				Button(String(localized: .TranscriptTheme.exportTheme)) { model.exportTranscriptTheme() }
				Spacer()
				Button(String(localized: .Settings.interfaceResetToDefaults), role: .destructive) {
					confirmResetTranscriptTheme()
				}
				.help(Text(.Settings.interfaceResetThemeConfirmation))
				.confirmationDialog(
					Text(.Settings.interfaceResetThemeConfirmation),
					isPresented: $confirmsThemeReset
				) {
					Button(String(localized: .Settings.interfaceResetToDefaults), role: .destructive) {
						model.resetTranscriptTheme()
					}
					Button(PromptStrings.Action.cancel, role: .cancel) {}
				} message: {
					Text(.Settings.interfaceResetThemeConfirmationBody)
				}
			}
		} header: {
			Text(.TranscriptTheme.transcriptTheme)
		}

		Section {
			colorGrid
		} header: {
			Text(.TranscriptTheme.colors)
		} footer: {
			SettingsNote(.TranscriptTheme.roleColorNote)
		}

		Section {
			formatFields
			spacingStepper(.TranscriptTheme.lineSpacing, value: lineSpacing, in: 0 ... 16)
			spacingStepper(.TranscriptTheme.messageSpacing, value: messageSpacing, in: 0 ... 32)
			spacingStepper(.TranscriptTheme.horizontalPadding, value: horizontalPadding, in: 0 ... 48)
		} header: {
			Text(.Settings.styleHeadingLayout)
		}

		Section {
			SettingsToggle(
				title: .Settings.styleAutoScrollbackMarker,
				isOn: model.preferences.binding(for: Preferences.Messages.autoAddScrollbackMark)
			)
			SettingsToggle(
				title: .Settings.styleShowDateChanges,
				isOn: model.preferences.binding(for: Preferences.Messages.showDateChanges)
			)
			SettingsToggle(
				title: .Settings.styleShowJoinLeave,
				isOn: model.preferences.binding(for: Preferences.Messages.showJoinLeave)
			)
			SettingsToggle(
				title: .TranscriptTheme.showInlineImages,
				isOn: model.preferences.binding(for: Preferences.Messages.showInlineMedia)
			)
			SettingsToggle(
				title: .Settings.styleDisableNicknameColors,
				isOn: model.preferences.binding(for: Preferences.Messages.disableNicknameColorHashing)
			)
			SettingsToggle(
				title: .Settings.styleShowMotd,
				isOn: model.preferences.binding(for: Preferences.Connection.displayServerMOTD)
			)
		} header: {
			Text(.Settings.headingGeneral)
		}

		Section {
			LabeledContent {
				SettingsComboField(
					title: .Settings.styleScrollbackSaveLimit,
					presets: Self.scrollbackPresets,
					value: model.preferences.numberField(
						for: Preferences.Logging.scrollbackSaveLimit
					) { PreferenceReload.perform(.scrollbackSaveLimit) },
					rejectionMessage: .PreferencesTransfer.enterAValidWholeNumber
				)
			} label: {
				Text(.Settings.styleScrollbackSaveLimit)
			}
		} header: {
			Text(.Settings.styleHeadingScrollback)
		} footer: {
			SettingsNote(.Settings.styleScrollbackSaveLimitNote)
		}
	}

	/// The light and dark wells of every colour role, in a grid so that the
	/// two columns line up and carry real headings.
	private var colorGrid: some View {
		Grid(
			alignment: .leading,
			horizontalSpacing: SettingsMetrics.spacingLarge,
			verticalSpacing: SettingsMetrics.spacingMedium
		) {
			GridRow {
				Color.clear.frame(width: 0, height: 0)
				columnHeader(.TranscriptTheme.light)
				columnHeader(.TranscriptTheme.dark)
			}
			.accessibilityHidden(true)

			ForEach(TranscriptThemeColorRole.all) { role in
				GridRow {
					Text(role.title)
						.gridColumnAlignment(.leading)
					colorWell(role, dark: false)
					colorWell(role, dark: true)
				}
			}
		}
		.frame(maxWidth: .infinity, alignment: .leading)
	}

	private func columnHeader(_ title: LocalizedStringResource) -> some View {
		Text(title)
			.font(.caption)
			.foregroundStyle(.secondary)
	}

	private func colorWell(_ role: TranscriptThemeColorRole, dark: Bool) -> some View {
		let appearance = String(localized: dark ? .TranscriptTheme.dark : .TranscriptTheme.light)
		return ColorPicker(appearance, selection: color(role, dark: dark), supportsOpacity: true)
			.labelsHidden()
			.accessibilityLabel(Text(.Settings.styleColorAccessibility(
				String(localized: role.title),
				appearance
			)))
	}

	private var fontRow: some View {
		LabeledContent {
			HStack {
				Text(.Settings.styleFontDescription(
					model.transcriptTheme.fontName,
					Double(model.transcriptTheme.fontSize)
						.formatted(.number.precision(.fractionLength(0 ... 1)))
				))
				Spacer()
				Button(String(localized: .Settings.styleFontChange)) { model.selectChannelViewFont() }
			}
		} label: {
			Text(.Settings.styleFontLabel)
		}
	}

	private func spacingStepper(
		_ label: LocalizedStringResource,
		value: Binding<Double>,
		in range: ClosedRange<Double>
	) -> some View {
		LabeledContent {
			Stepper(value: value, in: range) {
				Text(verbatim: value.wrappedValue.formatted())
			}
			.accessibilityLabel(Text(label))
		} label: {
			Text(label)
		}
	}

	@ViewBuilder
	private var formatFields: some View {
		LabeledContent {
			SettingsComboField(
				title: .Settings.styleNicknameFormatLabel,
				presets: Self.nicknamePresets,
				value: themeText(\.nicknameFormat)
			)
		} label: {
			Text(.Settings.styleNicknameFormatLabel)
			Text(verbatim: "\(String(localized: .Settings.styleFormatSymbolsLabel)) %@ = "
				+ "\(String(localized: .Settings.styleNicknameFormatSymbolMode)); "
				+ "%n = \(String(localized: .Settings.styleNicknameFormatSymbolNickname))")
		}

		LabeledContent {
			SettingsComboField(
				title: .Settings.styleTimestampFormatLabel,
				presets: Self.timestampPresets,
				value: themeText(\.timestampFormat)
			)
		} label: {
			Text(.Settings.styleTimestampFormatLabel)
			Text(.Settings.styleTimestampFormatNote)
		}
	}

	/// A customised theme cannot be brought back once it is replaced, so the
	/// reset asks first; a theme still at its defaults has nothing to lose.
	private func confirmResetTranscriptTheme() {
		guard hasCustomTranscriptTheme else {
			model.resetTranscriptTheme()
			return
		}

		confirmsThemeReset = true
	}

	private var hasCustomTranscriptTheme: Bool {
		let theme = model.transcriptTheme
		return theme != (theme.layout == .bubbles ? .bubbles : .lines)
	}

	/// A theme with an empty name is rejected, so a blank entry restores the
	/// stored one rather than being written.
	private var themeName: SettingsFieldValue {
		SettingsFieldValue(
			text: { model.transcriptTheme.name },
			write: { newValue in
				let name = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
				guard name.isEmpty == false, name != model.transcriptTheme.name else { return true }
				return model.updateTheme { $0.name = name }
			}
		)
	}

	private var themeLayout: Binding<TranscriptThemeLayout> {
		themeBinding(\.layout)
	}

	private var lineSpacing: Binding<Double> {
		themeBinding(\.lineSpacing)
	}

	private var messageSpacing: Binding<Double> {
		themeBinding(\.messageSpacing)
	}

	private var horizontalPadding: Binding<Double> {
		themeBinding(\.horizontalPadding)
	}

	/** A text field over the theme that writes when editing ends.

	 Every write re-validates, persists and republishes the whole theme to every
	 open transcript, which is what a format typed one keystroke at a time used
	 to cost per keystroke. */
	private func themeText(_ keyPath: WritableKeyPath<TranscriptTheme, String>) -> SettingsFieldValue {
		SettingsFieldValue(
			text: { model.transcriptTheme[keyPath: keyPath] },
			write: { value in
				guard value != model.transcriptTheme[keyPath: keyPath] else { return true }
				return model.updateTheme { $0[keyPath: keyPath] = value }
			}
		)
	}

	private func themeBinding<Value>(_ keyPath: WritableKeyPath<TranscriptTheme, Value>) -> Binding<Value> {
		Binding(
			get: { model.transcriptTheme[keyPath: keyPath] },
			set: { value in model.updateTheme { $0[keyPath: keyPath] = value } }
		)
	}

	private func color(_ role: TranscriptThemeColorRole, dark: Bool) -> Binding<Color> {
		Binding(
			get: {
				let pair = model.transcriptTheme.palette[keyPath: role.keyPath]
				return Color(nsColor: (dark ? pair.dark : pair.light).color)
			},
			set: { value in
				guard let components = TranscriptThemeColor(NSColor(value)) else { return }
				model.updateTheme {
					if dark {
						$0.palette[keyPath: role.keyPath].dark = components
					} else {
						$0.palette[keyPath: role.keyPath].light = components
					}
				}
			}
		)
	}
}
