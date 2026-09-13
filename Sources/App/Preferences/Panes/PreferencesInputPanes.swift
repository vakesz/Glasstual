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

struct PreferencesControlsSections: View {
	let model: PreferencesPaneModel

	var body: some View {
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
			PreferencesToggle(
				title: PreferencesControlsStrings.copyOnSelect,
				note: PreferencesControlsStrings.copyOnSelectNote,
				isOn: model.preferences.binding(for: Preferences.Messages.copyOnSelect)
			)
			PreferencesToggle(
				title: PreferencesControlsStrings.openLinksInBackground,
				isOn: model.preferences.binding(for: Preferences.Messages.openBrowserInBackground)
			)
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

	private var doubleClickPicker: some View {
		Picker(selection: model.preferences.binding(for: Preferences.Input.userDoubleClickAction)) {
			Text(verbatim: PreferencesControlsStrings.userDoubleClickQuery)
				.tag(UserDoubleClickAction.privateMessage)
			Text(verbatim: PreferencesControlsStrings.userDoubleClickWhois)
				.tag(UserDoubleClickAction.whois)
			Text(verbatim: PreferencesControlsStrings.userDoubleClickInsert)
				.tag(UserDoubleClickAction.insertTextField)
		} label: {
			Text(verbatim: PreferencesControlsStrings.userDoubleClickLabel)
		}
	}

	private var commandWPicker: some View {
		Picker(selection: model.preferences.binding(for: Preferences.Input.commandWKeyAction)) {
			Text(verbatim: PreferencesControlsStrings.commandWCloseWindow)
				.tag(CommandWShortcutAction.closeWindow)
			Text(verbatim: PreferencesControlsStrings.commandWPartChannel)
				.tag(CommandWShortcutAction.partChannel)
			Text(verbatim: PreferencesControlsStrings.commandWDisconnect)
				.tag(CommandWShortcutAction.disconnect)
			Text(verbatim: PreferencesControlsStrings.commandWTerminate)
				.tag(CommandWShortcutAction.terminate)
		} label: {
			Text(verbatim: PreferencesControlsStrings.commandWLabel)
		}
	}

	@ViewBuilder
	private var doubleClickToggles: some View {
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

	@ViewBuilder
	private var spellingToggles: some View {
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

	@ViewBuilder
	private var sendingToggles: some View {
		PreferencesToggle(
			title: PreferencesControlsStrings.historyPerSelection,
			isOn: model.preferences.binding(for: Preferences.Input.historyIsChannelSpecific) { _ in
				TextualPreferences.performReloadAction(.inputHistoryScope)
			}
		)
		/* Neither keyboard toggle reloads anything: they are read when a
		 key is pressed. Copying the history-scope reload onto them threw
		 the whole input history away every time one was flipped. */
		PreferencesToggle(
			title: PreferencesControlsStrings.commandReturnAction,
			isOn: model.preferences.binding(for: Preferences.Input.commandReturnSendsAction)
		)
		PreferencesToggle(
			title: PreferencesControlsStrings.controlEnterSends,
			isOn: model.preferences.binding(for: Preferences.Input.controlEnterSendsMessage)
		)
	}

	private var textSizePicker: some View {
		Picker(selection: model.preferences.binding(for: Preferences.Input.textViewFontSize) { _ in
			TextualPreferences.performReloadAction(.textFieldFontSize)
		}) {
			Text(verbatim: PreferencesControlsStrings.textSizeNormal)
				.tag(MainWindowTextFontSize.normal)
			Text(verbatim: PreferencesControlsStrings.textSizeLarge)
				.tag(MainWindowTextFontSize.large)
			Text(verbatim: PreferencesControlsStrings.textSizeExtraLarge)
				.tag(MainWindowTextFontSize.extraLarge)
			Text(verbatim: PreferencesControlsStrings.textSizeHumongous)
				.tag(MainWindowTextFontSize.humongous)
		} label: {
			Text(verbatim: PreferencesControlsStrings.textSizeLabel)
		}
	}

	private var tabKeyPicker: some View {
		Picker(selection: model.preferences.binding(for: Preferences.Input.tabKeyAction)) {
			Text(verbatim: PreferencesControlsStrings.tabKeyNone)
				.tag(TabKeyAction.none)
			Text(verbatim: PreferencesControlsStrings.tabKeyUnread)
				.tag(TabKeyAction.unreadChannel)
			Text(verbatim: PreferencesControlsStrings.tabKeyComplete)
				.tag(TabKeyAction.nicknameComplete)
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

struct PreferencesAddOnsSections: View {
	private static let listHeight = 200.0

	let model: PreferencesPaneModel

	var body: some View {
		Section {
			List(model.addOnCommands, id: \.self) { command in
				Text(verbatim: command)
			}
			.frame(height: Self.listHeight)
			.accessibilityLabel(Text(verbatim: PreferencesAddOnsStrings.commandsList))
		} header: {
			Text(verbatim: PreferencesAddOnsStrings.commandsHeading)
		} footer: {
			PreferencesNote(PreferencesAddOnsStrings.commandsNote)
		}

		Section {
			Button {
				model.openCustomAddOnsFolder()
			} label: {
				Text(verbatim: PreferencesAddOnsStrings.openInFinder)
			}
			.accessibilityLabel(Text(verbatim: PreferencesAddOnsStrings.openInFinderHelp))
		} header: {
			Text(verbatim: PreferencesAddOnsStrings.locationHeading)
		} footer: {
			PreferencesNote(model.addOnInstallationNote)
		}
	}
}

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
			Text(verbatim: PreferencesPane.defaultIdentity.title)
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
			Text(verbatim: PreferencesPane.defaultIRCopMessages.title)
		}
	}

	private func field(label: String, note: String?, key: PreferenceKey<String>) -> some View {
		TextField(text: model.preferences.binding(for: key)) {
			Text(verbatim: label)

			if let note {
				Text(verbatim: note)
			}
		}
		.accessibilityLabel(Text(verbatim: label))
	}
}
