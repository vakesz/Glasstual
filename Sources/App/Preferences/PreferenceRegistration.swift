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
