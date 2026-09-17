// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import CocoaExtensions

/** The defaults the application registers before anything reads a preference.

 The registration domain is built from the key declarations rather than read out
 of a plist, so a key that exists in the code always has a default, and a read
 cannot come back empty because a plist entry was renamed. */
@MainActor
enum PreferenceRegistration {
	/// What the application does with its preferences at launch, in order.
	static func prepareForLaunch() {
		ApplicationInfo.incrementApplicationRunCount()
		registerDefaults()
		ApplicationPaths.startUsingTranscriptFolderURL()
	}

	static func registerDefaults() {
		UserDefaults.standard.register(
			defaults: Preferences.registrationDomain(for: .standard).propertyListObject
		)
		GlasstualUserDefaults.container.register(
			defaults: Preferences.registrationDomain(for: .container).propertyListObject
		)
		registerDynamicDefaults()
		PreferencesTransferStores.live.repairValuesDeclarationsRefuse(
			backupDirectory: PreferencesRecoveryStore.defaultDirectory
		)
	}

	/// Everything registered, which is what a removed key is checked against.
	static var registeredDefaults: [String: PropertyListValue] {
		GlasstualUserDefaults.container.registeredDefaults
	}

	/** The two defaults that are made rather than declared: a starting nickname
	 with a number nobody else picked, and the dictionary version this build
	 writes once it is the newer one. */
	private static func registerDynamicDefaults() {
		let nickname = "\(Preferences.Identity.nickname.defaultValue)\(UInt32.random(in: 0 ..< 100))"
		GlasstualUserDefaults.container.registerDefault(nickname, for: Preferences.Identity.nickname)

		let current = Preferences.Internals.currentDictionaryVersion
		guard Preferences.Internals.dictionaryVersion.value < current else { return }

		Preferences.Internals.dictionaryVersion.value = current
	}
}
