/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\\_\\__|\\__,_|\\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import AppKit

@objc(TPCApplicationInfo)
public final class ApplicationInfo: NSObject {
	private static let runtimeDefaultsKey = "TXRunTime"
	private static let runCountDefaultsKey = "TXRunCount"

	@objc public static func applicationName() -> String {
		bundleValue(for: "CFBundleName")
	}

	@objc public static func applicationNameWithoutVersion() -> String {
		let name = applicationName()

		guard let separator = name.firstIndex(of: " "), separator != name.startIndex else {
			return name
		}

		return String(name[..<separator])
	}

	@objc public static func applicationVersion() -> String {
		bundleValue(for: "CFBundleVersion")
	}

	@objc public static func applicationVersionShort() -> String {
		bundleValue(for: "CFBundleShortVersionString")
	}

	@objc public static func applicationProcessID() -> Int32 {
		ProcessInfo.processInfo.processIdentifier
	}

	@objc public static func applicationBundleIdentifier() -> String {
		Bundle.main.bundleIdentifier ?? ""
	}

	@objc public static func applicationInfoPlist() -> [String: Any] {
		Bundle.main.infoDictionary ?? [:]
	}

	@objc public static func applicationLaunchDate() -> Date? {
		NSRunningApplication.current.launchDate
	}

	@objc public static func timeIntervalSinceApplicationLaunch() -> TimeInterval {
		guard let launchDate = applicationLaunchDate() else {
			return 0
		}

		return -launchDate.timeIntervalSinceNow
	}

	@objc public static func timeIntervalSinceApplicationInstall() -> TimeInterval {
		userDefaults.double(forKey: runtimeDefaultsKey) + timeIntervalSinceApplicationLaunch()
	}

	@objc public static func saveTimeIntervalSinceApplicationInstall() {
		userDefaults.set(timeIntervalSinceApplicationInstall(), forKey: runtimeDefaultsKey)
	}

	@objc public static func applicationRunCount() -> UInt {
		userDefaults.unsignedInteger(forKey: runCountDefaultsKey)
	}

	@objc public static func incrementApplicationRunCount() {
		userDefaults.setUnsignedInteger(applicationRunCount() + 1, forKey: runCountDefaultsKey)
	}

	@objc public static func applicationBirthday() -> TimeInterval {
		1_279_871_580
	}

	private static func bundleValue(for key: String) -> String {
		Bundle.main.object(forInfoDictionaryKey: key) as? String ?? ""
	}

	private static var userDefaults: TPCPreferencesUserDefaults {
		TPCPreferencesUserDefaults.shared()
	}
}
