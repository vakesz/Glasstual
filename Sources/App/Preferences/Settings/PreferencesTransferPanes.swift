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
				select: { model.selectDownloadFolder() },
				clear: { model.clearDownloadFolder() }
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
		}
	}

	private var replyActionPicker: some View {
		Picker(selection: model.preferences.binding(for: Preferences.FileTransfers.requestReplyAction)) {
			Text(verbatim: PreferencesFileTransfersStrings.replyIgnore)
				.tag(FileTransferRequestBehavior.ignore)
			Text(verbatim: PreferencesFileTransfersStrings.replyOpenDialog)
				.tag(FileTransferRequestBehavior.openDialog)
			Text(verbatim: PreferencesFileTransfersStrings.replyDownload)
				.tag(FileTransferRequestBehavior.automaticallyDownload)
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
				.tag(FileTransferIPAddressSource.routerOnly)
			Text(verbatim: PreferencesFileTransfersStrings.detectionRouterFirstParty)
				.tag(FileTransferIPAddressSource.routerAndFirstParty)
			Text(verbatim: PreferencesFileTransfersStrings.detectionRouterThirdParty)
				.tag(FileTransferIPAddressSource.routerAndThirdParty)
			Text(verbatim: PreferencesFileTransfersStrings.detectionManual)
				.tag(FileTransferIPAddressSource.manual)
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
				PreferencesCommittedField(
					title: PreferencesFileTransfersStrings.portRangeFirst,
					value: model.preferences.portField(
						for: Preferences.FileTransfers.portRangeStart,
						limitedBy: Preferences.FileTransfers.portRangeEnd
					),
					rejectionMessage: PreferencesFieldStrings.wholeNumberRequired
				)
				.frame(width: 80)
				Text(verbatim: PreferencesFileTransfersStrings.portRangeSeparator)
				PreferencesCommittedField(
					title: PreferencesFileTransfersStrings.portRangeLast,
					value: model.preferences.portField(
						for: Preferences.FileTransfers.portRangeEnd,
						limitedBy: Preferences.FileTransfers.portRangeStart
					),
					rejectionMessage: PreferencesFieldStrings.wholeNumberRequired
				)
				.frame(width: 80)
				Spacer()
			}
		} label: {
			Text(verbatim: PreferencesFileTransfersStrings.portRangeLabel)
		}
	}
}

/// A folder picker: the chosen folder with its icon, plus the two commands
/// that change it.
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

struct PreferencesLogLocationSections: View {
	let model: PreferencesPaneModel

	private var logsToDisk: Bool {
		model.preferences[Preferences.Logging.logToDisk]
	}

	var body: some View {
		Section {
			PreferencesToggle(
				title: PreferencesLogLocationStrings.logToDisk,
				isOn: model.preferences.binding(for: Preferences.Logging.logToDisk)
			)
			PreferencesFolderPicker(
				label: PreferencesLogLocationStrings.folderLabel,
				accessibilityLabel: PreferencesStrings.transcriptFolderAccessibilityLabel,
				folder: model.transcriptFolder,
				emptyTitle: PreferencesStrings.noTranscriptFolder,
				select: { model.selectTranscriptFolder() },
				clear: { model.clearTranscriptFolder() }
			)
			.disabled(logsToDisk == false)
		} header: {
			Text(verbatim: PreferencesPane.logLocation.title)
		}
	}
}

struct PreferencesHiddenSections: View {
	private static let scrollbackPresets = [
		"100", "500", "1000", "1500", "2000", "2500", "3000", "3500", "4000", "4500", "5000",
	]

	let model: PreferencesPaneModel

	var body: some View {
		Section {
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
		} header: {
			Text(verbatim: PreferencesPane.hidden.title)
		} footer: {
			VStack(alignment: .leading, spacing: PreferencesMetrics.spacingSmall) {
				PreferencesNote(PreferencesHiddenStrings.warning)
				PreferencesNote(PreferencesHiddenStrings.restartNote)
			}
		}
	}

	private var scrollbackLimitRow: some View {
		LabeledContent {
			PreferencesComboField(
				title: PreferencesHiddenStrings.scrollbackVisibleLimit,
				presets: Self.scrollbackPresets,
				value: model.preferences.numberField(
					for: Preferences.Logging.scrollbackVisibleLimit
				) {
					TextualPreferences.performReloadAction(.scrollbackVisibleLimit)
				},
				rejectionMessage: PreferencesFieldStrings.wholeNumberRequired
			)
		} label: {
			Text(verbatim: PreferencesHiddenStrings.scrollbackVisibleLimit)
			Text(verbatim: PreferencesHiddenStrings.scrollbackVisibleLimitNote)
		}
	}
}
