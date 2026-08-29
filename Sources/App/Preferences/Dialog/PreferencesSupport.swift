/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
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

import AppKit
import CocoaExtensions

/** The window has the fixed width a preference-style toolbar wants and grows
 or shrinks to whatever the selected pane needs, up to what the screen has. */
enum PreferencesLayout {
	static let windowWidth = 760.0
	static let windowMinimumHeight = 180.0
	static let windowScreenInset = 120.0
	/// What a grouped `Form` insets its own rows by, so the sub-page picker
	/// lines up with the content below it.
	static let contentInset = 20.0
}

/// The Settings window itself, which closes on Escape the way a settings
/// window is expected to.
final class PreferencesWindow: NSWindow {
	override func cancelOperation(_: Any?) {
		performClose(nil)
	}
}

struct PreferencesPaneDescriptor: Equatable {
	let identifier: PreferencesPaneIdentifier
	let symbolName: String
	let group: PreferencesPaneGroup
}

/// One pane: a toolbar section on its own, or one segment of a section that
/// holds several.
struct PreferencesPaneEntry: Equatable, Identifiable {
	let identifier: String
	let title: String
	let symbolName: String
	let group: PreferencesPaneGroup

	var id: String {
		identifier
	}
}

/// A toolbar item. The seven main panes are a section each; the add-on and
/// advanced panes are gathered behind one item apiece.
enum PreferencesSectionIdentifier: String, CaseIterable, Sendable {
	case general
	case behavior
	case notifications
	case highlights
	case interface
	case style
	case controls
	case addOns = "addons"
	case advanced

	var symbolName: String {
		switch self {
		case .general: "gearshape"
		case .behavior: "slider.horizontal.3"
		case .notifications: "bell"
		case .highlights: "text.magnifyingglass"
		case .interface: "macwindow"
		case .style: "paintbrush"
		case .controls: "keyboard"
		case .addOns: "puzzlepiece.extension"
		case .advanced: "gearshape.2"
		}
	}

	/// Which panes the section shows, `nil` for the two that gather a group.
	var pane: PreferencesPaneIdentifier? {
		switch self {
		case .general: .general
		case .behavior: .behavior
		case .notifications: .notifications
		case .highlights: .highlights
		case .interface: .interface
		case .style: .style
		case .controls: .controls
		case .addOns, .advanced: nil
		}
	}
}

/** One segment of a section's picker.

 A sub-page usually shows one pane; the Advanced section gathers eleven panes
 into five sub-pages, each drawn as one form whose sections carry the old pane
 names. */
struct PreferencesSubPage: Equatable, Identifiable {
	let identifier: String
	let title: String
	let panes: [PreferencesPaneEntry]

	var id: String {
		identifier
	}

	func contains(_ paneIdentifier: String) -> Bool {
		identifier == paneIdentifier || panes.contains { $0.identifier == paneIdentifier }
	}
}

/// How the sub-pages of the Advanced section are grouped, so no picker ever
/// carries more segments than fit across the window.
enum PreferencesAdvancedGroup: String, CaseIterable, Sendable {
	case connection
	case channels
	case identity
	case media
	case system

	var identifier: String {
		"advanced.\(rawValue)"
	}

	var panes: [PreferencesPaneIdentifier] {
		switch self {
		case .connection: [.compatibility, .floodControl, .incomingData]
		case .channels: [.channelManagement, .commandScope]
		case .identity: [.defaultIdentity, .defaultIRCopMessages]
		case .media: [.fileTransfers, .inlineMedia]
		case .system: [.logLocation, .hidden]
		}
	}
}

struct PreferencesSection: Equatable, Identifiable {
	let identifier: PreferencesSectionIdentifier
	let title: String
	let subPages: [PreferencesSubPage]

	var id: String {
		identifier.rawValue
	}

	var symbolName: String {
		identifier.symbolName
	}

	/// A picker only fits so many segments across a fixed-width window; past
	/// that the sub-pages are listed in a pop-up instead.
	static let maximumSegments = 5

	/* A segment is about this wide per character, plus the inset each one keeps
	 around its label. The estimate is deliberately generous: a row that would
	 be close to the edge falls back to the pop-up rather than truncating. */
	private static let segmentCharacterWidth = 7.5
	private static let segmentPadding = 28.0

