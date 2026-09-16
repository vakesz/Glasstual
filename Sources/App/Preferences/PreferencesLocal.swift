/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
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

import AppKit
import CocoaExtensions

/// Computed, not stored: `GlasstualUserDefaults.container` is already the handle
/// the main actor keeps, and a second global reference to it would only be a
/// second name for the same object.
@MainActor
private var preferences: GlasstualUserDefaults {
	GlasstualUserDefaults.container
}

// MARK: - Identity

@MainActor
extension TextualPreferences {
	static func populateDefaultNickname() {
		let nickname = "\(Preferences.Identity.nickname.defaultValue)\(randomNumber(100))"
		preferences.registerDefault(nickname, for: Preferences.Identity.nickname)
	}
}

// MARK: - Connection

@MainActor
extension TextualPreferences {
	static func clientList() -> [[String: PropertyListValue]]? {
		Preferences.Connection.clientList.propertyListValue?.array?.compactMap(\.dictionary)
	}

	static func setClientList(_ value: [[String: PropertyListValue]]?) {
		Preferences.Connection.clientList.propertyListValue = value.map { list in
			.array(list.map(PropertyListValue.dictionary))
		}
	}
}

// MARK: - Logging

@MainActor
extension TextualPreferences {
	static func logToDiskIsEnabled() -> Bool {
		Preferences.Logging.logToDisk.value && PathInfo.transcriptFolderURL != nil
	}
}

// MARK: - Highlights

@MainActor
extension TextualPreferences {
	/// Drops the entries that match nothing and sorts what is left, so the
	/// Settings list and the stored value stay in one order.
	private static func cleanKeywords(for key: PreferenceKey<[HighlightKeyword]>) {
		key.value = Preferences.Highlights.keywords(in: key.value)
			.sorted { $0.caseInsensitiveCompare($1) == .orderedAscending }
			.map(HighlightKeyword.init(string:))
	}

	static func cleanUpHighlightKeywords() {
		cleanKeywords(for: Preferences.Highlights.matchKeywords)
		cleanKeywords(for: Preferences.Highlights.excludeKeywords)
	}
}

// MARK: - Application

@MainActor
extension TextualPreferences {
	static func registerPreferencesDictionaryVersion() {
		guard Preferences.Internals.dictionaryVersion.value < preferencesDictionaryVersion else {
			return
		}

		Preferences.Internals.dictionaryVersion.value = preferencesDictionaryVersion
	}

	static func defaultPreferences() -> [String: PropertyListValue] {
		preferences.registeredDefaults
	}

	static func registerDynamicDefaults() {
		populateDefaultNickname()
		registerPreferencesDictionaryVersion()
	}

	/** The registration domain is built from the key declarations rather than
	 read out of a plist, so a key that exists in the code always has a default
	 and a read of it cannot come back empty because a plist entry was renamed. */
	static func registerDefaults() {
		UserDefaults.standard.register(defaults: Preferences.registrationDomain(for: .standard).propertyListObject)
		preferences.register(defaults: Preferences.registrationDomain(for: .container).propertyListObject)
		registerDynamicDefaults()
		PreferencesTransferStores.live.repairValuesDeclarationsRefuse(backupDirectory: PreferencesRecoveryStore.defaultDirectory)
	}

	static func initPreferences() {
		ApplicationInfo.incrementApplicationRunCount()
		registerDefaults()
		PathInfo.startUsingTranscriptFolderURL()
	}
}
