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

/** Everything the Settings window can show: one sidebar row each.

 The sidebar is one level deep, so a destination is the whole of a selection —
 there is no second coordinate to keep in step with it. */
enum SettingsSelection: Hashable, Sendable {
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
	case rules

	/** How the selection is written to the key store, which has to outlive the
	 window.

	 A row that shows a single pane is written under that pane's own name, so a
	 value stored before the sidebar was flattened still names it. */
	var storedIdentifier: String {
		switch self {
		case .general: SettingsPane.general.rawValue
		case .controls: SettingsPane.controls.rawValue
		case .interface: SettingsPane.interface.rawValue
		case .style: SettingsPane.style.rawValue
		case .notifications: SettingsPane.notifications.rawValue
		case .highlights: SettingsPane.highlights.rawValue
		case .identity: "identity"
		case .commands: "commands"
		case .connection: "connection"
		case .ircv3: SettingsPane.ircv3.rawValue
		case .fileTransfers: SettingsPane.fileTransfers.rawValue
		case .advanced: "advanced"
		case .rules: SettingsPane.rules.rawValue
		}
	}

	/** The row a stored identifier names.

	 A name written before the sidebar was flattened names one of the panes a
	 row now gathers, so it is resolved through the table as well and lands on
	 the row that shows it. */
	init?(storedIdentifier: String) {
		let rows = SettingsDestination.builtIn
		if let row = rows.first(where: { $0.selection.storedIdentifier == storedIdentifier }) {
			self = row.selection
			return
		}
		guard let pane = SettingsPane(rawValue: storedIdentifier),
		      let row = rows.first(where: { $0.panes.contains(pane) })
		else {
			return nil
		}
		self = row.selection
	}
}

/// One sidebar row: what it is called, the symbol beside it, and the panes its
/// form draws, in order.
struct SettingsDestination: Identifiable, Equatable, Sendable {
	let selection: SettingsSelection
	let symbolName: String
	let title: String
	let panes: [SettingsPane]

	var id: SettingsSelection {
		selection
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
		_ selection: SettingsSelection,
		symbol symbolName: String,
		title: LocalizedStringResource,
		panes: [SettingsPane]
	) {
		self.init(selection, symbol: symbolName, title: String(localized: title), panes: panes)
	}

	init(_ selection: SettingsSelection, symbol symbolName: String, title: String, panes: [SettingsPane]) {
		self.selection = selection
		self.symbolName = symbolName
		self.title = title
		self.panes = panes
	}
}

extension SettingsDestination {
	/** The Settings sidebar, in the order it lists its rows.

	 This is the one description of the window's structure: the titles, the
	 symbols, which settings each row shows, and which row a remembered
	 identifier names are all read from here. */
	static var builtIn: [SettingsDestination] {
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
				.rules,
				symbol: "line.3.horizontal.decrease.circle",
				title: .Settings.rules,
				panes: [.rules]
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
		]
	}
}
