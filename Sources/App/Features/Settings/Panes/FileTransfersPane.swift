// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import SwiftUI

/// The File Transfers row: what happens when a file is offered, the address
/// and ports the other end is given, and where downloads land.
struct FileTransfersPane: View {
	let model: SettingsModel

	private var usesManualAddress: Bool {
		model.settings[SettingsKeys.FileTransfers.ipAddressDetectionMethod] == .manual
	}

	var body: some View {
		Section {
			replyActionPicker
			detectionPicker
			manualAddressField
			portRange
			SettingsFolderPicker(
				label: .Settings.fileTransfersDestinationLabel,
				accessibilityLabel: .Settings.downloadDestination,
				folder: model.downloadFolder,
				emptyTitle: .Settings.noLocationSelected,
				clearTitle: .Settings.fileTransfersUseDownloads,
				canClear: model.usesCustomDownloadFolder,
				select: { model.selectDownloadFolder() },
				clear: { model.clearDownloadFolder() }
			)
			SettingsNote(.Settings.fileTransfersDestinationNote)
			SettingsToggle(
				title: .Settings.fileTransfersReverseDcc,
				isOn: model.settings.binding(for: SettingsKeys.FileTransfers.requestsAreReversed)
			)
			SettingsToggle(
				title: .Settings.fileTransfersPreventSleep,
				isOn: model.settings.binding(for: SettingsKeys.FileTransfers.preventIdleSystemSleep)
			)
		}
	}

	private var replyActionPicker: some View {
		Picker(selection: model.settings.binding(for: SettingsKeys.FileTransfers.requestReplyAction)) {
			Text(.Settings.fileTransfersReplyIgnore)
				.tag(FileTransferRequestBehavior.ignore)
			Text(.Settings.fileTransfersReplyOpenDialog)
				.tag(FileTransferRequestBehavior.openDialog)
			Text(.Settings.fileTransfersReplyDownload)
				.tag(FileTransferRequestBehavior.automaticallyDownload)
		} label: {
			Text(.Settings.fileTransfersReplyActionLabel)
		}
		.accessibilityLabel(Text(.Settings.fileTransfersReplyActionAccessibility))
	}

	private var detectionPicker: some View {
		Picker(
			selection: model.settings.binding(for: SettingsKeys.FileTransfers.ipAddressDetectionMethod)
		) {
			Text(.Settings.fileTransfersDetectionRouterOnly)
				.tag(FileTransferIPAddressSource.routerOnly)
			Text(.Settings.fileTransfersDetectionRouterFirstParty)
				.tag(FileTransferIPAddressSource.routerAndFirstParty)
			Text(.Settings.fileTransfersDetectionRouterThirdParty)
				.tag(FileTransferIPAddressSource.routerAndThirdParty)
			Text(.Settings.fileTransfersDetectionManual)
				.tag(FileTransferIPAddressSource.manual)
		} label: {
			Text(.Settings.fileTransfersDetectionLabel)
		}
		.accessibilityLabel(Text(.Settings.fileTransfersDetectionAccessibility))
	}

	private var manualAddressField: some View {
		TextField(
			text: model.settings.binding(for: SettingsKeys.FileTransfers.manuallyEnteredIPAddress),
			prompt: Text(verbatim: "127.0.0.1")
		) {
			Text(.Settings.fileTransfersManualAddressLabel)
		}
		.disabled(usesManualAddress == false)
		.accessibilityLabel(Text(.Settings.fileTransfersManualAddressAccessibility))
	}

	private var portRange: some View {
		LabeledContent {
			HStack(spacing: 6) {
				SettingsCommittedField(
					title: .Settings.fileTransfersPortRangeFirst,
					value: model.settings.portField(
						for: SettingsKeys.FileTransfers.portRangeStart,
						limitedBy: SettingsKeys.FileTransfers.portRangeEnd
					),
					rejectionMessage: .SettingsTransfer.enterAValidWholeNumber
				)
				.frame(width: 80)
				Text(.Settings.fileTransfersPortRangeSeparator)
				SettingsCommittedField(
					title: .Settings.fileTransfersPortRangeLast,
					value: model.settings.portField(
						for: SettingsKeys.FileTransfers.portRangeEnd,
						limitedBy: SettingsKeys.FileTransfers.portRangeStart
					),
					rejectionMessage: .SettingsTransfer.enterAValidWholeNumber
				)
				.frame(width: 80)
				Spacer()
			}
		} label: {
			Text(.Settings.fileTransfersPortRangeLabel)
		}
	}
}
