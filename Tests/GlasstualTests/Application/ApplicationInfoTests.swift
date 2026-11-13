// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Application metadata", .serialized)
struct ApplicationInfoTests {
	@Test("Application metadata is read straight out of the main bundle")
	func applicationMetadataMatchesMainBundle() {
		let bundle = Bundle.main

		#expect(ApplicationInfo.applicationName() == bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
		#expect(
			ApplicationInfo.applicationVersion() == bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
		)
		#expect(
			ApplicationInfo.applicationVersionShort()
				== bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
		)
		#expect(ApplicationInfo.applicationBundleIdentifier() == bundle.bundleIdentifier)
	}

	@Test("The process metadata describes a running application")
	func applicationRuntimeMetadataIsSane() {
		#expect(ApplicationInfo.timeIntervalSinceApplicationLaunch() >= 0)
		#expect(ApplicationInfo.applicationName().isEmpty == false)
	}

	/** The launch count is read back out of the defaults suite before it is
	 raised, so a value a hand-edited entry can carry has to survive the
	 increment. The declaration's bound is what keeps one out of the suite in the
	 first place, and the count is read back as an `Int`. */
	@Test("The launch count survives a stored value no count could reach")
	func launchCountSaturatesAndIsBounded() {
		let stored = SettingsKeys.Internals.runCount.value
		defer { SettingsKeys.Internals.runCount.value = stored }

		SettingsKeys.Internals.runCount.value = .max
		ApplicationInfo.incrementApplicationRunCount()

		#expect(ApplicationInfo.applicationRunCount() == .max)

		SettingsKeys.Internals.runCount.value = 41
		ApplicationInfo.incrementApplicationRunCount()

		#expect(ApplicationInfo.applicationRunCount() == 42)
		#expect(SettingsKeys.Internals.runCount.coerce(.integer(Int(Int32.max))) != nil)
		#expect(SettingsKeys.Internals.runCount.coerce(.string("\(UInt.max)")) == nil)
	}
}
