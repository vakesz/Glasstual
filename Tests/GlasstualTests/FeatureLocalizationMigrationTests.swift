/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

@testable import Glasstual
import XCTest

@MainActor
final class FeatureLocalizationMigrationTests: XCTestCase {
	func testChannelPropertiesStringsPreserveLegacyValues() {
		XCTAssertEqual(
			ChannelPropertiesStrings.invalidChannelName,
			"Please enter a properly formatted channel name."
		)
		XCTAssertEqual(
			ChannelPropertiesStrings.configurationChangedTitle,
			"This channel's configuration has changed. Do you want to reload the Channel Properties dialog?"
		)
		XCTAssertEqual(
			ChannelPropertiesStrings.unsavedChangesWarning,
			"You will loose unsaved changes if you click “Yes”"
		)
	}

	func testFileTransferFailureStringsUseTypedErrors() {
		let peer = "Alice"
		XCTAssertEqual(
			FileTransferStrings.failure(.connectionUnavailable, peerNickname: peer),
			"Transfer with Alice failed. Could not establish connection"
		)
		XCTAssertEqual(
			FileTransferStrings.failure(.fileHandlerFailed, peerNickname: peer),
			"Transfer with Alice failed. File handler threw an exception"
		)
		XCTAssertEqual(
			FileTransferStrings.failure(.invalidResumePosition, peerNickname: peer),
			"Transfer with Alice failed. Proposed resume position is bad"
		)
		XCTAssertEqual(
			FileTransferStrings.failure(.noListeningPort, peerNickname: peer),
			"Transfer with Alice failed. There is no open port"
		)
		XCTAssertEqual(
			FileTransferStrings.failure(.notConnectedToIRC, peerNickname: peer),
			"Transfer with Alice failed. You are not connected to IRC"
		)
		XCTAssertEqual(
			FileTransferStrings.failure(.sourceFileUnreadable, peerNickname: peer),
			"Transfer with Alice failed. Could not read source file"
		)
		XCTAssertEqual(
			FileTransferStrings.failure(.sourceIPAddressUnknown, peerNickname: peer),
			"Transfer with Alice failed. Unknown source IP address"
		)
		XCTAssertEqual(
			FileTransferStrings.failure(.storageFull, peerNickname: peer),
			"Transfer with Alice failed. No space left on device"
		)
		XCTAssertEqual(
			FileTransferStrings.failure(.underlying("Timed out"), peerNickname: peer),
			"Transfer with Alice failed: Timed out"
		)
	}

	func testFileTransferStatusesPreserveDirectionAndDeduplicateAcceptanceMessage() {
		XCTAssertEqual(
			FileTransferStrings.status(.stopped, direction: .incoming, peerNickname: "Alice"),
			"Transfer from Alice is stopped. Control click to start."
		)
		XCTAssertEqual(
			FileTransferStrings.status(.stopped, direction: .outgoing, peerNickname: "Alice"),
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
		XCTAssertEqual(listening, "Transfer to Alice is ready. Waiting for them to accept.")
		XCTAssertEqual(waiting, listening)
	}

	func testFileTransferProgressPreservesPositionalPlaceholderContracts() {
		XCTAssertEqual(
			FileTransferStrings.progress(
				direction: .incoming,
				processedSize: "1 MB",
				totalSize: "4 MB",
				speed: "2 MB",
				peerNickname: "Alice",
				timeRemaining: "2 seconds"
			),
			"1 MB of 4 MB (2 MB/s) received from Alice — 2 seconds remaining"
		)
		XCTAssertEqual(
			FileTransferStrings.progress(
				direction: .outgoing,
				processedSize: "1 MB",
				totalSize: "4 MB",
				speed: "2 MB",
				peerNickname: "Alice",
				timeRemaining: nil
			),
			"1 MB of 4 MB (2 MB/s) sent to Alice"
		)
	}

	func testPreferencesStringsUseTypedPaneAndOverrideState() {
		XCTAssertEqual(PreferencesStrings.paneTitle(.general), "General")
		XCTAssertEqual(PreferencesStrings.paneTitle(.fileTransfers), "File Transfers")
		XCTAssertEqual(PreferencesStrings.addOnsGroupTitle, "Add-ons")
		XCTAssertEqual(PreferencesStrings.advancedGroupTitle, "Advanced")
		XCTAssertEqual(PreferencesStrings.version(marketingVersion: "6.0", build: "42"), "Version 6.0 (42)")
		XCTAssertEqual(
			PreferencesStrings.preferredSelectionBody(
				styleName: "Default",
				overrides: [.nicknameFormat, .timestampFormat]
			),
			"The style named “Default” has chosen to override the following preferences with ones that it prefers "
				+ "for the best viewing experience:\n\n• Nickname Format\n• Timestamp Format"
		)
	}
}
