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

struct PreferencesFileTransfersPane: View {
	let model: PreferencesPaneModel

	var body: some View {
		PreferencesPaneLayout {
			PreferencesFileTransfersSections(model: model)
		}
	}
}

/// The pane as one form section, for the Advanced group that gathers it with
/// inline media.
struct PreferencesFileTransfersSections: View {
	let model: PreferencesPaneModel

	private var usesManualAddress: Bool {
		model.preferences[Preferences.FileTransfers.ipAddressDetectionMethod] == .manual
	}

	var body: some View {
		Section {
			replyActionPicker
			detectionPicker
			manualAddressField
			portRange
			PreferencesFolderPicker(
				label: PreferencesFileTransfersStrings.destinationLabel,
				accessibilityLabel: PreferencesStrings.downloadDestinationAccessibilityLabel,
				folder: model.downloadFolder,
				emptyTitle: PreferencesStrings.noDownloadDestination,
				select: { model.actions?.selectDownloadFolder() },
				clear: { model.actions?.clearDownloadFolder() }
			)
			PreferencesNote(PreferencesFileTransfersStrings.destinationNote)
			PreferencesToggle(
				title: PreferencesFileTransfersStrings.reverseDcc,
				isOn: model.preferences.binding(for: Preferences.FileTransfers.requestsAreReversed)
			)
			PreferencesToggle(
				title: PreferencesFileTransfersStrings.preventSleep,
				isOn: model.preferences.binding(for: Preferences.FileTransfers.preventIdleSystemSleep)
			)
		} header: {
			Text(verbatim: PreferencesStrings.paneTitle(.fileTransfers))
		}
	}

	private var replyActionPicker: some View {
		Picker(selection: model.preferences.binding(for: Preferences.FileTransfers.requestReplyAction)) {
			Text(verbatim: PreferencesFileTransfersStrings.replyIgnore)
				.tag(TXFileTransferRequestReply.ignore)
			Text(verbatim: PreferencesFileTransfersStrings.replyOpenDialog)
				.tag(TXFileTransferRequestReply.openDialog)
			Text(verbatim: PreferencesFileTransfersStrings.replyDownload)
				.tag(TXFileTransferRequestReply.automaticallyDownload)
		} label: {
			Text(verbatim: PreferencesFileTransfersStrings.replyActionLabel)
		}
		.accessibilityLabel(Text(verbatim: PreferencesFileTransfersStrings.replyActionAccessibility))
	}

	private var detectionPicker: some View {
		Picker(
			selection: model.preferences.binding(for: Preferences.FileTransfers.ipAddressDetectionMethod)
		) {
			Text(verbatim: PreferencesFileTransfersStrings.detectionRouterOnly)
				.tag(TXFileTransferIPAddressMethodDetection.routerOnly)
			Text(verbatim: PreferencesFileTransfersStrings.detectionRouterFirstParty)
				.tag(TXFileTransferIPAddressMethodDetection.routerAndFirstParty)
			Text(verbatim: PreferencesFileTransfersStrings.detectionRouterThirdParty)
				.tag(TXFileTransferIPAddressMethodDetection.routerAndThirdParty)
			Text(verbatim: PreferencesFileTransfersStrings.detectionManual)
				.tag(TXFileTransferIPAddressMethodDetection.manual)
		} label: {
			Text(verbatim: PreferencesFileTransfersStrings.detectionLabel)
		}
		.accessibilityLabel(Text(verbatim: PreferencesFileTransfersStrings.detectionAccessibility))
	}

	private var manualAddressField: some View {
		TextField(
			text: model.preferences.binding(for: Preferences.FileTransfers.manuallyEnteredIPAddress),
			prompt: Text(verbatim: "127.0.0.1")
		) {
			Text(verbatim: PreferencesFileTransfersStrings.manualAddressLabel)
		}
		.disabled(usesManualAddress == false)
		.accessibilityLabel(Text(verbatim: PreferencesFileTransfersStrings.manualAddressAccessibility))
	}

	private var portRange: some View {
		LabeledContent {
			HStack(spacing: 6) {
				TextField("", text: model.preferences.portFieldBinding(
					for: Preferences.FileTransfers.portRangeStart,
					limitedBy: Preferences.FileTransfers.portRangeEnd,
					isLowerBound: true
				))
				.labelsHidden()
				.frame(width: 80)
				.accessibilityLabel(Text(verbatim: PreferencesFileTransfersStrings.portRangeFirst))
				Text(verbatim: PreferencesFileTransfersStrings.portRangeSeparator)
				TextField("", text: model.preferences.portFieldBinding(
					for: Preferences.FileTransfers.portRangeEnd,
					limitedBy: Preferences.FileTransfers.portRangeStart,
					isLowerBound: false
				))
				.labelsHidden()
				.frame(width: 80)
				.accessibilityLabel(Text(verbatim: PreferencesFileTransfersStrings.portRangeLast))
				Spacer()
			}
		} label: {
			Text(verbatim: PreferencesFileTransfersStrings.portRangeLabel)
		}
	}
}