	/** Whether the sub-pages fit a segmented row: few enough of them, and short
	 enough labels to lay out across the window without truncating. */
	var usesSegmentedPicker: Bool {
		guard subPages.count <= Self.maximumSegments else {
			return false
		}
		let characters = subPages.reduce(0) { $0 + $1.title.count }
		let width = Double(characters) * Self.segmentCharacterWidth
			+ Double(subPages.count) * Self.segmentPadding
		return width <= PreferencesLayout.windowWidth - 2 * PreferencesLayout.contentInset
	}
}

enum PreferencesPaneIdentifier: String, CaseIterable, Sendable {
	case addOns = "addons"
	case behavior
	case channelManagement
	case commandScope
	case compatibility
	case controls
	case defaultIRCopMessages
	case defaultIdentity
	case fileTransfers
	case floodControl
	case general
	case hidden
	case highlights
	case incomingData
	case inlineMedia
	case interface
	case logLocation
	case notifications
	case style
}

enum PreferencesPaneGroup: String, Sendable {
	case addOns = "addons"
	case advanced
	case main
}

enum PreferencesPaneCatalog {
	static let panes = [
		PreferencesPaneDescriptor(
			identifier: .general,
			symbolName: "gearshape",
			group: .main
		),
		PreferencesPaneDescriptor(
			identifier: .behavior,
			symbolName: "slider.horizontal.3",
			group: .main
		),
		PreferencesPaneDescriptor(
			identifier: .notifications,
			symbolName: "bell",
			group: .main
		),
		PreferencesPaneDescriptor(
			identifier: .highlights,
			symbolName: "text.magnifyingglass",
			group: .main
		),
		PreferencesPaneDescriptor(
			identifier: .interface,
			symbolName: "macwindow",
			group: .main
		),
		PreferencesPaneDescriptor(
			identifier: .style,
			symbolName: "paintbrush",
			group: .main
		),
		PreferencesPaneDescriptor(
			identifier: .controls,
			symbolName: "keyboard",
			group: .main
		),
		PreferencesPaneDescriptor(
			identifier: .addOns,
			symbolName: "puzzlepiece.extension",
			group: .addOns
		),
		PreferencesPaneDescriptor(
			identifier: .channelManagement,
			symbolName: "person.2",
			group: .advanced
		),
		PreferencesPaneDescriptor(
			identifier: .commandScope,
			symbolName: "terminal",
			group: .advanced
		),
		PreferencesPaneDescriptor(
			identifier: .compatibility,
			symbolName: "wrench.and.screwdriver",
			group: .advanced
		),
		PreferencesPaneDescriptor(
			identifier: .floodControl,
			symbolName: "timer",
			group: .advanced
		),
		PreferencesPaneDescriptor(
			identifier: .incomingData,
			symbolName: "arrow.down.circle",
			group: .advanced
		),
		PreferencesPaneDescriptor(
			identifier: .fileTransfers,
			symbolName: "arrow.down.app",
			group: .advanced
		),
		PreferencesPaneDescriptor(
			identifier: .inlineMedia,
			symbolName: "photo",
			group: .advanced
		),
		PreferencesPaneDescriptor(
			identifier: .logLocation,
			symbolName: "folder",
			group: .advanced
		),
		PreferencesPaneDescriptor(
			identifier: .defaultIdentity,
			symbolName: "person.crop.circle",
			group: .advanced
		),
		PreferencesPaneDescriptor(
			identifier: .defaultIRCopMessages,
			symbolName: "shield",
			group: .advanced
		),
		PreferencesPaneDescriptor(
			identifier: .hidden,
			symbolName: "eye.slash",
			group: .advanced
		),
	]

	static func descriptor(for identifier: String) -> PreferencesPaneDescriptor? {
		guard let identifier = PreferencesPaneIdentifier(rawValue: identifier) else { return nil }
		return panes.first { $0.identifier == identifier }
	}

	static func pluginIdentifier(at index: Int) -> String {
		"plugin-\(index)"
	}

	static func pluginIndex(from identifier: String) -> Int? {
		guard identifier.hasPrefix("plugin-") else { return nil }
		return Int(identifier.dropFirst(7))
	}
}

nonisolated enum PreferencesValueValidation { // nonisolated: value
	static let scrollbackSaveRange = 100 ... 50000
	static let scrollbackVisibleRange = 100 ... 15000
	static let inlineMediaWidthRange = 40 ... 2000
	static let inlineMediaHeightRange = 0 ... 6000
	static let fileTransferPortRange = 1024 ... 65535

	static func clamped(_ value: Int, to range: ClosedRange<Int>, allowingZero: Bool = false) -> Int {
		if allowingZero, value == 0 {
			return 0
		}
		return min(max(value, range.lowerBound), range.upperBound)
	}
}
