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
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *  * Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *  * Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *  * Neither the name of Textual, "Codeux Software, LLC", nor the
 *    names of its contributors may be used to endorse or promote products
 *    derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 *********************************************************************** */

import AppKit
import CocoaExtensions

public nonisolated enum ApplicationInfo { // nonisolated: value
	public static func applicationName() -> String {
		bundleValue(for: "CFBundleName")
	}

	public static func applicationNameWithoutVersion() -> String {
		let name = applicationName()

		guard let separator = name.firstIndex(of: " "), separator != name.startIndex else {
			return name
		}

		return String(name[..<separator])
	}

	public static func applicationVersion() -> String {
		bundleValue(for: "CFBundleVersion")
	}

	public static func applicationVersionShort() -> String {
		bundleValue(for: "CFBundleShortVersionString")
	}

	public static func applicationProcessID() -> Int32 {
		ProcessInfo.processInfo.processIdentifier
	}

	public static func applicationBundleIdentifier() -> String {
		guard let identifier = Bundle.main.bundleIdentifier, !identifier.isEmpty else {
			preconditionFailure("The generated Info.plist is missing CFBundleIdentifier")
		}

		return identifier
	}

	public static func applicationInfoPlist() -> [String: PropertyListValue] {
		Bundle.main.infoDictionary.flatMap { [String: PropertyListValue](propertyList: $0) } ?? [:]
	}

	public static func applicationLaunchDate() -> Date? {
		NSRunningApplication.current.launchDate
	}

	public static func timeIntervalSinceApplicationLaunch() -> TimeInterval {
		guard let launchDate = applicationLaunchDate() else {
			return 0
		}

		return -launchDate.timeIntervalSinceNow
	}

	@MainActor public static func timeIntervalSinceApplicationInstall() -> TimeInterval {
		Preferences.Internals.runTime.value + timeIntervalSinceApplicationLaunch()
	}

	@MainActor public static func saveTimeIntervalSinceApplicationInstall() {
		Preferences.Internals.runTime.value = timeIntervalSinceApplicationInstall()
	}

	@MainActor public static func applicationRunCount() -> UInt {
		Preferences.Internals.runCount.value
	}

	@MainActor public static func incrementApplicationRunCount() {
		Preferences.Internals.runCount.value = applicationRunCount() + 1
	}

	public static func applicationBirthday() -> TimeInterval {
		1_279_871_580
	}

	private static func bundleValue(for key: String) -> String {
		Bundle.main.object(forInfoDictionaryKey: key) as? String ?? ""
	}
}
