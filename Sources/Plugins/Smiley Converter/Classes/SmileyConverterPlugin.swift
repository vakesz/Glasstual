/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
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

import AppKit

@objc(TPISmileyConverter)
final class SmileyConverterPlugin: NSObject, THOPluginProtocol, @unchecked Sendable {
	private static let enabledPreference = "Smiley Converter Extension -> Enable Service"
	private static let extraEmoticonsPreference = "Smiley Converter Extension -> Enable Extra Emoticons"

	@IBOutlet private var preferencesPane: NSView!

	private var conversionTable: [String: String] = [:]
	private var sortedSmileys: [String] = []

	private var bundle: Bundle {
		Bundle(for: SmileyConverterPlugin.self)
	}

	private var defaults: TPCPreferencesUserDefaults {
		TPCPreferencesUserDefaults.shared()
	}

	func pluginLoadedIntoMemory() {
		DispatchQueue.main.syncIfNeeded {
			self.bundle.loadNibNamed("TPISmileyConverter", owner: self, topLevelObjects: nil)
		}
		rebuildConversionTableIfEnabled()
	}

	private func rebuildConversionTableIfEnabled() {
		guard defaults.bool(forKey: Self.enabledPreference) else { return }
		buildConversionTable()
	}

	private func buildConversionTable() {
		var table = loadConversionTable(named: "conversionTable")
		if defaults.bool(forKey: Self.extraEmoticonsPreference) {
			table.merge(loadConversionTable(named: "conversionTable2")) { _, new in new }
		}
		conversionTable = table
		sortedSmileys = table.keys.sorted(by: >)
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

	@IBAction private func preferenceChanged(_: Any?) {
		conversionTable.removeAll()
		sortedSmileys.removeAll()
		rebuildConversionTableIfEnabled()
	}

	var pluginPreferencesPaneView: NSView {
		preferencesPane
	}

	var pluginPreferencesPaneMenuItemName: String {
		bundle.localizedString(forKey: "3kj-8f", value: nil, table: "BasicLanguage")
	}

	func willRenderMessage(
		_ newMessage: String,
		for _: TVCLogController,
		lineType: TVCLogLineType,
		memberType _: TVCLogLineMemberType
	) -> String? {
		guard defaults.bool(forKey: Self.enabledPreference),
		      lineType == .action || lineType == .privateMessage
		else { return newMessage }
		return convertToEmoji(newMessage)
	}

	private func convertToEmoji(_ string: String) -> String {
		let result = NSMutableString(string: string)
		for smiley in sortedSmileys {
			replace(smiley, in: result)
		}
		return result as String
	}

	private func replace(_ smiley: String, in string: NSMutableString) {
		var searchLocation = 0
		while searchLocation < string.length {
			let searchRange = NSRange(location: searchLocation, length: string.length - searchLocation)
			let match = string.range(of: smiley, options: .caseInsensitive, range: searchRange)
			guard match.location != NSNotFound else { return }

			let hasLeftBoundary = match.location == 0 || string.character(at: match.location - 1) == 0x20
			let rightLocation = NSMaxRange(match)
			let hasRightBoundary = rightLocation == string.length || string.character(at: rightLocation) == 0x20

			if hasLeftBoundary, hasRightBoundary, let emoji = conversionTable[smiley] {
				string.replaceCharacters(in: match, with: emoji)
				searchLocation = match.location + (emoji as NSString).length + 1
			} else {
				searchLocation = rightLocation + 1
			}
		}
	}
}

private extension DispatchQueue {
	func syncIfNeeded(_ work: () -> Void) {
		if Thread.isMainThread {
			work()
		} else {
			sync(execute: work)
		}
	}
}
