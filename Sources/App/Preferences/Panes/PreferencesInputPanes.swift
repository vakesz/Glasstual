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

import SwiftUI

struct PreferencesControlsPane: View {
	let model: PreferencesPaneModel

	var body: some View {
		PreferencesPaneLayout {
			Section {
				PreferencesToggle(
					title: PreferencesControlsStrings.navigationServerSpecific,
					isOn: model.preferences.binding(
						for: Preferences.Appearance.channelNavigationIsServerSpecific
					)
				)
				doubleClickPicker
				commandWPicker
				doubleClickToggles
				VStack(alignment: .leading, spacing: 4) {
					PreferencesToggle(
						title: PreferencesControlsStrings.copyOnSelect,
						isOn: model.preferences.binding(for: Preferences.Messages.copyOnSelect)
					)
					PreferencesNote(PreferencesControlsStrings.copyOnSelectNote)
				}
			} header: {
				Text(verbatim: PreferencesControlsStrings.headingKeyboardMouse)
			}

			Section {
				spellingToggles
				sendingToggles
				textSizePicker
				tabKeyPicker
				completionSuffixRow
			} header: {
				Text(verbatim: PreferencesControlsStrings.headingTextField)
			}
		}
	}

	private var doubleClickPicker: some View {
		Picker(selection: model.preferences.binding(for: Preferences.Input.userDoubleClickAction)) {
			Text(verbatim: PreferencesControlsStrings.userDoubleClickQuery)
				.tag(TXUserDoubleClickAction.privateMessage)
			Text(verbatim: PreferencesControlsStrings.userDoubleClickWhois)
				.tag(TXUserDoubleClickAction.whois)
			Text(verbatim: PreferencesControlsStrings.userDoubleClickInsert)
				.tag(TXUserDoubleClickAction.insertTextField)
		} label: {
			Text(verbatim: PreferencesControlsStrings.userDoubleClickLabel)
		}
	}

	private var commandWPicker: some View {
		Picker(selection: model.preferences.binding(for: Preferences.Input.commandWKeyAction)) {
			Text(verbatim: PreferencesControlsStrings.commandWCloseWindow)
				.tag(TXCommandWKeyAction.closeWindow)
			Text(verbatim: PreferencesControlsStrings.commandWPartChannel)
				.tag(TXCommandWKeyAction.partChannel)
			Text(verbatim: PreferencesControlsStrings.commandWDisconnect)
				.tag(TXCommandWKeyAction.disconnect)
			Text(verbatim: PreferencesControlsStrings.commandWTerminate)
				.tag(TXCommandWKeyAction.terminate)
		} label: {
			Text(verbatim: PreferencesControlsStrings.commandWLabel)
		}
	}

	private var doubleClickToggles: some View {
		VStack(alignment: .leading, spacing: 6) {
			PreferencesToggle(
				title: PreferencesControlsStrings.connectOnDoubleClick,
				isOn: model.preferences.binding(for: Preferences.Appearance.connectOnDoubleClick)
			)
			PreferencesToggle(
				title: PreferencesControlsStrings.disconnectOnDoubleClick,
				isOn: model.preferences.binding(for: Preferences.Appearance.disconnectOnDoubleClick)
			)
			PreferencesToggle(
				title: PreferencesControlsStrings.joinOnDoubleClick,
				isOn: model.preferences.binding(for: Preferences.Appearance.joinOnDoubleClick)
			)
			PreferencesToggle(
				title: PreferencesControlsStrings.leaveOnDoubleClick,
				isOn: model.preferences.binding(for: Preferences.Appearance.leaveOnDoubleClick)
			)
		}
	}

