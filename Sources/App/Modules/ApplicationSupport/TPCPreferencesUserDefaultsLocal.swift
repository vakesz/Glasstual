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

import Foundation

private enum PreferencesComparator: UInt {
	case equal = 0
	case anchorFront = 1
	case anchorBack = 2
}

public extension TPCPreferencesUserDefaults {
	@objc(keyIsExcludedFromExportImport:)
	class func keyIsExcludedFromExportImport(_ defaultName: String) -> Bool {
		if matchesCachedKey(defaultName, resource: "KeysExcludedFromExport") {
			return true
		}

		return keyAppearsInMasterList(defaultName) == false
	}

	@objc(keyAppearsInMasterList:)
	class func keyAppearsInMasterList(_ defaultName: String) -> Bool {
		matchesCachedKey(defaultName, resource: "PreferenceKeyMasterList")
	}

	@objc(keyIsExcludedFromContainer:)
	class func keyIsExcludedFromContainer(_ defaultName: String) -> Bool {
		matchesCachedKey(defaultName, resource: "KeysExcludedFromContainer")
	}

	@objc(_migrateObject:forKey:)
	func _migrateObject(_ value: Any?, forKey defaultName: String) {
		if Self.keyIsExcludedFromContainer(defaultName) {
			UserDefaults.standard.set(value, forKey: defaultName)
			return
		}

		_setObject(value, forKey: defaultName)
	}

	private class func matchesCachedKey(_ defaultName: String, resource: String) -> Bool {
		guard
			let cachedValues = TPCResourceManager.dictionary(
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
