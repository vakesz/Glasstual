// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Observation
import SwiftUI

enum SettingsSceneSelection: UInt, Sendable {
	case `default`
	case notifications
	case style
	case hiddenPreferences
}

/// State and actions owned by the SwiftUI Settings scene.
@MainActor
final class SettingsSession {
	let model = SettingsModel()
	private lazy var notifications = NotificationSubscriptions()
	private var notificationsAreActive = false

	init() {
		prepareInitialState()
	}

	private func prepareInitialState() {
		model.destinations = SettingsDestination.builtIn
		model.onSelectionChange = { [weak self] selection in
			self?.selectionChanged(to: selection)
		}
		model.refreshAll()
	}

	private func prepareNotifications() {
		guard notificationsAreActive == false else { return }
		notificationsAreActive = true
		notifications.observe(.clientCapabilitiesDidChange) { [weak self] _ in
			self?.model.refreshIRCv3Connections()
		}
		notifications.observe(.clientDirectoryClientListWasModified) { [weak self] _ in
			self?.model.refreshIRCv3Connections()
		}
	}

	func activate(selection: SettingsSceneSelection) {
		prepareNotifications()
		// A menu request names a destination, including when it names the one
		// already selected. An earlier search must not hide that destination.
		model.searchText = ""
		model.destinations = SettingsDestination.builtIn
		model.refreshAll()
		select(selection)
	}

	func deactivate() {
		notifications.cancelAll()
		notificationsAreActive = false
		PreferenceReload.perform([.highlightKeywords, .preferencesChanged])
	}

	/// Opens the row a caller asked for, or the one the window was left on.
	private func select(_ selection: SettingsSceneSelection) {
		let requested: SettingsSelection = switch selection {
		case .notifications: .notifications
		case .style: .style
		case .hiddenPreferences: .advanced
		case .default: remembered ?? .general
		}
		show(requested)
	}

	/// Where the window was left, as long as it still names a row.
	private var remembered: SettingsSelection? {
		Preferences.Internals.selectedPreferencePane.storedValue
			.flatMap(SettingsSelection.init(storedIdentifier:))
	}

	/** Shows a row and reports where the window ended up, even when that is the
	 row already showing: the first destination it opens on is not a change, but
	 it is still what the window has to remember. */
	private func show(_ selection: SettingsSelection) {
		if model.select(selection) == false {
			selectionChanged(to: model.selection)
		}
	}

	// MARK: - Selection

	private func selectionChanged(to selection: SettingsSelection) {
		Preferences.Internals.selectedPreferencePane.value = selection.storedIdentifier
		// The one pane whose content is read from outside the key store is
		// refreshed as it is opened rather than polled.
		if selection == .ircv3 {
			model.refreshIRCv3Connections()
		}
	}
}

@MainActor
@Observable
final class SettingsSceneRequest {
	private(set) var selection: SettingsSceneSelection = .default
	private(set) var revision = 0

	func open(_ selection: SettingsSceneSelection) {
		self.selection = selection
		revision &+= 1
	}
}

/// The `Settings` scene, as a named type like every other application scene.
struct SettingsScene: Scene {
	let request: SettingsSceneRequest

	var body: some Scene {
		Settings {
			SettingsSceneRoot(request: request)
		}
		/* The pages declare their own minimum, and the window used to let
		 itself be dragged narrower than any of them could lay out. */
		.windowResizability(.contentMinSize)
	}
}

struct SettingsSceneRoot: View {
	let request: SettingsSceneRequest
	@State private var session = SettingsSession()

	var body: some View {
		/* No frame here: `SettingsRootView` declares the window's minimum,
		 ideal and maximum size, and a second frame would only fight it. */
		SettingsRootView(model: session.model)
			.onAppear {
				session.activate(selection: request.selection)
			}
			.onChange(of: request.revision) {
				session.activate(selection: request.selection)
			}
			.onDisappear {
				session.deactivate()
			}
	}
}