	private var spellingToggles: some View {
		VStack(alignment: .leading, spacing: 6) {
			PreferencesToggle(
				title: PreferencesControlsStrings.spellCheck,
				isOn: model.preferences.binding(for: Preferences.Input.automaticSpellCheck)
			)
			PreferencesToggle(
				title: PreferencesControlsStrings.grammarCheck,
				isOn: model.preferences.binding(for: Preferences.Input.automaticGrammarCheck)
			)
			PreferencesToggle(
				title: PreferencesControlsStrings.spellCorrection,
				isOn: model.preferences.binding(for: Preferences.Input.automaticSpellCorrection)
			)
		}
	}

	private var sendingToggles: some View {
		VStack(alignment: .leading, spacing: 6) {
			PreferencesToggle(
				title: PreferencesControlsStrings.historyPerSelection,
				isOn: model.preferences.binding(for: Preferences.Input.historyIsChannelSpecific) { _ in
					TextualPreferences.performReloadAction(.inputHistoryScope)
				}
			)
			PreferencesToggle(
				title: PreferencesControlsStrings.commandReturnAction,
				isOn: model.preferences.binding(for: Preferences.Input.commandReturnSendsAction) { _ in
					TextualPreferences.performReloadAction(.inputHistoryScope)
				}
			)
			PreferencesToggle(
				title: PreferencesControlsStrings.controlEnterSends,
				isOn: model.preferences.binding(for: Preferences.Input.controlEnterSendsMessage) { _ in
					TextualPreferences.performReloadAction(.inputHistoryScope)
				}
			)
		}
	}

	private var textSizePicker: some View {
		Picker(selection: model.preferences.binding(for: Preferences.Input.textViewFontSize) { _ in
			TextualPreferences.performReloadAction(.textFieldFontSize)
		}) {
			Text(verbatim: PreferencesControlsStrings.textSizeNormal)
				.tag(TVCMainWindowTextViewFontSize.normal)
			Text(verbatim: PreferencesControlsStrings.textSizeLarge)
				.tag(TVCMainWindowTextViewFontSize.large)
			Text(verbatim: PreferencesControlsStrings.textSizeExtraLarge)
				.tag(TVCMainWindowTextViewFontSize.extraLarge)
			Text(verbatim: PreferencesControlsStrings.textSizeHumongous)
				.tag(TVCMainWindowTextViewFontSize.humongous)
		} label: {
			Text(verbatim: PreferencesControlsStrings.textSizeLabel)
		}
	}

	private var tabKeyPicker: some View {
		Picker(selection: model.preferences.binding(for: Preferences.Input.tabKeyAction)) {
			Text(verbatim: PreferencesControlsStrings.tabKeyNone)
				.tag(TXTabKeyAction.none)
			Text(verbatim: PreferencesControlsStrings.tabKeyUnread)
				.tag(TXTabKeyAction.unreadChannel)
			Text(verbatim: PreferencesControlsStrings.tabKeyComplete)
				.tag(TXTabKeyAction.nicknameComplete)
		} label: {
			Text(verbatim: PreferencesControlsStrings.tabKeyLabel)
		}
	}

	private var completionSuffixRow: some View {
		LabeledContent {
			HStack(spacing: 8) {
				TextField(
					"",
					text: model.preferences.binding(for: Preferences.Input.tabCompletionSuffix)
				)
				.labelsHidden()
				.accessibilityLabel(
					Text(verbatim: PreferencesControlsStrings.completionSuffixAccessibility)
				)
				Divider()
				Text(verbatim: PreferencesControlsStrings.completionPreviewLabel)
					.bold()
				Text(verbatim: PreferencesControlsStrings.completionPreview(
					suffix: model.preferences[Preferences.Input.tabCompletionSuffix]
				))
				.foregroundStyle(.secondary)
			}
		} label: {
			Text(verbatim: PreferencesControlsStrings.completionSuffixLabel)
		}
	}
}

struct PreferencesAddOnsPane: View {
	private static let listHeight = 200.0

	let model: PreferencesPaneModel

