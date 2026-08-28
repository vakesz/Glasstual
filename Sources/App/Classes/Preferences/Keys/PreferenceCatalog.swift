/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
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

/** Every declaration in one place, and everything derived from them: the
 registration domain, the catalogue the export and import filters consult, and
 the three plists that used to be hand-maintained beside the code.

 The plists are still shipped for the sake of tools that read them, but they are
 generated from these declarations — `PreferenceCatalogTests` fails when a
 checked-in copy drifts from what the code declares. */
public nonisolated extension Preferences {
	static let allKeys: [any AnyPreferenceKey] =
		Identity.all
			+ Connection.all
			+ Commands.all
			+ Messages.all
			+ Logging.all
			+ Appearance.all
			+ Theme.all
			+ Badges.all
			+ MainWindow.all
			+ Notifications.all
			+ Input.all
			+ Highlights.all
			+ FileTransfers.all
			+ Extensions.all
			+ Internals.all
			+ LinkSchemes.all
			+ InlineMedia.all

	static let allFamilies: [PreferenceKeyFamily] = Families.all

	private static let keysByName: [String: any AnyPreferenceKey] = {
		var result: [String: any AnyPreferenceKey] = [:]

		for key in allKeys {
			result[key.name] = key
		}

		return result
	}()

	/// The declaration for a stored name, if the name is one the code knows.
	static func key(named name: String) -> (any AnyPreferenceKey)? {
		keysByName[name]
	}

	/// The registration domain for one defaults database, built from the
	/// declarations rather than read from a plist.
	static func registrationDomain(for storage: PreferenceStorage) -> [String: Any] {
		var domain: [String: Any] = [:]

		for key in allKeys where key.storage == storage {
			guard let value = key.registeredDefault else {
				continue
			}

			domain[key.name] = value
		}

		return domain
	}

	/// Whether a stored name is one this application owns. Names made at
	/// runtime are matched by their family's pattern.
	static func isCatalogued(_ name: String) -> Bool {
		if let key = keysByName[name] {
			return key.isCatalogued
		}

		return allFamilies.contains { $0.isCatalogued && $0.matches(name) }
	}

	/// Whether a stored name is kept out of an exported configuration.
	static func isExcludedFromExport(_ name: String) -> Bool {
		if let key = keysByName[name], key.traits.contains(.excludedFromExport) {
			return true
		}

		if allFamilies.contains(where: { $0.traits.contains(.excludedFromExport) && $0.matches(name) }) {
			return true
		}

		// A name the catalogue does not cover is not ours to export.
		return isCatalogued(name) == false
	}

	/// Which defaults database a stored name belongs in. An unknown name goes to
	/// the container, which is where everything the application owns lives.
	static func storage(for name: String) -> PreferenceStorage {
		if let key = keysByName[name] {
			return key.storage
		}

		if let family = allFamilies.first(where: { $0.matches(name) }) {
			return family.storage
		}

		return .container
	}
}

// MARK: - Generated resources

public nonisolated extension Preferences {
	/// The generated equivalents of the checked-in plists, in the shape those
	/// files have: name to comparator for the catalogues, name to value for the
	/// registration domains.
	nonisolated enum GeneratedResources {
		public static var masterList: [String: Any] {
			catalogue { $0.isCatalogued } families: { $0.isCatalogued }
		}

		public static var keysExcludedFromContainer: [String: Any] {
			catalogue { $0.storage == .standard } families: { $0.storage == .standard }
		}

		public static var keysExcludedFromExport: [String: Any] {
			catalogue { $0.traits.contains(.excludedFromExport) } families: {
				$0.traits.contains(.excludedFromExport)
			}
		}

		public static var registeredUserDefaults: [String: Any] {
			Preferences.registrationDomain(for: .standard)
		}

		public static var registeredUserDefaultsInContainer: [String: Any] {
			Preferences.registrationDomain(for: .container)
		}

		private static func catalogue(
			_ includesKey: (any AnyPreferenceKey) -> Bool,
			families includesFamily: (PreferenceKeyFamily) -> Bool
		) -> [String: Any] {
			var result: [String: Any] = [:]

			for key in Preferences.allKeys where includesKey(key) {
				result[key.name] = NSNumber(value: PreferenceKeyFamily.Match.exact.rawValue)
			}

			for family in Preferences.allFamilies where includesFamily(family) {
				result[family.pattern] = NSNumber(value: family.match.rawValue)
			}

			return result
		}
	}
}
