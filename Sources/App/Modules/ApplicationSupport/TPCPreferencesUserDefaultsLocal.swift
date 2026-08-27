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

import Foundation

private enum PreferencesComparator: UInt {
	case equal = 0
	case anchorFront = 1
	case anchorBack = 2
}

public extension TextualUserDefaults {
	@objc(keyIsExcludedFromExportImport:)
	class func keyIsExcludedFromExportImport(_ defaultName: String) -> Bool {
		if matchesCachedKey(defaultName, resource: "KeysExcludedFromExport") {
			return true
		}

		return keyAppearsInPreferenceCatalog(defaultName) == false
	}

	@objc(keyAppearsInMasterList:)
	class func keyAppearsInPreferenceCatalog(_ defaultName: String) -> Bool {
		matchesCachedKey(defaultName, resource: "PreferenceKeyMasterList")
	}

	@objc(keyIsExcludedFromContainer:)
	class func keyIsExcludedFromContainer(_ defaultName: String) -> Bool {
		matchesCachedKey(defaultName, resource: "KeysExcludedFromContainer")
	}

	@objc(_migrateObject:forKey:)
	func migrateObject(_ value: Any?, forKey defaultName: String) {
		if Self.keyIsExcludedFromContainer(defaultName) {
			UserDefaults.standard.set(value, forKey: defaultName)
			return
		}

		setObjectWithoutNotification(value, forKey: defaultName)
	}

	private class func matchesCachedKey(_ defaultName: String, resource: String) -> Bool {
		guard
			let cachedValues = ResourceManager.dictionary(
				fromResources: resource,
				inDirectory: "Preferences"
			) as? [String: NSNumber]
		else {
			return false
		}

		for (cachedKey, cachedObject) in cachedValues {
			let comparator = PreferencesComparator(rawValue: cachedObject.uintValue) ?? .equal

			if key(defaultName, matches: cachedKey, using: comparator) {
				return true
			}
		}

		return false
	}

	private class func key(
		_ defaultName1: String,
		matches defaultName2: String,
		using comparator: PreferencesComparator
	) -> Bool {
		switch comparator {
		case .equal:
			defaultName1 == defaultName2
		case .anchorFront:
			defaultName1.hasPrefix(defaultName2)
		case .anchorBack:
			defaultName1.hasSuffix(defaultName2)
		}
	}
}
