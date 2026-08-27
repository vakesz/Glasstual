/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation
@testable import Glasstual
import XCTest

@MainActor
final class LocalizationCatalogMigrationTests: XCTestCase {
	func testTypedBoundariesResolveMigratedCatalogValues() {
		XCTAssertEqual(AccessibilityStrings.userListEntry(for: "Alice"), "User Alice in User List")
		XCTAssertEqual(AccessibilityStrings.mainWindow, "Main Window")
		XCTAssertEqual(CommonValidationStrings.invalidNickname, "Please enter a properly formatted nickname.")
		XCTAssertEqual(CommonValidationStrings.maximumLength(390), "Maximum length is 390 characters.")
		XCTAssertEqual(NotificationStrings.eventTypeTitle(for: .invite), "Channel Invitation")
		XCTAssertEqual(
			NotificationStrings.deliveredTitle(for: .highlight, subject: "#textual"),
			"Highlight: #textual"
		)
		XCTAssertEqual(
			NotificationStrings.Membership.parted(
				nickname: "Alice",
				channelName: "#textual",
				reason: "Leaving"
			),
			"Alice parted #textual with reason: Leaving"
		)
		XCTAssertEqual(
			NotificationStrings.FileTransfer.description(
				for: .fileTransferReceiveSuccessful,
				filename: "archive.zip",
				byteCount: 1024
			),
			"archive.zip (1024 bytes)"
		)
		XCTAssertEqual(NotificationSoundStrings.defaultSound, "Default Sound")
		XCTAssertEqual(NotificationSoundStrings.noSound, "No Sound")
	}

	func testMigratedCatalogSchemaTracksAllNinetySixEntries() throws {
		let expectedCounts = [
			"Accessibility": 8,
			"CommonErrors": 5,
			"Notifications": 81,
			"TVCNotificationConfigurationView": 2,
		]
		var totalEntryCount = 0

		for (tableName, expectedCount) in expectedCounts {
			let catalog = try catalog(named: tableName)
			XCTAssertEqual(catalog.sourceLanguage, "en", tableName)
			XCTAssertEqual(catalog.version, "1.0", tableName)
			XCTAssertEqual(catalog.strings.count, expectedCount, tableName)
			totalEntryCount += catalog.strings.count

			for (key, entry) in catalog.strings {
				XCTAssertTrue(entry.comment.contains("Migrated from legacy key"), "\(tableName):\(key)")
				XCTAssertTrue(["manual", "extracted"].contains(entry.extractionState), "\(tableName):\(key)")
				let english = try XCTUnwrap(entry.localizations["en"], "\(tableName):\(key)")
				XCTAssertEqual(english.stringUnit.state, "translated", "\(tableName):\(key)")
				XCTAssertFalse(english.stringUnit.value.isEmpty, "\(tableName):\(key)")
			}
		}

		XCTAssertEqual(totalEntryCount, 96)
	}

	private func catalog(named tableName: String) throws -> Catalog {
		let repositoryURL = URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.deletingLastPathComponent()
		let catalogURL = repositoryURL
			.appending(path: "Sources/App/Resources/Language Files")
			.appending(path: "\(tableName).xcstrings")

		return try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: catalogURL))
	}
}

private struct Catalog: Decodable {
	let sourceLanguage: String
	let strings: [String: CatalogEntry]
	let version: String
}

private struct CatalogEntry: Decodable {
	let comment: String
	let extractionState: String
	let localizations: [String: CatalogLocalization]
}

private struct CatalogLocalization: Decodable {
	let stringUnit: CatalogStringUnit
}

private struct CatalogStringUnit: Decodable {
	let state: String
	let value: String
}
