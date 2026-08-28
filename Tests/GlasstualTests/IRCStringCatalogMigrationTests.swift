/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import CryptoKit
import Foundation
@testable import Glasstual
import XCTest

final class IRCStringCatalogMigrationTests: XCTestCase {
	func testCatalogRetainsAllLegacyKeysAndExactValueDigest() throws {
		let catalog = try loadCatalog()
		XCTAssertEqual(catalog.sourceLanguage, "en")
		XCTAssertEqual(catalog.version, "1.0")
		// 220 keys carried over from the Objective-C .strings files, plus the
		// keys added since. Only the migrated ones carry the legacy comment.
		XCTAssertEqual(catalog.strings.count, 221)

		let canonicalValues = catalog.strings.keys.sorted().map { key in
			let entry = catalog.strings[key]!
			if entry.comment.contains("Migrated from legacy key") {
				XCTAssertTrue(entry.comment.contains("Migrated from legacy key \(key)"), key)
			}
			XCTAssertEqual(entry.localizations["en"]?.stringUnit.state, "translated", key)

			return key + "\u{1F}" + (entry.localizations["en"]?.stringUnit.value ?? "")
		}.joined(separator: "\u{1E}")
		let digest = SHA256.hash(data: Data(canonicalValues.utf8))
		XCTAssertEqual(
			digest.map { String(format: "%02x", $0) }.joined(),
			"c651062af8cfc2297c09b1371caa53ed37812f73bca4c2289f353e77b9944120"
		)
	}

	func testGeneratedAndLegacyFormatterBoundariesPreservePlaceholders() {
		XCTAssertEqual(
			IRCCommandStrings.topicTooLong(networkName: "Libera.Chat", maximumLength: 390),
			"You have exceeded the maximum topic length for Libera.Chat which is 390 characters. "
				+ "The end of your topic may have been cut off."
		)
		XCTAssertEqual(
			IRCConnectionStrings.connecting(host: "irc.example", port: 6697),
			"Connecting to [irc.example] on port 6697"
		)
		XCTAssertEqual(
			IRCFileTransferStrings.request(nickname: "Alice", filename: "archive.zip", byteCount: 1024),
			"Received file transfer request from Alice, archive.zip (1024 bytes)"
		)
	}

	func testTypedDynamicSelectionsPreserveBehavior() {
		XCTAssertEqual(IRCTimerStrings.status(active: true), "Active")
		XCTAssertTrue(IRCTimerStrings.help(topic: .restart).contains("/timer restart <identifier>"))
		XCTAssertEqual(IRCCTCPStrings.lagRating(.excellent), "Yeah, okay…")
		XCTAssertEqual(IRCCTCPStrings.lagRating(.verySlow), "Very slow")
		XCTAssertEqual(
			IRCISupportStrings.extendedBanDescription(type: "a", argument: "staff"),
			"Users logged in to account “staff”"
		)
		XCTAssertEqual(
			IRCISupportStrings.extendedBanDescription(type: "?", argument: "mask"),
			"Extended ban of type “?”: mask"
		)
		XCTAssertEqual(
			IRCChannelAccessListStrings.entry(
				kind: .ban,
				channelName: "#swift",
				mask: "*!*@example",
				setBy: "Alice",
				date: "26 Aug 2026"
			),
			"Ban in #swift: *!*@example set by Alice on 26 Aug 2026"
		)
	}

	func testSetNameUsesRetainedCatalogEntry() {
		XCTAssertEqual(
			IRCCommandStrings.setNameUnsupported,
			"This server does not support changing the real name (setname)"
		)
	}

	private func loadCatalog() throws -> Catalog {
		let repositoryURL = URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.deletingLastPathComponent()
		let catalogURL = repositoryURL
			.appending(path: "Sources/App/Resources/Language Files/IRC.xcstrings")

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
	let localizations: [String: CatalogLocalization]
}

private struct CatalogLocalization: Decodable {
	let stringUnit: CatalogStringUnit
}

private struct CatalogStringUnit: Decodable {
	let state: String
	let value: String
}
