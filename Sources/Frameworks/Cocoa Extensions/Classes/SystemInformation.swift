/* *********************************************************************
 *
 *         Copyright (c) 2015 - 2020 Codeux Software, LLC
 *     Please see ACKNOWLEDGEMENT for additional information.
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
 *  * Neither the name of "Codeux Software, LLC", nor the names of its
 *    contributors may be used to endorse or promote products derived
 *    from this software without specific prior written permission.
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
import Darwin

@objc(XRSystemInformation)
final class SystemInformation: NSObject {
	private static let sleepStateLock = NSLock()
	private nonisolated(unsafe) static var sleeping = false

	private nonisolated(unsafe) static let sleepObservers: [NSObjectProtocol] = {
		let center = NSWorkspace.shared.notificationCenter
		return [
			center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: nil) { _ in
				sleepStateLock.withLock { sleeping = true }
			},
			center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: nil) { _ in
				sleepStateLock.withLock { sleeping = false }
			},
		]
	}()

	@objc(systemIsSleeping)
	class var systemIsSleeping: Bool {
		_ = sleepObservers
		return sleepStateLock.withLock { sleeping }
	}

	@objc(systemBuildVersion)
	class var systemBuildVersion: String? {
		SystemVersion.shared.productBuildVersion
	}

	@objc(systemStandardVersion)
	class var systemStandardVersion: String {
		let version = ProcessInfo.processInfo.operatingSystemVersion
		if version.patchVersion == 0 {
			return "\(version.majorVersion).\(version.minorVersion)"
		}
		return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
	}

	@objc(systemOperatingSystemName)
	class var systemOperatingSystemName: String {
		let key = ProcessInfo.processInfo.operatingSystemVersion.majorVersion == 26 ? "macOS Tahoe" : "macOS"
		return localizedString(key)
	}

	@available(*, deprecated, message: "Return value is not reliable on new Macs. No alternative available.")
	@objc(systemModelName)
	class var systemModelName: String? {
		guard let token = systemModelToken?.lowercased(), !token.isEmpty else { return nil }

		let names = [
			"macbookpro": "MacBook Pro",
			"macbookair": "MacBook Air",
			"macbook": "MacBook",
			"macpro": "Mac Pro",
			"macmini": "Mac Mini",
			"imac": "iMac",
			"xserve": "Xserve",
		]

		let name = names.first(where: { token.hasPrefix($0.key) })?.value ?? "Mac"
		return localizedString(name)
	}

	private class var systemModelToken: String? {
		var buffer = [CChar](repeating: 0, count: 256)
		var size = buffer.count
		guard sysctlbyname("hw.model", &buffer, &size, nil, 0) == 0 else { return nil }
		let bytes = buffer.prefix { $0 != 0 }.map(UInt8.init(bitPattern:))
		return String(bytes: bytes, encoding: .utf8)
	}

	private class func localizedString(_ key: String) -> String {
		NSLocalizedString(key, tableName: "XRSystemInformation", bundle: Bundle(for: self), comment: "")
	}
}

private struct SystemVersion: @unchecked Sendable {
	static let shared = SystemVersion()
	let productBuildVersion: String?

	private init() {
		let path = "/System/Library/CoreServices/SystemVersion.plist"
		productBuildVersion = (NSDictionary(contentsOfFile: path) as? [String: Any])?["ProductBuildVersion"] as? String
	}
}
