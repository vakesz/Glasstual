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

enum PreferencesSceneSelection: UInt, Sendable {
	case `default`
	case notifications
	case style
	case hiddenPreferences
}

/// State and actions owned by the SwiftUI Settings scene.
@MainActor
final class PreferencesSession {
	let model = PreferencesPaneModel()
	private lazy var notifications = NotificationSubscriptions()
	private var notificationsAreActive = false

	init() {
		prepareInitialState()
	}

	private func prepareInitialState() {
		model.destinations = PreferencesDestination.builtIn
		model.onSelectionChange = { [weak self] selection in
			self?.selectionChanged(to: selection)
		}
		model.refreshAll()
	}

	private func prepareNotifications() {
		guard notificationsAreActive == false else { return }
		notificationsAreActive = true
		notifications.observe(.ircClientCapabilitiesDidChange) { [weak self] _ in
			self?.model.refreshIRCv3Connections()
		}
		notifications.observe(.ircWorldClientListWasModified) { [weak self] _ in
			self?.model.refreshIRCv3Connections()
		}
	}

	func activate(selection: PreferencesSceneSelection) {
		prepareNotifications()
		// A menu request names a destination, including when it names the one
		// already selected. An earlier search must not hide that destination.
		model.searchText = ""
		model.destinations = PreferencesDestination.builtIn
		model.refreshAll()
		select(selection)
	}

	func deactivate() {
		notifications.cancelAll()
		notificationsAreActive = false
		TextualPreferences.performReloadAction([.highlightKeywords, .preferencesChanged])
	}

	/// Opens the row a caller asked for, or the one the window was left on.
	private func select(_ selection: PreferencesSceneSelection) {
		let requested: PreferencesSelection = switch selection {
		case .notifications: .notifications
		case .style: .style
		case .hiddenPreferences: .advanced
		case .default: remembered ?? .general
		}
		show(requested)
	}

	/// Where the window was left, as long as it still names a row.
	private var remembered: PreferencesSelection? {
		Preferences.Internals.selectedPreferencePane.storedValue
			.flatMap(PreferencesSelection.init(storedIdentifier:))
	}

	/** Shows a row and reports where the window ended up, even when that is the
	 row already showing: the first destination it opens on is not a change, but
	 it is still what the window has to remember. */
	private func show(_ selection: PreferencesSelection) {
		if model.select(selection) == false {
			selectionChanged(to: model.selection)
		}
	}

	// MARK: - Selection

	private func selectionChanged(to selection: PreferencesSelection) {
		Preferences.Internals.selectedPreferencePane.value = selection.storedIdentifier
		// The one pane whose content is read from outside the key store is
		// refreshed as it is opened rather than polled.
		if selection == .ircv3 {
			model.refreshIRCv3Connections()
		}
	}
}
