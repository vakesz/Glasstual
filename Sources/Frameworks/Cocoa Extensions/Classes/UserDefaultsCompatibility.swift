/* *********************************************************************
 *
 *         Copyright (c) 2016 - 2018 Codeux Software, LLC
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

public extension UserDefaults {
	func setColor(_ color: NSColor?, forKey key: String) {
		guard let color else {
			removeObject(forKey: key)
			return
		}

		do {
			try set(NSKeyedArchiver.archivedData(withRootObject: color, requiringSecureCoding: true), forKey: key)
		} catch {
			/* A colour that will not archive is a preference the user loses, not
			 a programming error worth trapping on. */
			Logging.frameworkSubsystem?.error(
				"Could not archive colour for key [\(key, privacy: .public)]: \(error.localizedDescription, privacy: .public)"
			)
		}
	}

	func setUnsignedInteger(_ value: UInt, forKey key: String) {
		set(NSNumber(value: value), forKey: key)
	}

	func setShort(_ value: Int16, forKey key: String) {
		set(NSNumber(value: value), forKey: key)
	}

	func setUnsignedShort(_ value: UInt16, forKey key: String) {
		set(NSNumber(value: value), forKey: key)
	}

	func setLong(_ value: Int, forKey key: String) {
		set(NSNumber(value: value), forKey: key)
	}

	func setUnsignedLong(_ value: UInt, forKey key: String) {
		set(NSNumber(value: value), forKey: key)
	}

	func setLongLong(_ value: Int64, forKey key: String) {
		set(NSNumber(value: value), forKey: key)
	}

	func setUnsignedLongLong(_ value: UInt64, forKey key: String) {
		set(NSNumber(value: value), forKey: key)
	}

	func color(forKey key: String) -> NSColor? {
		guard let data = object(forKey: key) as? Data else { return nil }
		return try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data)
	}

	func unsignedInteger(forKey key: String) -> UInt {
		(object(forKey: key) as? NSNumber)?.uintValue ?? 0
	}

	func short(forKey key: String) -> Int16 {
		(object(forKey: key) as? NSNumber)?.int16Value ?? 0
	}

	func unsignedShort(forKey key: String) -> UInt16 {
		(object(forKey: key) as? NSNumber)?.uint16Value ?? 0
	}

	func long(forKey key: String) -> Int {
		(object(forKey: key) as? NSNumber)?.intValue ?? 0
	}

	func unsignedLong(forKey key: String) -> UInt {
		(object(forKey: key) as? NSNumber)?.uintValue ?? 0
	}

	func longLong(forKey key: String) -> Int64 {
		(object(forKey: key) as? NSNumber)?.int64Value ?? 0
	}

	func unsignedLongLong(forKey key: String) -> UInt64 {
		(object(forKey: key) as? NSNumber)?.uint64Value ?? 0
	}
}
