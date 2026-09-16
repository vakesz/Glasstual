/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import AppKit
import SwiftUI

struct PreferencesInterfaceSections: View {
	let model: PreferencesPaneModel
	@State private var confirmsUserListColorReset = false

	var body: some View {
		Section {
			PreferencesToggle(
				title: PreferencesInterfaceStrings.rightToLeftText,
				isOn: model.preferences.binding(for: Preferences.Messages.rightToLeftFormatting) { _ in
					TextualPreferences.performReloadAction([.style, .textDirection])
				}
			)
			appearancePicker
			PreferencesToggle(
				title: PreferencesInterfaceStrings.noModeSymbol,
				isOn: model.preferences.binding(for: Preferences.Appearance.memberListNoModeSymbol) { _ in
					TextualPreferences.performReloadAction([.memberListUserBadges, .memberList])
				}
			)
			PreferencesToggle(
				title: PreferencesInterfaceStrings.staffAtTop,
				isOn: model.preferences.binding(
					for: Preferences.Appearance.memberListSortFavorsServerStaff
				) { _ in TextualPreferences.performReloadAction(.memberListSortOrder) }
			)
			PreferencesToggle(
				title: PreferencesInterfaceStrings.popoverUpdatesOnScroll,
				isOn: model.preferences.binding(for: Preferences.Appearance.memberListUpdatesPopoverOnScroll)
			)
		} header: {
			Text(verbatim: PreferencesSectionStrings.general)
		}

		Section {
			serverListBadgeColor
		} header: {
			Text(verbatim: PreferencesInterfaceStrings.headingServerListColors)
		}

		Section {
			ForEach(UserListModeBadge.allCases, id: \.self) { badge in
				ColorPicker(
					selection: model.preferences.colorBinding(for: badge.preferenceKey) {
						TextualPreferences.performReloadAction(
							.memberListUserBadges,
							forKey: badge.preferenceKey.name
						)
					},
					supportsOpacity: false
				) {
					Text(verbatim: badge.title)
				}
			}
			Button(PreferencesInterfaceStrings.resetToDefaults, role: .destructive) {
				confirmResetUserListColors()
			}
			.help(Text(verbatim: PreferencesInterfaceStrings.resetUserListColors))
			.accessibilityLabel(Text(verbatim: PreferencesInterfaceStrings.resetUserListColors))
			.confirmationDialog(
				PreferencesInterfaceStrings.resetColorsConfirmationTitle,
				isPresented: $confirmsUserListColorReset
			) {
				Button(PreferencesInterfaceStrings.resetToDefaults, role: .destructive) {
					resetUserListColors()
				}
				Button(PromptStrings.Action.cancel, role: .cancel) {}
			} message: {
				Text(verbatim: PreferencesInterfaceStrings.resetColorsConfirmationBody)
			}
		} header: {
			Text(verbatim: PreferencesInterfaceStrings.headingUserListColors)
		} footer: {
			PreferencesNote(PreferencesInterfaceStrings.userListColorsNote)
		}
	}

	private var appearancePicker: some View {
		Picker(selection: model.preferences.binding(for: Preferences.Appearance.preferredAppearance) { _ in
			TextualPreferences.performReloadAction(.appearance)
		}) {
			/* From `allCases`, so the picker offers every appearance the type
			 declares: three rows spelled out here is three rows that go on
			 saying three when a fourth is added. */
			ForEach(PreferredAppearance.allCases, id: \.self) { appearance in
				Text(verbatim: appearance.title).tag(appearance)
			}
		} label: {
			Text(verbatim: PreferencesInterfaceStrings.appearanceLabel)
		}
	}

	private var serverListBadgeColor: some View {
		HStack {
			ColorPicker(
				selection: model.preferences.storedColorBinding(
					for: Preferences.Badges.serverListUnreadHighlight
				) { TextualPreferences.performReloadAction(.serverListUnreadBadges) },
				supportsOpacity: false
			) {
				Text(verbatim: PreferencesInterfaceStrings.unreadHighlightColorLabel)
			}
			Spacer()
			Button(PreferencesInterfaceStrings.reset) {
				model.preferences.reset(Preferences.Badges.serverListUnreadHighlight)
				TextualPreferences.performReloadAction(.serverListUnreadBadges)
			}
			.help(Text(verbatim: PreferencesInterfaceStrings.resetUnreadHighlightColor))
			.accessibilityLabel(Text(verbatim: PreferencesInterfaceStrings.resetUnreadHighlightColor))
		}
	}

	/// Colours the user picked are gone for good, so a reset that would throw
	/// any away asks first. With nothing customised there is nothing to lose.
	private func confirmResetUserListColors() {
		guard hasCustomUserListColors else {
			resetUserListColors()
			return
		}

		confirmsUserListColorReset = true
	}

	private var hasCustomUserListColors: Bool {
		UserListModeBadge.allCases.contains { model.preferences[stored: $0.preferenceKey] != nil }
	}

