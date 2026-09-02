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

private nonisolated struct SmileyConversionSnapshot: Sendable { // nonisolated: value
	static let empty = SmileyConversionSnapshot(conversionTable: [:])

	let conversionTable: [String: String]
	let sortedSmileys: [String]

	init(conversionTable: [String: String]) {
		self.conversionTable = conversionTable
		sortedSmileys = conversionTable.keys.sorted(by: >)
	}
}

@objc(TPISmileyConverter)
final class SmileyConverterPlugin: NSObject, GlasstualPlugin, PluginMessageRendering,
	PluginPreferencesProviding
{
	private static let logger = Logger(
		subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
		category: "Extension['Smiley Converter']"
	)

	private let conversionSnapshot = Mutex(SmileyConversionSnapshot.empty)
	private var host: PluginHostContext?

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
		self.host = host
		rebuildConversionSnapshot()
	}

	/** Rebuilds the conversion table from the preferences as they stand now.

	 `@objc` because this plugin is loaded from its bundle at runtime: nothing
	 that links against Glasstual can see this Swift type, so a selector is the
	 only way into it. `PluginRuntimeTests` uses that to drive a preference
	 reload against a live renderer. The preferences pane, which is inside the
	 bundle, calls it directly. */
	@objc private func rebuildConversionSnapshot() {
		let newSnapshot = defaults.bool(forKey: SmileyConverterPreferenceKey.serviceEnabled)
			? buildConversionSnapshot()
			: SmileyConversionSnapshot.empty

		conversionSnapshot.withLock { snapshot in
			snapshot = newSnapshot
		}
	}

	private func buildConversionSnapshot() -> SmileyConversionSnapshot {
		var table = loadConversionTable(named: "conversionTable")
		if defaults.bool(forKey: SmileyConverterPreferenceKey.extraEmoticonsEnabled) {
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
			assertionFailure("Failed to load conversion table named \(name)")
			return [:]
		}
	}

	var pluginPreferencesPane: PluginPreferencesPane? {
		guard let host else { return nil }
		return PluginPreferencesPane(title: String(localized: .BasicLanguage.preferencesPaneTitle)) { [weak self] in
			SmileyConverterPreferencesView(defaults: host.defaults) {
				self?.rebuildConversionSnapshot()
			}
		}
	}

	/** Called from the message renderer's background queue. The conversion table
	 is the only state it reads, and that table is empty whenever the preference
	 is off, so there is nothing to consult on the main actor. */
	nonisolated func willRenderMessage(_ event: PluginRenderEvent) -> String? { // nonisolated: pure
		guard event.kind == .action || event.kind == .privateMessage else {
			return event.message
		}
		return convertToEmoji(event.message)
	}

	private nonisolated func convertToEmoji(_ string: String) -> String { // nonisolated: pure
		let snapshot = conversionSnapshot.withLock { $0 }
		let result = NSMutableString(string: string)
		for smiley in snapshot.sortedSmileys {
			replace(smiley, in: result, using: snapshot)
		}
		return result as String
	}

	private nonisolated func replace( // nonisolated: pure
		_ smiley: String,
		in string: NSMutableString,
		using snapshot: SmileyConversionSnapshot
	) {
		var searchLocation = 0
		while searchLocation < string.length {
			let searchRange = NSRange(location: searchLocation, length: string.length - searchLocation)
			let match = string.range(of: smiley, options: .caseInsensitive, range: searchRange)
			guard match.location != NSNotFound else { return }

			let hasLeftBoundary = match.location == 0 || string.character(at: match.location - 1) == 0x20
			let rightLocation = NSMaxRange(match)
			let hasRightBoundary = rightLocation == string.length || string.character(at: rightLocation) == 0x20

			if hasLeftBoundary, hasRightBoundary, let emoji = snapshot.conversionTable[smiley] {
				string.replaceCharacters(in: match, with: emoji)
				searchLocation = match.location + (emoji as NSString).length + 1
			} else {
				searchLocation = rightLocation + 1
			}
		}
	}
}
