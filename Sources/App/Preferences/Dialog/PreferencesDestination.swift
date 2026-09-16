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

import Foundation

/** A block of related settings, drawn as one or more `Section`s inside the form
 of whichever sidebar row gathers it. */
enum PreferencesPane: String, CaseIterable, Sendable {
	case addOns = "addons"
	case channelManagement
	case commandScope
	case controls
	case defaultIRCopMessages
	case defaultIdentity
	case fileTransfers
	case floodControl
	case general
	case hidden
	case highlights
	case incomingData
	case interface
	case ircv3
	case logLocation
	case notifications
	case style

	/// The heading the pane wears when a row gathers it with its neighbours.
	var title: String {
		let resource: LocalizedStringResource = switch self {
		case .addOns: .Settings.addOns
		case .channelManagement: .Settings.channelManagement
		case .commandScope: .Settings.commandScope
		case .controls: .Settings.titleOfTheControls
		case .defaultIRCopMessages: .Settings.ircopMessages
		case .defaultIdentity: .Settings.defaultIdentity
		case .fileTransfers: .Settings.fileTransfers
		case .floodControl: .Settings.floodControl
		case .general: .Settings.titleOfTheGeneral
		case .hidden: .Settings.titleOfTheHidden
		case .highlights: .Settings.titleOfTheHighlights
		case .incomingData: .Settings.incomingData
		case .interface: .Settings.titleOfTheInterface
		case .ircv3: .Settings.titleOfTheIrcv3
		case .logLocation: .Settings.logLocation
		case .notifications: .Settings.titleOfTheNotifications
		case .style: .Settings.titleOfTheStyle
		}
		return String(localized: resource)
	}
}

/** Everything the Settings window can show: one sidebar row each.

 The sidebar is one level deep, so a destination is the whole of a selection —
 there is no second coordinate to keep in step with it. An add-on supplies its
 own row, named by the bundle identifier it keeps across launches so a
 remembered selection survives the add-on being absent. */
enum PreferencesSelection: Hashable, Sendable {
	case general
	case controls
	case interface
	case style
	case notifications
	case highlights
	case identity
	case commands
	case connection
	case ircv3
	case fileTransfers
	case advanced
	case addOns
	case plugin(bundleIdentifier: String)

	private static let pluginPrefix = "plugin:"

	/** How the selection is written to the key store, which has to outlive both
	 the window and, for an add-on, the bundle that supplied the row.

	 A row that shows a single pane is written under that pane's own name, so a
	 value stored before the sidebar was flattened still names it. */
	var storedIdentifier: String {
		switch self {
		case .general: PreferencesPane.general.rawValue
		case .controls: PreferencesPane.controls.rawValue
		case .interface: PreferencesPane.interface.rawValue
		case .style: PreferencesPane.style.rawValue
		case .notifications: PreferencesPane.notifications.rawValue
		case .highlights: PreferencesPane.highlights.rawValue
		case .identity: "identity"
		case .commands: "commands"
		case .connection: "connection"
		case .ircv3: PreferencesPane.ircv3.rawValue
		case .fileTransfers: PreferencesPane.fileTransfers.rawValue
		case .advanced: "advanced"
		case .addOns: PreferencesPane.addOns.rawValue
		case let .plugin(bundleIdentifier): Self.pluginPrefix + bundleIdentifier
		}
	}

	/** The row a stored identifier names.

	 A name written before the sidebar was flattened names one of the panes a
	 row now gathers, so it is resolved through the table as well and lands on
	 the row that shows it. */
	init?(storedIdentifier: String) {
		if storedIdentifier.hasPrefix(Self.pluginPrefix) {
			let bundleIdentifier = String(storedIdentifier.dropFirst(Self.pluginPrefix.count))
			guard bundleIdentifier.isEmpty == false else { return nil }
			self = .plugin(bundleIdentifier: bundleIdentifier)
			return
		}
		let rows = PreferencesDestination.builtIn
		if let row = rows.first(where: { $0.selection.storedIdentifier == storedIdentifier }) {
			self = row.selection
			return
		}
		guard let pane = PreferencesPane(rawValue: storedIdentifier),
		      let row = rows.first(where: { $0.panes.contains(pane) })
		else {
			return nil
		}
		self = row.selection
	}
}

