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
import Combine
import Synchronization

/// Computed, not stored: `TextualUserDefaults.container` is already the handle
/// the main actor keeps, and a second global reference to it would only be a
/// second name for the same object.
@MainActor
private var preferences: TextualUserDefaults {
	TextualUserDefaults.container
}

/** The keyword lists, cached so that a client snapshot does not re-read and
 re-filter two preference arrays. Main-actor state: the defaults observation
 that refreshes it, the preference panes that edit it and the snapshot that
 reads it are all there. */
private struct HighlightKeywords {
	var match: [String]?
	var exclude: [String]?
}

@MainActor
private var highlightKeywords = HighlightKeywords()

@MainActor
private var highlightKeywordObservation: Task<Void, Never>?

// MARK: - Identity

@MainActor
public extension TextualPreferences {
	class func populateDefaultNickname() {
		let nickname = "\(Preferences.Identity.nickname.defaultValue)\(randomNumber(100))"
		preferences.registerDefault(nickname, for: Preferences.Identity.nickname)
	}
}

// MARK: - Connection

@MainActor
public extension TextualPreferences {
	class func clientList() -> [[String: PropertyListValue]]? {
		Preferences.Connection.clientList.propertyListValue?.array?.compactMap(\.dictionary)
	}

	class func setClientList(_ value: [[String: PropertyListValue]]?) {
		Preferences.Connection.clientList.propertyListValue = value.map { list in
			.array(list.map(PropertyListValue.dictionary))
		}
	}
}

// MARK: - Logging

@MainActor
public extension TextualPreferences {
	class func logToDiskIsEnabled() -> Bool {
		Preferences.Logging.logToDisk.value && PathInfo.transcriptFolderURL != nil
	}
}

// MARK: - Highlights

@MainActor
public extension TextualPreferences {
	private class func loadKeywords(for key: PreferenceKey<[HighlightKeyword]>) -> [String] {
		key.value.map(\.string).filter { $0.isEmpty == false }
	}

	private class func reloadHighlightKeywords() {
		highlightKeywords.match = loadKeywords(for: Preferences.Highlights.matchKeywords)
		highlightKeywords.exclude = loadKeywords(for: Preferences.Highlights.excludeKeywords)
	}

	private class func cleanKeywords(for key: PreferenceKey<[HighlightKeyword]>) {
		key.value = loadKeywords(for: key)
			.sorted { $0.caseInsensitiveCompare($1) == .orderedAscending }
			.map(HighlightKeyword.init(string:))
	}

	class func cleanUpHighlightKeywords() {
		cleanKeywords(for: Preferences.Highlights.matchKeywords)
		cleanKeywords(for: Preferences.Highlights.excludeKeywords)
	}

	class func highlightMatchKeywords() -> [String]? {
		highlightKeywords.match
	}

	class func highlightExcludeKeywords() -> [String]? {
		highlightKeywords.exclude
	}
}

// MARK: - Application

@MainActor
public extension TextualPreferences {
	class func appNapEnabled() -> Bool {
		Preferences.Internals.appSleepDisabled.value == false
	}

	class func setAppNapEnabled(_ value: Bool) {
		Preferences.Internals.appSleepDisabled.value = (value == false)
	}

	class func registerPreferencesDictionaryVersion() {
		guard Preferences.Internals.dictionaryVersion.value < preferencesDictionaryVersion else {
			return
		}

		Preferences.Internals.dictionaryVersion.value = preferencesDictionaryVersion
	}

	class func defaultPreferences() -> [String: PropertyListValue] {
		preferences.registeredDefaults
	}

	class func registerDynamicDefaults() {
		populateDefaultNickname()
		registerPreferencesDictionaryVersion()
	}

	/** The registration domain is built from the key declarations rather than
	 read out of a plist, so a key that exists in the code always has a default
	 and a read of it cannot come back empty because a plist entry was renamed. */
	class func registerDefaults() {
		UserDefaults.standard.register(defaults: Preferences.registrationDomain(for: .standard).propertyListObject)
		preferences.register(defaults: Preferences.registrationDomain(for: .container).propertyListObject)
		registerDynamicDefaults()
	}

	class func initPreferences() {
		ApplicationInfo.incrementApplicationRunCount()
		registerDefaults()
		PathInfo.startUsingTranscriptFolderURL()
		/* Awaited on the main actor rather than sunk: the post can come from any
		 thread, and the handler writes main-actor state. No `object` filter --
		 a suite can be open through more than one handle, and a write through
		 any of them changes the keywords. */
		highlightKeywordObservation?.cancel()
		highlightKeywordObservation = Task { @MainActor in
			for await _ in NotificationCenter.default
				.publisher(for: UserDefaults.didChangeNotification)
				.bufferedValues
			{
				reloadHighlightKeywords()
			}
		}
		reloadHighlightKeywords()
	}
}
