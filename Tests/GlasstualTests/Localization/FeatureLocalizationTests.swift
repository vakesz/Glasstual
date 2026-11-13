// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

/// Check semantic selection in the host language, then wording with an explicit
/// resource language. Changing process-wide AppleLanguages races other suites.
func expectLocalizedCopy(_ actual: String?, _ resource: LocalizedStringResource, _ english: String) throws {
	let actual = try #require(actual)
	#expect(actual == String(localized: resource))
	var englishResource = resource
	englishResource.locale = Locale(identifier: "en_US")
	#expect(String(localized: englishResource) == english)
}

@MainActor
@Suite("Migrated feature copy")
struct FeatureLocalizationTests {
	@Test("Channel properties preserve catalog symbols and corrected English copy")
	func channelPropertiesStringsPreserveLegacyValues() throws {
		try expectLocalizedCopy(String(localized: .ChannelProperties.pleaseEnterAProperlyFormattedChannel),
		                        .ChannelProperties.pleaseEnterAProperlyFormattedChannel,
		                        "Enter a channel name beginning with a channel prefix, such as #example.")
		/* The alert asks whether to reload and offers Cancel and Reload, so
		 neither half of it may name a "Yes" button that is not there. */
		try expectLocalizedCopy(String(localized: .ChannelProperties.thisChannelsConfigurationHasChangedDo),
		                        .ChannelProperties.thisChannelsConfigurationHasChangedDo,
		                        "Reload the channel’s settings?")
		try expectLocalizedCopy(String(localized: .ChannelProperties.youWillLooseUnsavedChangesIf),
		                        .ChannelProperties.youWillLooseUnsavedChangesIf,
		                        "Your unsaved changes will be discarded.")
	}

	@Test("Every typed transfer failure names its own cause and what to do about it")
	func fileTransferFailureStringsUseTypedErrors() throws {
		let cases: [(FileTransferFailure, (LocalizedStringResource, String))] = [
			(.connectionUnavailable, (
				.FileTransfer.transferWithFailedCouldNotEstablish("Alice"),
				"Could not connect to Alice. They may be offline or behind a firewall."
			)),
			(.connectTimeout, (
				.FileTransfer.transferWithFailedNoAnswer("Alice"),
				"Alice did not answer in time. They may be offline or behind a firewall."
			)),
			(.fileHandlerFailed, (
				.FileTransfer.transferWithFailedFileHandlerThrew("Alice"),
				"Could not write the file from Alice. Check that the destination folder still exists and that you can write to it."
			)),
			(.invalidResumePosition, (
				.FileTransfer.transferWithFailedProposedResumePosition("Alice"),
				"Could not resume the transfer with Alice. Choose Try Again to start it over from the beginning."
			)),
			(.noListeningPort, (
				.FileTransfer.transferWithFailedThereIsNo("Alice"),
				"No port was free for the transfer with Alice. Widen the port range in File Transfer settings, then try again."
			)),
			(.notConnectedToIRC, (
				.FileTransfer.transferWithFailedYouAreNot("Alice"),
				"Transfer with Alice stopped because the connection to the server was lost. Reconnect, then start it again."
			)),
			(.oversizedTransfer, (
				.FileTransfer.transferFromFailedBecauseTheSender("Alice"),
				"Alice sent more than the offer stated, so the transfer was stopped."
			)),
			(.peerClosedConnection, (
				.FileTransfer.transferWithFailedPeerClosed("Alice"),
				"Alice closed the connection before the transfer finished. Start it again to resume."
			)),
			(.sourceFileUnreadable, (
				.FileTransfer.transferWithFailedCouldNotRead("Alice"),
				"Could not read the file being sent to Alice. Check that it still exists and that you can open it."
			)),
			(.sourceIPAddressUnknown, (
				.FileTransfer.transferWithFailedUnknownSourceIp("Alice"),
				"Could not work out this Mac\u{2019}s IP address for the transfer with Alice. Enter one in "
					+ "File Transfer settings, then try again."
			)),
			(.storageFull, (
				.FileTransfer.transferWithFailedNoSpaceLeft("Alice"),
				"There is not enough free space to save the file from Alice. Free some space, then start the transfer again."
			)),
			(.resumeNotAnswered, (
				.FileTransfer.transferWithFailedResumeNotAnswered("Alice"),
				"Alice did not agree to resume the transfer. Choose Try Again to start it over from the beginning."
			)),
			(.stalled, (
				.FileTransfer.transferWithFailedStalled("Alice"),
				"The connection to Alice stopped responding, so the transfer was cancelled. Start it again to resume."
			)),
			(.underlying("Timed out"), (
				.FileTransfer.transferWithFailed("Alice", "Timed out"),
				"Transfer with Alice failed: Timed out"
			)),
		]
		for (failure, (resource, english)) in cases {
			try expectLocalizedCopy(failure.message(peerNickname: "Alice"), resource, english)
		}
	}