	private func resetUserListColors() {
		for badge in UserListModeBadge.allCases {
			model.preferences.reset(badge.preferenceKey)
		}
		TextualPreferences.performReloadAction([.memberListUserBadges, .memberList])
	}
}

private struct TranscriptThemeColorRole: Identifiable {
	let id: String
	let title: String
	let keyPath: WritableKeyPath<TranscriptThemePalette, AdaptiveTranscriptColor>

	static let all = [
		Self(id: "background", title: TranscriptThemeStrings.background, keyPath: \.background),
		Self(id: "primaryText", title: TranscriptThemeStrings.primaryText, keyPath: \.primaryText),
		Self(id: "secondaryText", title: TranscriptThemeStrings.secondaryText, keyPath: \.secondaryText),
		Self(id: "timestampText", title: TranscriptThemeStrings.timestampText, keyPath: \.timestampText),
		Self(id: "eventText", title: TranscriptThemeStrings.eventText, keyPath: \.eventText),
		Self(id: "link", title: TranscriptThemeStrings.links, keyPath: \.link),
		Self(id: "localNickname", title: TranscriptThemeStrings.yourNickname, keyPath: \.localNickname),
		Self(id: "remoteNickname", title: TranscriptThemeStrings.otherNicknames, keyPath: \.remoteNickname),
		Self(
			id: "highlightBackground",
			title: TranscriptThemeStrings.highlightBackground,
			keyPath: \.highlightBackground
		),
		Self(id: "highlightText", title: TranscriptThemeStrings.highlightText, keyPath: \.highlightText),
		Self(id: "bubbleIncoming", title: TranscriptThemeStrings.incomingBubble, keyPath: \.bubbleIncoming),
		Self(id: "bubbleOutgoing", title: TranscriptThemeStrings.outgoingBubble, keyPath: \.bubbleOutgoing),
		Self(id: "unreadMarker", title: TranscriptThemeStrings.unreadMarker, keyPath: \.unreadMarker),
		Self(id: "failure", title: TranscriptThemeStrings.failure, keyPath: \.failure),
	]
}

struct PreferencesStyleSections: View {
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

	let model: PreferencesPaneModel
	@State private var confirmsThemeReset = false

	var body: some View {
		Section {
			LabeledContent {
				PreferencesCommittedField(title: TranscriptThemeStrings.themeName, value: themeName)
			} label: {
				Text(verbatim: TranscriptThemeStrings.themeName)
			}
			Picker(TranscriptThemeStrings.layout, selection: themeLayout) {
				Text(verbatim: TranscriptThemeStrings.lines).tag(TranscriptThemeLayout.lines)
				Text(verbatim: TranscriptThemeStrings.bubbles).tag(TranscriptThemeLayout.bubbles)
			}
			fontRow
			HStack {
				Button(TranscriptThemeStrings.importTheme) { model.importTranscriptTheme() }
				Button(TranscriptThemeStrings.exportTheme) { model.exportTranscriptTheme() }
				Spacer()
				Button(PreferencesInterfaceStrings.resetToDefaults, role: .destructive) {
					confirmResetTranscriptTheme()
				}
				.help(Text(verbatim: PreferencesInterfaceStrings.resetThemeConfirmationTitle))
				.confirmationDialog(
					PreferencesInterfaceStrings.resetThemeConfirmationTitle,
					isPresented: $confirmsThemeReset
				) {
					Button(PreferencesInterfaceStrings.resetToDefaults, role: .destructive) {
						model.resetTranscriptTheme()
					}
					Button(PromptStrings.Action.cancel, role: .cancel) {}
				} message: {
					Text(verbatim: PreferencesInterfaceStrings.resetThemeConfirmationBody)
				}
			}
		} header: {
			Text(verbatim: TranscriptThemeStrings.transcriptTheme)
		}

		Section {
			colorGrid
		} header: {
			Text(verbatim: TranscriptThemeStrings.colors)
		} footer: {
			PreferencesNote(TranscriptThemeStrings.roleColorNote)
		}

		Section {
			formatFields
			spacingStepper(TranscriptThemeStrings.lineSpacing, value: lineSpacing, in: 0 ... 16)
			spacingStepper(TranscriptThemeStrings.messageSpacing, value: messageSpacing, in: 0 ... 32)
			spacingStepper(TranscriptThemeStrings.horizontalPadding, value: horizontalPadding, in: 0 ... 48)
		} header: {
			Text(verbatim: PreferencesStyleStrings.headingLayout)
		}

		Section {
			PreferencesToggle(
				title: PreferencesStyleStrings.autoScrollbackMarker,
				isOn: model.preferences.binding(for: Preferences.Messages.autoAddScrollbackMark)
			)
			PreferencesToggle(
				title: PreferencesStyleStrings.showDateChanges,
				isOn: model.preferences.binding(for: Preferences.Messages.showDateChanges)
			)
			PreferencesToggle(
				title: PreferencesStyleStrings.showJoinLeave,
				isOn: model.preferences.binding(for: Preferences.Messages.showJoinLeave)
			)
			PreferencesToggle(
				title: TranscriptThemeStrings.showInlineImages,
				isOn: model.preferences.binding(for: Preferences.Messages.showInlineMedia)
			)
			PreferencesToggle(
				title: PreferencesStyleStrings.disableNicknameColors,
				isOn: model.preferences.binding(for: Preferences.Messages.disableNicknameColorHashing)
			)
			PreferencesToggle(
				title: PreferencesStyleStrings.showMotd,
				isOn: model.preferences.binding(for: Preferences.Connection.displayServerMOTD)
			)
		} header: {
			Text(verbatim: PreferencesSectionStrings.general)
		}

		Section {
			LabeledContent {
				PreferencesComboField(
					title: PreferencesStyleStrings.scrollbackSaveLimit,
					presets: Self.scrollbackPresets,
					value: model.preferences.numberField(
						for: Preferences.Logging.scrollbackSaveLimit
					) { TextualPreferences.performReloadAction(.scrollbackSaveLimit) },
					rejectionMessage: PreferencesFieldStrings.wholeNumberRequired
				)
			} label: {
				Text(verbatim: PreferencesStyleStrings.scrollbackSaveLimit)
			}
		} header: {
			Text(verbatim: PreferencesStyleStrings.headingScrollback)
		} footer: {
			PreferencesNote(PreferencesStyleStrings.scrollbackSaveLimitNote)
		}
	}

