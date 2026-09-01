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

import CocoaExtensions
import Foundation
@testable import Glasstual
import Testing

/// Retired settings must not remain in generated defaults after their owners
/// are removed.
@Suite("Removed preference keys")
@MainActor
struct RemovedPreferenceKeyTests {
	private static let removedKeys = [
		"InlineMediaLimitInsecureContent",
		"InlineMediaMaximumFilesize",
		"InlineMediaScalingWidth",
		"InlineMediaMaximumHeight",
		"InlineMediaLimitToBasics",
		"InlineMediaLimitBasicsToFiles",
		"InlineMediaLimitNaughtyContent",
		"InlineMediaLimitUnsafeContent",
		"InlineMediaCheckEverything",
		"InlineMediaAllowsCleartextHTTP",
		"User List Mode Badge Colors -> no mode",
		"ChannelViewArrangement",
		"Window -> Main Window -> Split Channel View Saved Frames",
	]

	private nonisolated static let preferencePlists = [
		"PreferenceKeyMasterList",
		"RegisteredUserDefaultsInContainer",
		"KeysExcludedFromExport",
		"KeysExcludedFromContainer",
	]

	@Test("No preference plist still declares a removed key", arguments: preferencePlists)
	func plistsDoNotDeclareRemovedKeys(named name: String) throws {
		guard let url = Bundle.main.url(
			forResource: name,
			withExtension: "plist",
			subdirectory: "Preferences"
		) else {
			return
		}
		let contents = try Data(contentsOf: url)
		let plist = try PropertyListSerialization.propertyList(from: contents, format: nil)
		let keys = [String: PropertyListValue](propertyList: plist)?.keys.sorted() ?? []
		for removed in Self.removedKeys {
			#expect(keys.contains(removed) == false)
		}
	}

	@Test("The registration domain no longer carries a removed key")
	func registrationDomainIsClean() {
		let registered = TextualPreferences.defaultPreferences()
		for removed in Self.removedKeys {
			#expect(registered[removed] == nil)
		}
	}
}
