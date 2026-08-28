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
import Synchronization

public enum SystemInformation {
	private struct SleepState {
		var observing = false
		var sleeping = false
	}

	/// `Mutex` makes the invariant -- this is only ever read or written under
	/// the lock -- one the compiler checks, which `nonisolated(unsafe)` plus an
	/// `NSLock` did not.
	private static let sleepState = Mutex(SleepState())

	/** Must be called during launch. Relying on the first read of `systemIsSleeping` to
	 register the observers means a sleep that happens before any read is never seen. */
	public static func beginObservingSleepState() {
		let shouldRegister = sleepState.withLock { state in
			guard !state.observing else {
				return false
			}

			state.observing = true
			return true
		}

		guard shouldRegister else {
			return
		}

		/* The observations last for the life of the process, so the returned
		 tokens have nothing to be kept for. */
		let center = NSWorkspace.shared.notificationCenter

		_ = center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: nil) { _ in
			sleepState.withLock { $0.sleeping = true }
		}

		_ = center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: nil) { _ in
			sleepState.withLock { $0.sleeping = false }
		}
	}

	public static var systemIsSleeping: Bool {
		beginObservingSleepState()
		return sleepState.withLock(\.sleeping)
	}

	public static var systemBuildVersion: String? {
		SystemVersion.shared.productBuildVersion
	}

	public static var systemStandardVersion: String {
		let version = ProcessInfo.processInfo.operatingSystemVersion
		if version.patchVersion == 0 {
			return "\(version.majorVersion).\(version.minorVersion)"
		}
		return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
	}

	/// The name of the platform, without a marketing release name. The release
	/// is already identified by `systemStandardVersion`, and a table of
	/// marketing names is wrong the day the next major version ships.
	public static var systemOperatingSystemName: String {
		String(localized: .XRSystemInformation.operatingSystemMacos)
	}
}

private struct SystemVersion: Sendable {
	static let shared = SystemVersion()
	let productBuildVersion: String?

	private init() {
		let path = "/System/Library/CoreServices/SystemVersion.plist"
		productBuildVersion = (NSDictionary(contentsOfFile: path) as? [String: Any])?["ProductBuildVersion"] as? String
	}
}
