/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2013 - 2018 Codeux Software, LLC & respective contributors.
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

import GlasstualPluginKit
import os
import SwiftUI
import Synchronization

/** The table the renderer looks tokens up in.

 Keyed by the lower-cased smiley: a smiley has always matched without regard to
 case, and what is looked up is a whole space-delimited token, so one dictionary
 hit answers what used to be a case-insensitive scan of the message per smiley —
 nine hundred and fifty-odd of them for every rendered line. */
private nonisolated struct SmileyConversionSnapshot: Sendable { // nonisolated: value
	static let empty = SmileyConversionSnapshot(conversionTable: [:])

	let conversionTable: [String: String]

	init(conversionTable: [String: String]) {
		var lowercased: [String: String] = [:]
		lowercased.reserveCapacity(conversionTable.count)

		/* Twenty-one smileys in the shipped table differ from another only in
		 case, and a case-insensitive match could never tell them apart either.
		 Ascending order makes the winner the greatest key, which is the one the
		 old descending scan reached first — and the same one on every launch. */
		for key in conversionTable.keys.sorted() {
			lowercased[key.lowercased()] = conversionTable[key]
		}

		self.conversionTable = lowercased
	}
}

/// The two preferences the conversion table is built from.
private nonisolated struct SmileyConverterSettings: Equatable, Sendable { // nonisolated: value
	let serviceEnabled: Bool
	let extraEmoticonsEnabled: Bool
}

/** Converts the smileys in a message body to emoji.

 Nonisolated because the transcript renderer calls `willRenderMessage` on its
 own queue. The conversion table is the only thing that crosses, and it crosses
 as a value behind a `Mutex`; everything the load and unload callbacks own —
 the host, the defaults observation, the settings last applied — is main-actor
 and stays there. */
@objc(TPISmileyConverter)
final nonisolated class SmileyConverterPlugin: NSObject, PluginMessageRendering { // nonisolated: guarded
	private static let logger = Logger(
		subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
		category: "Extension['Smiley Converter']"
	)

	private let conversions = Mutex(SmileyConversionSnapshot.empty)

	@MainActor private var host: PluginHostContext?
	@MainActor private var defaultsObservation: PluginDefaultsObservation?
	@MainActor private var effectiveSettings: SmileyConverterSettings?

	func willRenderMessage(_ event: PluginRenderEvent) -> String? {
		guard event.kind == .action || event.kind == .privateMessage else {
			return event.message
		}

		return Self.converting(event.message, using: conversions.withLock { $0 })
	}

	/** `message` with every smiley token replaced.

	 A pure function of the snapshot handed in, which is what lets the renderer
	 read the table once and leave the plugin object alone for the rest of the
	 work.

	 The old scan asked `NSMutableString` for every one of the table's smileys in
	 turn, then checked that what it found was surrounded by spaces. Only a whole
	 space-delimited token could ever pass that check, so splitting on the space
	 and looking the token up decides the same thing in one pass. */
	private static func converting(_ message: String, using snapshot: SmileyConversionSnapshot) -> String {
		guard snapshot.conversionTable.isEmpty == false else { return message }

		var result = ""
		result.reserveCapacity(message.count)
		var needsSeparator = false

		/* Empty subsequences are kept so a run of spaces survives the round
		 trip: one space is written back between every pair of tokens, which is
		 exactly what was split on. */
		for token in message.split(separator: " ", omittingEmptySubsequences: false) {
			if needsSeparator {
				result.append(" ")
			}
			needsSeparator = true
			result += replacement(for: token, using: snapshot) ?? String(token)
		}

		return result
	}

	/** The smiley `token` stands for, if it is one.

	 A link needs no special case: the whole token has to be a smiley, and a URL
	 that ends in `:+1:` is not one — it is a token of its own, and no address is
	 a table key. The check that used to be here dated from the scan that looked
	 inside the message. */
	private static func replacement(
		for token: Substring,
		using snapshot: SmileyConversionSnapshot
	) -> String? {
		guard token.isEmpty == false else { return nil }

		return snapshot.conversionTable[token.lowercased()]
	}
}

@MainActor
extension SmileyConverterPlugin: GlasstualPlugin, PluginPreferencesProviding {
	private var bundle: Bundle {
		Bundle(for: SmileyConverterPlugin.self)
	}

	private var defaults: UserDefaults {
		guard let host else {
			preconditionFailure("The plugin host must load Smiley Converter before it is used")
		}
		return host.defaults
	}

	func pluginLoaded(using host: PluginHostContext) {
		pluginWillUnload()
		self.host = host
		rebuildConversionSnapshot()
		defaultsObservation = PluginDefaultsObservation { [weak self] in
			self?.rebuildConversionSnapshot()
		}
	}

	func pluginWillUnload() {
		defaultsObservation = nil
		host = nil
		effectiveSettings = nil
		conversions.withLock { $0 = .empty }
	}

	var pluginPreferencesPane: PluginPreferencesPane? {
		guard let host else { return nil }
		return PluginPreferencesPane(title: String(localized: .BasicLanguage.preferencesPaneTitle)) { [weak self] in
			SmileyConverterPreferencesView(defaults: host.defaults) {
				self?.rebuildConversionSnapshot()
			}
		}
	}

	private func rebuildConversionSnapshot() {
		guard host != nil else { return }
		let settings = SmileyConverterSettings(
			serviceEnabled: defaults.bool(forKey: FirstPartyPluginPreferences.smileyServiceEnabled.name),
			extraEmoticonsEnabled: defaults.bool(forKey: FirstPartyPluginPreferences.smileyExtraEmoticons.name)
		)
		guard settings != effectiveSettings else { return }
		effectiveSettings = settings
		let newSnapshot = settings.serviceEnabled
			? buildConversionSnapshot(extraEmoticonsEnabled: settings.extraEmoticonsEnabled)
			: SmileyConversionSnapshot.empty

		conversions.withLock { snapshot in
			snapshot = newSnapshot
		}
	}

	private func buildConversionSnapshot(extraEmoticonsEnabled: Bool) -> SmileyConversionSnapshot {
		var table = loadConversionTable(named: "conversionTable")
		if extraEmoticonsEnabled {
			table.merge(loadConversionTable(named: "conversionTable2")) { _, new in new }
		}
		return SmileyConversionSnapshot(conversionTable: table)
	}

	private func loadConversionTable(named name: String) -> [String: String] {
		do {
			guard let url = bundle.url(forResource: name, withExtension: "plist") else {
				throw CocoaError(.fileNoSuchFile)
			}
			let data = try Data(contentsOf: url)
			guard let table = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String]
			else {
				throw CocoaError(.propertyListReadCorrupt)
			}
			return table
		} catch {
			Self.logger.error("Failed to load the conversion table named \(name, privacy: .public)")
			return [:]
		}
	}
}