/// One sidebar row: what it is called, the symbol beside it, and the panes its
/// form draws, in order.
struct PreferencesDestination: Identifiable, Equatable, Sendable {
	let selection: PreferencesSelection
	let symbolName: String
	let title: String
	let panes: [PreferencesPane]

	var id: PreferencesSelection {
		selection
	}

	/// Uses the same localized labels as the controls and import preview. The
	/// search never depends on internal defaults keys or English-only keywords.
	func matches(searchText: String) -> Bool {
		let terms = searchText.split(whereSeparator: \.isWhitespace)
		guard terms.isEmpty == false else { return true }
		let labels = [title] + panes.flatMap { pane in
			[pane.title] + (PreferencesPaneKeys.keysByPane[pane] ?? []).map {
				String(localized: $0.displayName)
			}
		}
		return terms.allSatisfy { term in
			labels.contains { $0.localizedStandardContains(String(term)) }
		}
	}

	init(
		_ selection: PreferencesSelection,
		symbol symbolName: String,
		title: LocalizedStringResource,
		panes: [PreferencesPane]
	) {
		self.init(selection, symbol: symbolName, title: String(localized: title), panes: panes)
	}

	init(_ selection: PreferencesSelection, symbol symbolName: String, title: String, panes: [PreferencesPane]) {
		self.selection = selection
		self.symbolName = symbolName
		self.title = title
		self.panes = panes
	}
}

extension PreferencesDestination {
	/** The Settings sidebar, in the order it lists its rows.

	 This is the one description of the window's structure: the titles, the
	 symbols, which settings each row shows, and which row a remembered
	 identifier names are all read from here. Add-on rows are appended to it as
	 the add-ons load. */
	static var builtIn: [PreferencesDestination] {
		[
			.init(.general, symbol: "gearshape", title: .Settings.titleOfTheGeneral, panes: [.general]),
			.init(.controls, symbol: "keyboard", title: .Settings.titleOfTheControls, panes: [.controls]),
			.init(.interface, symbol: "macwindow", title: .Settings.titleOfTheInterface, panes: [.interface]),
			.init(.style, symbol: "paintbrush", title: .Settings.titleOfTheStyle, panes: [.style]),
			.init(
				.notifications,
				symbol: "bell",
				title: .Settings.titleOfTheNotifications,
				panes: [.notifications]
			),
			.init(
				.highlights,
				symbol: "text.magnifyingglass",
				title: .Settings.titleOfTheHighlights,
				panes: [.highlights]
			),
			.init(
				.identity,
				symbol: "person.crop.circle",
				title: .Settings.titleOfTheIdentity,
				panes: [.defaultIdentity, .defaultIRCopMessages]
			),
			.init(
				.commands,
				symbol: "terminal",
				title: .Settings.titleOfTheCommands,
				panes: [.commandScope, .channelManagement]
			),
			.init(
				.connection,
				symbol: "antenna.radiowaves.left.and.right",
				title: .Settings.titleOfTheConnection,
				panes: [.floodControl, .incomingData]
			),
			.init(.ircv3, symbol: "network", title: .Settings.titleOfTheIrcv3, panes: [.ircv3]),
			.init(
				.fileTransfers,
				symbol: "arrow.up.arrow.down",
				title: .Settings.fileTransfers,
				panes: [.fileTransfers]
			),
			.init(
				.advanced,
				symbol: "gearshape.2",
				title: .Settings.titleOfTheAdvanced,
				panes: [.logLocation, .hidden]
			),
			.init(.addOns, symbol: "puzzlepiece.extension", title: .Settings.addOns, panes: [.addOns]),
		]
	}
}