/// The nib's folder popups: the chosen folder with its icon, plus the two
/// commands that change it.
struct PreferencesFolderPicker: View {
	let label: String
	let accessibilityLabel: String
	let folder: URL?
	let emptyTitle: String
	let select: () -> Void
	let clear: () -> Void

	var body: some View {
		LabeledContent {
			Menu {
				Button(action: select) {
					Text(verbatim: PreferencesLogLocationStrings.selectDestination)
				}
				Button(action: clear) {
					Text(verbatim: PreferencesLogLocationStrings.clearDestination)
				}
				.disabled(folder == nil)
			} label: {
				HStack(spacing: 4) {
					if let folder {
						Image(nsImage: NSWorkspace.shared.icon(forFile: folder.path))
							.resizable()
							.frame(width: 16, height: 16)
						Text(verbatim: folder.lastPathComponent)
					} else {
						Text(verbatim: emptyTitle)
					}
				}
			}
			.accessibilityLabel(Text(verbatim: accessibilityLabel))
		} label: {
			Text(verbatim: label)
		}
	}
}

struct PreferencesLogLocationPane: View {
	let model: PreferencesPaneModel

	var body: some View {
		PreferencesPaneLayout {
			PreferencesLogLocationSections(model: model)
		}
	}
}

/// The pane as one form section, for the Advanced group that gathers it with
/// the hidden preferences.
struct PreferencesLogLocationSections: View {
	let model: PreferencesPaneModel

	private var logsToDisk: Bool {
		model.preferences[Preferences.Logging.logToDisk]
	}

	var body: some View {
		Section {
			PreferencesToggle(
				title: PreferencesLogLocationStrings.label,
				isOn: model.preferences.binding(for: Preferences.Logging.logToDisk)
			)
			PreferencesFolderPicker(
				label: PreferencesLogLocationStrings.label,
				accessibilityLabel: PreferencesStrings.transcriptFolderAccessibilityLabel,
				folder: model.transcriptFolder,
				emptyTitle: PreferencesStrings.noTranscriptFolder,
				select: { model.actions?.selectTranscriptFolder() },
				clear: { model.actions?.clearTranscriptFolder() }
			)
			.labelsHidden()
			.disabled(logsToDisk == false)
		} header: {
			Text(verbatim: PreferencesStrings.paneTitle(.logLocation))
		}
	}
}

struct PreferencesHiddenPane: View {
	let model: PreferencesPaneModel

	var body: some View {
		PreferencesPaneLayout {
			PreferencesHiddenSections(model: model)
		}
	}
}

/// The pane as one form section, for the Advanced group that gathers it with
/// the log location.
struct PreferencesHiddenSections: View {
	private static let scrollbackPresets = [
		"100", "500", "1000", "1500", "2000", "2500", "3000", "3500", "4000", "4500", "5000",
	]

	let model: PreferencesPaneModel

	var body: some View {
		Section {
			HStack(alignment: .firstTextBaseline, spacing: 4) {
				Text(verbatim: PreferencesHiddenStrings.warningLabel)
					.bold()
				Text(verbatim: PreferencesHiddenStrings.warning)
				Spacer()
			}
			PreferencesToggle(
				title: PreferencesHiddenStrings.appNap,
				isOn: model.preferences.invertedBinding(for: Preferences.Internals.appSleepDisabled)
			)
			PreferencesToggle(
				title: PreferencesHiddenStrings.loadHistoryLazily,
				isOn: model.preferences.binding(for: Preferences.Logging.loadHistoryLazily)
			)
			PreferencesToggle(
				title: PreferencesHiddenStrings.sidebarTranslucency,
				isOn: model.preferences.invertedBinding(
					for: Preferences.Appearance.disableSidebarTranslucency
				)
			)
			scrollbackLimitRow
			PreferencesNote(PreferencesHiddenStrings.restartNote)
		} header: {
			Text(verbatim: PreferencesStrings.paneTitle(.hidden))
		}
	}

	private var scrollbackLimitRow: some View {
		LabeledContent {
			HStack(spacing: 6) {
				PreferencesComboField(
					title: PreferencesHiddenStrings.scrollbackVisibleLimit,
					presets: Self.scrollbackPresets,
					text: model.preferences.numberFieldBinding(
						for: Preferences.Logging.scrollbackVisibleLimit,
						range: PreferencesValueValidation.scrollbackVisibleRange,
						allowingZero: true
					) {
						TextualPreferences.performReloadAction(.scrollbackVisibleLimit)
					}
				)
				Text(verbatim: PreferencesHiddenStrings.scrollbackVisibleLimitNote)
					.font(.callout)
					.foregroundStyle(.secondary)
			}
		} label: {
			Text(verbatim: PreferencesHiddenStrings.scrollbackVisibleLimit)
		}
	}
}
