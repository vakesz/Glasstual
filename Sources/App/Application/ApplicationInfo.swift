// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import CocoaExtensions

nonisolated enum ApplicationInfo {
	static func applicationName() -> String {
		bundleValue(for: "CFBundleName")
	}

	static func applicationVersion() -> String {
		bundleValue(for: "CFBundleVersion")
	}

	/// The copyright line the bundle declares, which is what the standard About
	/// panel would show.
	static func applicationCopyright() -> String {
		bundleValue(for: "NSHumanReadableCopyright")
	}

	static func applicationVersionShort() -> String {
		bundleValue(for: "CFBundleShortVersionString")
	}

	static func applicationBundleIdentifier() -> String {
		guard let identifier = Bundle.main.bundleIdentifier, !identifier.isEmpty else {
			preconditionFailure("The generated Info.plist is missing CFBundleIdentifier")
		}

		return identifier
	}

	static func applicationLaunchDate() -> Date? {
		NSRunningApplication.current.launchDate
	}

	static func timeIntervalSinceApplicationLaunch() -> TimeInterval {
		guard let launchDate = applicationLaunchDate() else {
			return 0
		}

		return -launchDate.timeIntervalSinceNow
	}

	@MainActor static func timeIntervalSinceApplicationInstall() -> TimeInterval {
		SettingsKeys.Internals.runTime.value + timeIntervalSinceApplicationLaunch()
	}

	@MainActor static func saveTimeIntervalSinceApplicationInstall() {
		SettingsKeys.Internals.runTime.value = timeIntervalSinceApplicationInstall()
	}

	@MainActor static func applicationRunCount() -> UInt {
		SettingsKeys.Internals.runCount.value
	}

	/// The stored count is read back before it is raised, and a value a
	/// hand-edited defaults entry can carry is not a count: the bound on the
	/// declaration is what keeps one out, and the saturation here is what keeps
	/// a launch from ending on the increment if one ever gets past it.
	@MainActor static func incrementApplicationRunCount() {
		let count = applicationRunCount()
		SettingsKeys.Internals.runCount.value = count < .max ? count + 1 : count
	}

	private static func bundleValue(for key: String) -> String {
		Bundle.main.object(forInfoDictionaryKey: key) as? String ?? ""
	}
}
