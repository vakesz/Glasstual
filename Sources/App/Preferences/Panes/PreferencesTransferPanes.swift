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

	private var usesManualAddress: Bool {
		model.preferences[Preferences.FileTransfers.ipAddressDetectionMethod] == .manual
	}

	var body: some View {
		PreferencesPaneLayout {
			Section {
				replyActionPicker
			}

			Section {
				detectionPicker
				manualAddressField
				portRange
			}

			Section {
				PreferencesFolderPicker(
					label: PreferencesFileTransfersStrings.destinationLabel,
					accessibilityLabel: PreferencesStrings.downloadDestinationAccessibilityLabel,
					folder: model.downloadFolder,
					emptyTitle: PreferencesStrings.noDownloadDestination,
					select: { model.actions?.selectDownloadFolder() },
					clear: { model.actions?.clearDownloadFolder() }
				)
				PreferencesNote(PreferencesFileTransfersStrings.destinationNote)
			}

			Section {
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

struct PreferencesInlineMediaPane: View {
	/** The tags the nib's popup carried, in the order it listed them. */
	private static let fileSizeChoices: [(tag: UInt, megabytes: Int)] = [
		(1, 1), (2, 2), (3, 3), (4, 4), (5, 5), (6, 10), (7, 15), (8, 20), (9, 50), (10, 100),
	]

	let model: PreferencesPaneModel

	private var limitsToBasics: Bool {
		model.preferences[Preferences.InlineMedia.limitToBasics]
	}

	var body: some View {
		PreferencesPaneLayout {
			Section {
				VStack(alignment: .leading, spacing: 4) {
					PreferencesToggle(title: PreferencesInlineMediaStrings.show, isOn: showsInlineMedia)
						.disabled(model.isReloadingTheme)
					PreferencesNote(PreferencesInlineMediaStrings.showNote)
				}
			} header: {
				Text(verbatim: PreferencesSectionStrings.general)
			}

			Section {
				fileSizePicker
				heightField
				widthField
				checkEverything
			} header: {
				Text(verbatim: PreferencesInlineMediaStrings.headingImages)
			}

			Section {
				limitations
			} header: {
				Text(verbatim: PreferencesInlineMediaStrings.headingLimitations)
			}
		}
	}

	private var showsInlineMedia: Binding<Bool> {
		Binding(
			get: { model.preferences[Preferences.Messages.showInlineMedia] },
			set: { model.actions?.setInlineMediaEnabled($0) }
		)
	}

	private var fileSizePicker: some View {
		Picker(selection: model.preferences.binding(for: Preferences.InlineMedia.maximumFilesize)) {
			ForEach(Self.fileSizeChoices, id: \.tag) { choice in
				Text(verbatim: choice.megabytes == 1
					? PreferencesInlineMediaStrings.oneMegabyte
					: PreferencesInlineMediaStrings.megabytes(count: choice.megabytes))
					.tag(choice.tag)
			}
		} label: {
			Text(verbatim: PreferencesInlineMediaStrings.filesizeLabel)
		}
		.accessibilityLabel(Text(verbatim: PreferencesInlineMediaStrings.filesizeAccessibility))
	}

	private var heightField: some View {
		VStack(alignment: .leading, spacing: 4) {
			LabeledContent {
				HStack(spacing: 6) {
					TextField("", text: model.preferences.numberFieldBinding(
						for: Preferences.InlineMedia.maximumHeight,
						range: PreferencesValueValidation.inlineMediaHeightRange,
						allowingZero: true
					))
					.labelsHidden()
					.frame(width: 80)
					.accessibilityLabel(Text(verbatim: PreferencesInlineMediaStrings.heightAccessibility))
					Text(verbatim: PreferencesInlineMediaStrings.pixels)
					Spacer()
				}
			} label: {
				Text(verbatim: PreferencesInlineMediaStrings.heightLabel)
			}
			PreferencesNote(PreferencesInlineMediaStrings.heightNote)
		}
	}

	private var widthField: some View {
		LabeledContent {
			HStack(spacing: 6) {
				TextField("", text: model.preferences.numberFieldBinding(
					for: Preferences.InlineMedia.scalingWidth,
					range: PreferencesValueValidation.inlineMediaWidthRange
				))
				.labelsHidden()
				.frame(width: 80)
				.accessibilityLabel(Text(verbatim: PreferencesInlineMediaStrings.widthAccessibility))
				Text(verbatim: PreferencesInlineMediaStrings.pixelsWide)
				Spacer()
			}
		} label: {
			Text(verbatim: PreferencesInlineMediaStrings.widthLabel)
		}
	}

	private var checkEverything: some View {
		VStack(alignment: .leading, spacing: 4) {
			PreferencesToggle(
				title: PreferencesInlineMediaStrings.checkEverything,
				isOn: model.preferences.binding(for: Preferences.InlineMedia.checkEverything)
			)
			.accessibilityLabel(
				Text(verbatim: PreferencesInlineMediaStrings.checkEverythingAccessibility)
			)
			PreferencesNote(PreferencesInlineMediaStrings.checkEverythingNote)
		}
	}

	private var limitations: some View {
		VStack(alignment: .leading, spacing: 10) {
			VStack(alignment: .leading, spacing: 6) {
				PreferencesToggle(
					title: PreferencesInlineMediaStrings.limitToBasics,
					isOn: model.preferences.binding(for: Preferences.InlineMedia.limitToBasics)
				)
				PreferencesToggle(
					title: PreferencesInlineMediaStrings.limitBasicsToFiles,
					isOn: model.preferences.gatedBinding(
						for: Preferences.InlineMedia.limitBasicsToFiles,
						enabledWhen: { limitsToBasics }
					)
				)
				.disabled(limitsToBasics == false)
				.padding(.leading, 16)
			}
			VStack(alignment: .leading, spacing: 4) {
				PreferencesToggle(
					title: PreferencesInlineMediaStrings.limitNaughty,
					isOn: model.preferences.binding(for: Preferences.InlineMedia.limitNaughtyContent)
				)
				PreferencesNote(PreferencesInlineMediaStrings.limitNaughtyNote)
			}
			VStack(alignment: .leading, spacing: 4) {
				PreferencesToggle(
					title: PreferencesInlineMediaStrings.limitUnsafe,
					isOn: model.preferences.binding(for: Preferences.InlineMedia.limitUnsafeContent)
				)
				PreferencesNote(PreferencesInlineMediaStrings.limitUnsafeNote)
			}
		}
	}
}

struct PreferencesLogLocationPane: View {
	let model: PreferencesPaneModel

	private var logsToDisk: Bool {
		model.preferences[Preferences.Logging.logToDisk]
	}

	var body: some View {
		PreferencesPaneLayout {
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
			}
		}
	}
}

struct PreferencesHiddenPane: View {
	private static let scrollbackPresets = [
		"100", "500", "1000", "1500", "2000", "2500", "3000", "3500", "4000", "4500", "5000",
	]

	let model: PreferencesPaneModel

	var body: some View {
		PreferencesPaneLayout {
			Section {
				HStack(alignment: .firstTextBaseline, spacing: 4) {
					Text(verbatim: PreferencesHiddenStrings.warningLabel)
						.bold()
					Text(verbatim: PreferencesHiddenStrings.warning)
					Spacer()
				}
			}

			Section {
				PreferencesToggle(
					title: PreferencesHiddenStrings.appNap,
					isOn: model.preferences.invertedBinding(for: Preferences.Internals.appSleepDisabled)
				)
				PreferencesToggle(
					title: PreferencesHiddenStrings.webkitProcessPool,
					isOn: model.preferences.binding(for: Preferences.Appearance.webViewProcessPoolLimited)
				)
				PreferencesToggle(
					title: PreferencesHiddenStrings.webkitPreviewLinks,
					isOn: model.preferences.binding(for: Preferences.Appearance.webViewPreviewLinks)
				)
				PreferencesToggle(
					title: PreferencesHiddenStrings.customScrollbars,
					isOn: model.preferences.invertedBinding(
						for: Preferences.Appearance.webViewCustomScrollersDisabled
					)
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
			}

			Section {
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

			Section {
				PreferencesNote(PreferencesHiddenStrings.restartNote)
			}
		}
	}
}