	/// The light and dark wells of every colour role, in a grid so that the
	/// two columns line up and carry real headings.
	private var colorGrid: some View {
		Grid(
			alignment: .leading,
			horizontalSpacing: PreferencesMetrics.spacingLarge,
			verticalSpacing: PreferencesMetrics.spacingMedium
		) {
			GridRow {
				Color.clear.frame(width: 0, height: 0)
				columnHeader(TranscriptThemeStrings.light)
				columnHeader(TranscriptThemeStrings.dark)
			}
			.accessibilityHidden(true)

			ForEach(TranscriptThemeColorRole.all) { role in
				GridRow {
					Text(verbatim: role.title)
						.gridColumnAlignment(.leading)
					colorWell(role, dark: false)
					colorWell(role, dark: true)
				}
			}
		}
		.frame(maxWidth: .infinity, alignment: .leading)
	}

	private func columnHeader(_ title: String) -> some View {
		Text(verbatim: title)
			.font(.caption)
			.foregroundStyle(.secondary)
	}

	private func colorWell(_ role: TranscriptThemeColorRole, dark: Bool) -> some View {
		let appearance = dark ? TranscriptThemeStrings.dark : TranscriptThemeStrings.light
		return ColorPicker(appearance, selection: color(role, dark: dark), supportsOpacity: true)
			.labelsHidden()
			.accessibilityLabel(Text(verbatim: PreferencesStyleStrings.colorAccessibility(
				role: role.title,
				appearance: appearance
			)))
	}

	private var fontRow: some View {
		LabeledContent {
			HStack {
				Text(verbatim: PreferencesStyleStrings.fontDescription(
					name: model.transcriptTheme.fontName,
					size: Double(model.transcriptTheme.fontSize)
						.formatted(.number.precision(.fractionLength(0 ... 1)))
				))
				Spacer()
				Button(PreferencesStyleStrings.fontChange) { model.selectChannelViewFont() }
			}
		} label: {
			Text(verbatim: PreferencesStyleStrings.fontLabel)
		}
	}

	private func spacingStepper(
		_ label: String,
		value: Binding<Double>,
		in range: ClosedRange<Double>
	) -> some View {
		LabeledContent {
			Stepper(value: value, in: range) {
				Text(verbatim: value.wrappedValue.formatted())
			}
			.accessibilityLabel(Text(verbatim: label))
		} label: {
			Text(verbatim: label)
		}
	}

	@ViewBuilder
	private var formatFields: some View {
		LabeledContent {
			PreferencesComboField(
				title: PreferencesStyleStrings.nicknameFormatLabel,
				presets: Self.nicknamePresets,
				value: themeText(\.nicknameFormat)
			)
		} label: {
			Text(verbatim: PreferencesStyleStrings.nicknameFormatLabel)
			Text(verbatim: "\(PreferencesStyleStrings.formatSymbolsLabel) %@ = "
				+ "\(PreferencesStyleStrings.nicknameFormatSymbolMode); "
				+ "%n = \(PreferencesStyleStrings.nicknameFormatSymbolNickname)")
		}

		LabeledContent {
			PreferencesComboField(
				title: PreferencesStyleStrings.timestampFormatLabel,
				presets: Self.timestampPresets,
				value: themeText(\.timestampFormat)
			)
		} label: {
			Text(verbatim: PreferencesStyleStrings.timestampFormatLabel)
			Text(verbatim: PreferencesStyleStrings.timestampFormatNote)
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
	private var themeName: PreferencesFieldValue {
		PreferencesFieldValue(
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
	private func themeText(_ keyPath: WritableKeyPath<TranscriptTheme, String>) -> PreferencesFieldValue {
		PreferencesFieldValue(
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
