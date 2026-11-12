// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import SwiftUI

/// The File Transfers row: what happens when a file is offered, the address
/// and ports the other end is given, and where downloads land.
struct FileTransfersPane: View {
	/// Wide enough for five digits at the body size.
	private static let portFieldWidth = 64.0

	let model: SettingsModel
	@State private var showsKnownCertificates = false

	private var usesManualAddress: Bool {
		model.settings[SettingsKeys.FileTransfers.ipAddressDetectionMethod] == .manual
	}

	var body: some View {
		Section {
			replyActionPicker
			SettingsToggle(
				title: .Settings.fileTransfersReverseDcc,
				isOn: model.settings.binding(for: SettingsKeys.FileTransfers.requestsAreReversed)
			)
		} header: {
			Text(.Settings.fileTransfersHeadingRequests)
		}

		Section {
			detectionPicker
			manualAddressField
			portRange
		} header: {
			Text(.Settings.fileTransfersHeadingNetwork)
		}

		Section {
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
			SettingsToggle(
				title: .Settings.fileTransfersPreventSleep,
				isOn: model.settings.binding(for: SettingsKeys.FileTransfers.preventIdleSystemSleep)
			)
		} header: {
			Text(.Settings.fileTransfersHeadingDownloads)
		} footer: {
			Text(.Settings.fileTransfersDestinationNote)
		}

		secureConnections

		Section {
			SettingsToggle(
				title: .Settings.fileTransfersXdccKnownPeers,
				note: .Settings.fileTransfersXdccKnownPeersNote,
				isOn: model.settings.binding(for: SettingsKeys.FileTransfers.xdccRequestsAreKnownPeers)
			)
		} header: {
			Text(.Settings.fileTransfersHeadingXdcc)
		}
	}

	/// Encrypted (TLS) transfers and chats: whether to take them, whether to
	/// offer them, how strict to be about the other side, and the certificates
	/// that are trusted.
	private var secureConnections: some View {
		Section {
			SettingsToggle(
				title: .Settings.fileTransfersAcceptSecureOffers,
				isOn: model.settings.binding(for: SettingsKeys.FileTransfers.acceptsSecureOffers)
			)
			SettingsToggle(
				title: .Settings.fileTransfersOffersAreSecure,
				note: .Settings.fileTransfersOffersAreSecureNote,
				isOn: model.settings.binding(for: SettingsKeys.FileTransfers.offersAreSecure)
			)
			SettingsToggle(
				title: .Settings.fileTransfersRequirePeerCertificate,
				note: .Settings.fileTransfersRequirePeerCertificateNote,
				isOn: model.settings.binding(for: SettingsKeys.FileTransfers.requirePeerCertificate)
			)
			Button(.Settings.fileTransfersKnownCertificatesButton) { showsKnownCertificates = true }
				.frame(maxWidth: .infinity, alignment: .trailing)
				.accessibilityIdentifier("settings-known-certificates")
		} header: {
			Text(.Settings.fileTransfersHeadingSecureConnections)
		}
		.sheet(isPresented: $showsKnownCertificates) {
			DCCKnownCertificatesSheet(model: .application())
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
			HStack(spacing: UISpacing.tight) {
				SettingsCommittedField(
					title: .Settings.fileTransfersPortRangeFirst,
					value: model.settings.portField(
						for: SettingsKeys.FileTransfers.portRangeStart,
						limitedBy: SettingsKeys.FileTransfers.portRangeEnd
					),
					rejectionMessage: .SettingsTransfer.enterAValidWholeNumber
				)
				.monospacedDigit()
				.frame(idealWidth: Self.portFieldWidth)
				.fixedSize()
				Text(.Settings.fileTransfersPortRangeSeparator)
				SettingsCommittedField(
					title: .Settings.fileTransfersPortRangeLast,
					value: model.settings.portField(
						for: SettingsKeys.FileTransfers.portRangeEnd,
						limitedBy: SettingsKeys.FileTransfers.portRangeStart
					),
					rejectionMessage: .SettingsTransfer.enterAValidWholeNumber
				)
				.monospacedDigit()
				.frame(idealWidth: Self.portFieldWidth)
				.fixedSize()
			}
		} label: {
			Text(.Settings.fileTransfersPortRangeLabel)
		}
		.accessibilityElement(children: .contain)
	}
}
