/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

@testable import Glasstual
import Testing

@MainActor
@Suite("Migrated feature copy")
struct FeatureLocalizationMigrationTests {
	@Test("Channel properties copy still reads the way the legacy table did")
	func channelPropertiesStringsPreserveLegacyValues() {
		#expect(ChannelPropertiesStrings.invalidChannelName == "Please enter a properly formatted channel name.")
		#expect(
			ChannelPropertiesStrings.configurationChangedTitle ==
				"This channel's configuration has changed. Do you want to reload the Channel Properties dialog?"
		)
		#expect(
			ChannelPropertiesStrings.unsavedChangesWarning ==
				"You will loose unsaved changes if you click “Yes”"
		)
	}

	@Test("Every typed transfer failure names its own cause")
	func fileTransferFailureStringsUseTypedErrors() {
		let peer = "Alice"
		#expect(
			FileTransferStrings.failure(.connectionUnavailable, peerNickname: peer) ==
				"Transfer with Alice failed. Could not establish connection"
		)
		#expect(
			FileTransferStrings.failure(.fileHandlerFailed, peerNickname: peer) ==
				"Transfer with Alice failed. File handler threw an exception"
		)
		#expect(
			FileTransferStrings.failure(.invalidResumePosition, peerNickname: peer) ==
				"Transfer with Alice failed. Proposed resume position is bad"
		)
		#expect(
			FileTransferStrings.failure(.noListeningPort, peerNickname: peer) ==
				"Transfer with Alice failed. There is no open port"
		)
		#expect(
			FileTransferStrings.failure(.notConnectedToIRC, peerNickname: peer) ==
				"Transfer with Alice failed. You are not connected to IRC"
		)
		#expect(
			FileTransferStrings.failure(.sourceFileUnreadable, peerNickname: peer) ==
				"Transfer with Alice failed. Could not read source file"
		)
		#expect(
			FileTransferStrings.failure(.sourceIPAddressUnknown, peerNickname: peer) ==
				"Transfer with Alice failed. Unknown source IP address"
		)
		#expect(
			FileTransferStrings.failure(.storageFull, peerNickname: peer) ==
				"Transfer with Alice failed. No space left on device"
		)
		#expect(
			FileTransferStrings.failure(.underlying("Timed out"), peerNickname: peer) ==
				"Transfer with Alice failed: Timed out"
		)
	}

	@Test("A transfer status names its direction, and the two waiting states share one sentence")
	func fileTransferStatusesPreserveDirectionAndDeduplicateAcceptanceMessage() {
		#expect(
			FileTransferStrings.status(.stopped, direction: .incoming, peerNickname: "Alice") ==
				"Transfer from Alice is stopped. Control click to start."
		)
		#expect(
			FileTransferStrings.status(.stopped, direction: .outgoing, peerNickname: "Alice") ==
				"Transfer to Alice is stopped. Control click to start."
		)
		let listening = FileTransferStrings.status(
			.isListeningAsSender,
			direction: .outgoing,
			peerNickname: "Alice"
		)
		let waiting = FileTransferStrings.status(
			.waitingForReceiverToAccept,
			direction: .outgoing,
			peerNickname: "Alice"
		)
		#expect(listening == "Transfer to Alice is ready. Waiting for them to accept.")
		#expect(waiting == listening)
	}

	@Test("Transfer progress fills its positional placeholders in the declared order")
	func fileTransferProgressPreservesPositionalPlaceholderContracts() {
		#expect(
			FileTransferStrings.progress(
				direction: .incoming,
				processedSize: "1 MB",
				totalSize: "4 MB",
				speed: "2 MB",
				peerNickname: "Alice",
				timeRemaining: "2 seconds"
			) == "1 MB of 4 MB (2 MB/s) received from Alice — 2 seconds remaining"
		)
		#expect(
			FileTransferStrings.progress(
				direction: .outgoing,
				processedSize: "1 MB",
				totalSize: "4 MB",
				speed: "2 MB",
				peerNickname: "Alice",
				timeRemaining: nil
			) == "1 MB of 4 MB (2 MB/s) sent to Alice"
		)
	}

	@Test("Preferences copy is keyed by the typed pane")
	func preferencesStringsUseTypedPaneState() {
		#expect(PreferencesStrings.paneTitle(.general) == "General")
		#expect(PreferencesStrings.paneTitle(.fileTransfers) == "File Transfers")
		#expect(PreferencesStrings.addOnsGroupTitle == "Add-ons")
		#expect(PreferencesStrings.advancedGroupTitle == "Advanced")
	}
}
