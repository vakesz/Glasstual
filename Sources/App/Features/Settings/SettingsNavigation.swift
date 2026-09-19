// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** A block of related settings, drawn as one or more `Section`s inside the form
 of whichever sidebar row gathers it. */
enum SettingsPane: String, CaseIterable, Sendable {
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
	case rules
	case style

	/// The heading the pane wears when a row gathers it with its neighbours.
	var title: LocalizedStringResource {
		switch self {
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
		case .rules: .Settings.rules
		case .style: .Settings.titleOfTheStyle
		}
	}
}

/** One sidebar row: what it is called, the symbol beside it, and the panes its
 form draws, in order.

 The sidebar is one level deep and a pane is drawn by exactly one row, so a row
 is named by the first pane it shows rather than by a second enum that has to be
 kept in step with ``SettingsPane``. */
struct SettingsDestination: Identifiable, Equatable, Sendable {
	let symbolName: String
	let title: String
	let panes: [SettingsPane]
	/** How the row is written to the key store, which has to outlive the window.

	 A row that shows a single pane is written under that pane's own name, so a
	 value stored before the sidebar was flattened still names it; a row that
	 gathers several panes names itself, here, beside the panes it draws. */
	let storedIdentifier: String

	var id: SettingsPane {
		panes[0]
	}

	/// Uses the same localized labels as the controls and import preview. The
	/// search never depends on internal defaults keys or English-only keywords.
	func matches(searchText: String) -> Bool {
		let terms = searchText.split(whereSeparator: \.isWhitespace)
		guard terms.isEmpty == false else { return true }
		let labels = [title] + panes.flatMap { pane in
			[String(localized: pane.title)] + SettingsPaneKeys.keys(for: pane).map {
				String(localized: $0.displayName)
			}
		}
		return terms.allSatisfy { term in
			labels.contains { $0.localizedStandardContains(String(term)) }
		}
	}

	init(
		symbol symbolName: String,
		title: LocalizedStringResource,
		panes: [SettingsPane],
		storedAs storedIdentifier: String? = nil
	) {
		precondition(panes.isEmpty == false, "A row has to show something")
		self.symbolName = symbolName
		self.title = String(localized: title)
		self.panes = panes
		if let storedIdentifier {
			self.storedIdentifier = storedIdentifier
		} else {
			precondition(panes.count == 1, "A row that gathers several panes has to name itself")
			self.storedIdentifier = panes[0].rawValue
		}
	}

	/** The row a stored identifier names, or `nil` when nothing answers to it.

	 A name written before the sidebar was flattened names one of the panes a
	 row now gathers, so it is resolved through the table as well and lands on
	 the row that shows it. */
	static func named(_ storedIdentifier: String) -> SettingsDestination? {
		if let named = builtIn.first(where: { $0.storedIdentifier == storedIdentifier }) {
			return named
		}
		return SettingsPane(rawValue: storedIdentifier).flatMap { row(showing: $0) }
	}

	/// The row that draws `pane`, which every catalogued pane has exactly one of.
	static func row(showing pane: SettingsPane) -> SettingsDestination? {
		builtIn.first { $0.panes.contains(pane) }
	}
}

extension SettingsDestination {
	/** The Settings sidebar, in the order it lists its rows.

	 This is the one description of the window's structure: the titles, the
	 symbols, which settings each row shows, and which row a remembered
	 identifier names are all read from here. */
	static var builtIn: [SettingsDestination] {
		[
			.init(symbol: "gearshape", title: .Settings.titleOfTheGeneral, panes: [.general]),
			.init(symbol: "keyboard", title: .Settings.titleOfTheControls, panes: [.controls]),
			.init(symbol: "macwindow", title: .Settings.titleOfTheInterface, panes: [.interface]),
			.init(symbol: "paintbrush", title: .Settings.titleOfTheStyle, panes: [.style]),
			.init(symbol: "bell", title: .Settings.titleOfTheNotifications, panes: [.notifications]),
			.init(
				symbol: "text.magnifyingglass",
				title: .Settings.titleOfTheHighlights,
				panes: [.highlights]
			),
			.init(
				symbol: "line.3.horizontal.decrease.circle",
				title: .Settings.rules,
				panes: [.rules]
			),
			.init(
				symbol: "person.crop.circle",
				title: .Settings.titleOfTheIdentity,
				panes: [.defaultIdentity, .defaultIRCopMessages],
				storedAs: "identity"
			),
			.init(
				symbol: "terminal",
				title: .Settings.titleOfTheCommands,
				panes: [.commandScope, .channelManagement],
				storedAs: "commands"
			),
			.init(
				symbol: "antenna.radiowaves.left.and.right",
				title: .Settings.titleOfTheConnection,
				panes: [.floodControl, .incomingData],
				storedAs: "connection"
			),
			.init(symbol: "network", title: .Settings.titleOfTheIrcv3, panes: [.ircv3]),
			.init(symbol: "arrow.up.arrow.down", title: .Settings.fileTransfers, panes: [.fileTransfers]),
			.init(
				symbol: "gearshape.2",
				title: .Settings.titleOfTheAdvanced,
				panes: [.logLocation, .hidden],
				storedAs: "advanced"
			),
		]
	}
}
