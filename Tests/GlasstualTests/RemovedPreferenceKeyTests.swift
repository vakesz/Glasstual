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

	@Test("The registration domain no longer carries a removed key")
	func registrationDomainIsClean() {
		let registered = TextualPreferences.defaultPreferences()
		for removed in Self.removedKeys {
			#expect(registered[removed] == nil)
		}
	}
}
