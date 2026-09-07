/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

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
		try expectLocalizedCopy(ChannelPropertiesStrings.invalidChannelName,
		                        .TDCChannelPropertiesSheet.pleaseEnterAProperlyFormattedChannel,
		                        "Please enter a properly formatted channel name.")
		try expectLocalizedCopy(ChannelPropertiesStrings.configurationChangedTitle,
		                        .TDCChannelPropertiesSheet.thisChannelsConfigurationHasChangedDo,
		                        "This channel's configuration has changed. Do you want to reload the Channel Properties dialog?")
		try expectLocalizedCopy(ChannelPropertiesStrings.unsavedChangesWarning,
		                        .TDCChannelPropertiesSheet.youWillLooseUnsavedChangesIf,
		                        "You will lose unsaved changes if you click “Yes”")
	}

	@Test("Every typed transfer failure names its own cause")
	func fileTransferFailureStringsUseTypedErrors() throws {
		let cases: [(FileTransferFailure, (LocalizedStringResource, String))] = [
			(.connectionUnavailable, (.TDCFileTransferDialog.transferWithFailedCouldNotEstablish("Alice"),
			                          "Transfer with Alice failed. Could not establish connection")),
			(.fileHandlerFailed, (.TDCFileTransferDialog.transferWithFailedFileHandlerThrew("Alice"),
			                      "Transfer with Alice failed. File handler threw an exception")),
			(.invalidResumePosition, (.TDCFileTransferDialog.transferWithFailedProposedResumePosition("Alice"),
			                          "Transfer with Alice failed. Proposed resume position is bad")),
			(.noListeningPort, (.TDCFileTransferDialog.transferWithFailedThereIsNo("Alice"),
			                    "Transfer with Alice failed. There is no open port")),
			(.notConnectedToIRC, (.TDCFileTransferDialog.transferWithFailedYouAreNot("Alice"),
			                      "Transfer with Alice failed. You are not connected to IRC")),
			(.sourceFileUnreadable, (.TDCFileTransferDialog.transferWithFailedCouldNotRead("Alice"),
			                         "Transfer with Alice failed. Could not read source file")),
			(.sourceIPAddressUnknown, (.TDCFileTransferDialog.transferWithFailedUnknownSourceIp("Alice"),
			                           "Transfer with Alice failed. Unknown source IP address")),
			(.storageFull, (.TDCFileTransferDialog.transferWithFailedNoSpaceLeft("Alice"),
			                "Transfer with Alice failed. No space left on device")),
			(.underlying("Timed out"), (.TDCFileTransferDialog.transferWithFailed("Alice", "Timed out"),
			                            "Transfer with Alice failed: Timed out")),
		]
		for (failure, (resource, english)) in cases {
			try expectLocalizedCopy(FileTransferStrings.failure(failure, peerNickname: "Alice"), resource, english)
		}
	}

	@Test("Transfer statuses preserve direction and share the acceptance message")
	func fileTransferStatusesPreserveDirectionAndDeduplicateAcceptanceMessage() throws {
		try expectLocalizedCopy(FileTransferStrings.status(.stopped, direction: .incoming, peerNickname: "Alice"),
		                        .TDCFileTransferDialog.transferFromIsStoppedControlClick("Alice"),
		                        "Transfer from Alice is stopped. Control click to start.")
		try expectLocalizedCopy(FileTransferStrings.status(.stopped, direction: .outgoing, peerNickname: "Alice"),
		                        .TDCFileTransferDialog.transferToIsStoppedControlClick("Alice"),
		                        "Transfer to Alice is stopped. Control click to start.")
		let listening = FileTransferStrings.status(.isListeningAsSender, direction: .outgoing, peerNickname: "Alice")
		let waiting = FileTransferStrings.status(
			.waitingForReceiverToAccept,
			direction: .outgoing,
			peerNickname: "Alice"
		)
		try expectLocalizedCopy(listening, .TDCFileTransferDialog.transferToIsReadyWaiting("Alice"),
		                        "Transfer to Alice is ready. Waiting for them to accept.")
		#expect(waiting == listening)
	}

	@Test("Transfer progress fills positional placeholders in the declared order")
	func fileTransferProgressPreservesPositionalPlaceholderContracts() throws {
		try expectLocalizedCopy(FileTransferStrings.progress(
			direction: .incoming, processedSize: "1 MB", totalSize: "4 MB", speed: "2 MB",
			peerNickname: "Alice", timeRemaining: "2 seconds"
		), .TDCFileTransferDialog.ofSReceivedFromRemaining("1 MB", "4 MB", "2 MB", "Alice", "2 seconds"),
		"1 MB of 4 MB (2 MB/s) received from Alice — 2 seconds remaining")
		try expectLocalizedCopy(FileTransferStrings.progress(
			direction: .outgoing, processedSize: "1 MB", totalSize: "4 MB", speed: "2 MB",
			peerNickname: "Alice", timeRemaining: nil
		), .TDCFileTransferDialog.ofSSent("1 MB", "4 MB", "2 MB", "Alice"),
		"1 MB of 4 MB (2 MB/s) sent to Alice")
	}

	@Test("Preferences copy is keyed by the typed pane")
	func preferencesStringsUseTypedPaneState() throws {
		try expectLocalizedCopy(
			PreferencesStrings.paneTitle(.general),
			.TDCPreferencesController.titleOfTheGeneral,
			"General"
		)
		try expectLocalizedCopy(
			PreferencesStrings.paneTitle(.fileTransfers),
			.TDCPreferencesController.fileTransfers,
			"File Transfers"
		)
		try expectLocalizedCopy(PreferencesStrings.addOnsGroupTitle, .TDCPreferencesController.addOns, "Add-ons")
		try expectLocalizedCopy(
			PreferencesStrings.advancedGroupTitle,
			.TDCPreferencesController.titleOfTheAdvanced,
			"Advanced"
		)
	}
}