	/// Every transport error has to reach copy of its own: an `NSError`
	/// description in English was what the three timeouts used to show.
	@Test("No transport error falls through to an unlocalized description")
	func everyTransportErrorHasLocalizedCopy() {
		let transportErrors: [DCCTransferError] = [
			.connectTimeout, .stalled, .closedByPeer, .noOpenPort, .badParameter,
			.rejectedPeerAddress, .oversizedTransfer, .fileUnreadable, .fileUnwritable, .storageFull,
		]
		for error in transportErrors {
			if case .underlying = FileTransferFailure(error) {
				Issue.record("\(error) has no localized failure of its own")
			}
		}
		#expect(FileTransferFailure(.network("Boom")) == .underlying("Boom"))
	}

	@Test("Transfer statuses preserve direction, and every preparing step reads as one wait")
	func fileTransferStatusesPreserveDirectionAndCollapsePreparation() throws {
		try expectLocalizedCopy(FileTransferStatus.stopped.notice(direction: .incoming, peerNickname: "Alice"),
		                        .FileTransfer.transferFromIsStopped("Alice"),
		                        "Transfer from Alice has not started. Choose Accept to begin.")
		try expectLocalizedCopy(FileTransferStatus.stopped.notice(direction: .outgoing, peerNickname: "Alice"),
		                        .FileTransfer.transferToIsStopped("Alice"),
		                        "Transfer to Alice has not started. Choose Start Transfer to begin.")
		let listening = FileTransferStatus.isListeningAsSender.notice(direction: .outgoing, peerNickname: "Alice")
		let waiting = FileTransferStatus.waitingForReceiverToAccept.notice(
			direction: .outgoing,
			peerNickname: "Alice"
		)
		try expectLocalizedCopy(listening, .FileTransfer.transferToIsReadyWaiting("Alice"),
		                        "Waiting for Alice to accept.")
		#expect(waiting == listening)

		let preparing: [FileTransferStatus] = [.initializing, .mappingListeningPort, .waitingForLocalIPAddress]
		for status in preparing {
			for direction in [FileTransferDirection.incoming, .outgoing] {
				try expectLocalizedCopy(
					status.notice(direction: direction, peerNickname: "Alice"),
					.FileTransfer.preparingTheTransfer,
					"Preparing the transfer…"
				)
			}
		}
	}

	@Test("Transfer progress fills positional placeholders in the declared order")
	func fileTransferProgressPreservesPositionalPlaceholderContracts() throws {
		try expectLocalizedCopy(FileTransferDirection.incoming.progressNotice(
			processedSize: "1 MB", totalSize: "4 MB", speed: "2 MB",
			peerNickname: "Alice", timeRemaining: "2 seconds"
		), .FileTransfer.ofSReceivedFromRemaining("1 MB", "4 MB", "2 MB", "Alice", "2 seconds"),
		"1 MB of 4 MB (2 MB/s) received from Alice — 2 seconds remaining")
		try expectLocalizedCopy(FileTransferDirection.outgoing.progressNotice(
			processedSize: "1 MB", totalSize: "4 MB", speed: "2 MB",
			peerNickname: "Alice", timeRemaining: nil
		), .FileTransfer.ofSSent("1 MB", "4 MB", "2 MB", "Alice"),
		"1 MB of 4 MB (2 MB/s) sent to Alice")
	}

	@Test("Settings copy is keyed by the typed pane and the sidebar row")
	func preferencesStringsUseTypedPaneState() throws {
		try expectLocalizedCopy(
			String(localized: SettingsPane.general.title),
			.Settings.titleOfTheGeneral,
			"General"
		)
		try expectLocalizedCopy(
			String(localized: SettingsPane.fileTransfers.title),
			.Settings.fileTransfers,
			"File Transfers"
		)
		try expectLocalizedCopy(
			SettingsDestination.row(showing: .rules)?.title,
			.Settings.rules,
			"Rules"
		)
		try expectLocalizedCopy(
			SettingsDestination.row(showing: .hidden)?.title,
			.Settings.titleOfTheAdvanced,
			"Advanced"
		)
	}
}