	var body: some View {
		PreferencesPaneLayout {
			Section {
				VStack(alignment: .leading, spacing: 6) {
					Text(verbatim: PreferencesAddOnsStrings.commandsLabel)
					List(model.addOnCommands, id: \.self) { command in
						Text(verbatim: command)
					}
					.frame(height: Self.listHeight)
					.accessibilityLabel(Text(verbatim: PreferencesAddOnsStrings.commandsList))
					PreferencesNote(PreferencesAddOnsStrings.commandsNote)
				}
			}

			Section {
				VStack(alignment: .leading, spacing: 6) {
					HStack {
						Text(verbatim: PreferencesAddOnsStrings.locationLabel)
							.bold()
						Spacer()
						Button {
							model.actions?.openCustomAddOnsFolder()
						} label: {
							Text(verbatim: PreferencesAddOnsStrings.openInFinder)
						}
						.accessibilityLabel(Text(verbatim: PreferencesAddOnsStrings.openInFinderHelp))
					}
					PreferencesNote(model.scriptInstallationInstructions)
				}
			}
		}
	}
}

struct PreferencesDefaultIdentityPane: View {
	let model: PreferencesPaneModel

	var body: some View {
		PreferencesPaneLayout {
			PreferencesDefaultIdentitySections(model: model)
		}
	}
}

/// The pane as one form section, for the Advanced group that gathers it with
/// its neighbours.
struct PreferencesDefaultIdentitySections: View {
	let model: PreferencesPaneModel

	var body: some View {
		Section {
			PreferencesNote(PreferencesDefaultIdentityStrings.note)
			field(
				label: PreferencesDefaultIdentityStrings.nickname,
				key: Preferences.Identity.nickname
			)
			field(
				label: PreferencesDefaultIdentityStrings.awayNickname,
				key: Preferences.Identity.awayNickname
			)
			field(
				label: PreferencesDefaultIdentityStrings.username,
				key: Preferences.Identity.username
			)
			field(
				label: PreferencesDefaultIdentityStrings.realname,
				key: Preferences.Identity.realName
			)
			PreferencesNote(PreferencesDefaultIdentityStrings.allOptional)
		} header: {
			Text(verbatim: PreferencesStrings.paneTitle(.defaultIdentity))
		}
	}

	private func field(label: String, key: PreferenceKey<String>) -> some View {
		TextField(
			text: model.preferences.binding(for: key),
			prompt: Text(verbatim: PreferencesDefaultIdentityStrings.optional)
		) {
			Text(verbatim: label)
		}
		.accessibilityLabel(Text(verbatim: label))
	}
}

struct PreferencesIRCopMessagesPane: View {
	let model: PreferencesPaneModel

	var body: some View {
		PreferencesPaneLayout {
			PreferencesIRCopMessagesSections(model: model)
		}
	}
}

/// The pane as one form section, for the Advanced group that gathers it with
/// its neighbours.
struct PreferencesIRCopMessagesSections: View {
	let model: PreferencesPaneModel

	var body: some View {
		Section {
			field(
				label: PreferencesIRCopStrings.killLabel,
				note: nil,
				key: Preferences.Commands.irCopKillMessage
			)
			field(
				label: PreferencesIRCopStrings.glineLabel,
				note: PreferencesIRCopStrings.includesBanLength,
				key: Preferences.Commands.irCopGlineMessage
			)
			field(
				label: PreferencesIRCopStrings.shunLabel,
				note: PreferencesIRCopStrings.includesBanLength,
				key: Preferences.Commands.irCopShunMessage
			)
		} header: {
			Text(verbatim: PreferencesStrings.paneTitle(.defaultIRCopMessages))
		}
	}

	private func field(label: String, note: String?, key: PreferenceKey<String>) -> some View {
		VStack(alignment: .leading, spacing: 6) {
			HStack(spacing: 6) {
				Text(verbatim: label)
				if let note {
					Text(verbatim: note)
						.font(.callout)
						.foregroundStyle(.secondary)
				}
			}
			TextField("", text: model.preferences.binding(for: key))
				.labelsHidden()
				.accessibilityLabel(Text(verbatim: label))
		}
	}
}
