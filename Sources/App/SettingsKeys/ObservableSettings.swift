// Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
import Observation
import SwiftUI

/** A main-actor observable face on the typed key store, for the SwiftUI sheets.

 The keys are values rather than properties of an object, so there is nothing
 for `@Observable` to track per setting. What is tracked instead is one
 revision counter that every read touches and every defaults change bumps: a
 view that reads any setting through this store is re-evaluated when any
 setting changes. That is coarse, and right for a settings sheet, where the
 alternative — 170 published properties — buys precision nothing needs. */
@MainActor
@Observable
final class ObservableSettings {
	static let shared = ObservableSettings()

	/// Touched by every read and bumped by every change. Private because it is
	/// the mechanism, not part of the interface.
	private var revision: UInt = 0

	/// Cancels itself when it goes, which for this one is never: the store is a
	/// singleton the process holds for as long as it runs.
	@ObservationIgnored
	private let observations = NotificationSubscriptions()

	private init() {
		/* Two notifications, because the store posts one and the system posts
		 the other: `GlasstualUserDefaults` announces its own writes, while
		 `UserDefaults.didChangeNotification` covers a value another process wrote
		 into the same suite.

		 No `object` filter: a suite can be open through more than one
		 `UserDefaults` handle — the bindings controller has its own, and so
		 does anything writing off the main actor — and a write through any of
		 them is a change this has to see. */
		for name in [UserDefaults.didChangeNotification, .userDefaultsDidChange] {
			observations.observe(name) { [weak self] _ in
				self?.invalidate()
			}
		}
	}

	subscript<Value>(key: SettingsKey<Value>) -> Value {
		get {
			_ = revision
			return key.value
		}
		set {
			key.value = newValue
			reload(key)
		}
	}

	/// `nil` while nothing has been written — for the settings whose unset state
	/// means something, such as a colour well that follows the appearance until
	/// the user picks a colour.
	subscript<Value>(stored key: SettingsKey<Value>) -> Value? {
		get {
			_ = revision
			return key.storedValue
		}
		set {
			key.storedValue = newValue
			reload(key)
		}
	}

	func binding<Value>(for key: SettingsKey<Value>) -> Binding<Value> {
		Binding(
			get: { self[key] },
			set: { self[key] = $0 }
		)
	}

	/// Restores a key to its declared default.
	func reset(_ key: some AnySettingsKey) {
		key.reset()
		reload(key)
	}

	/** Answers the write: whatever the key that was just written obliges the
	 running application to redo.

	 Derived from the key rather than stated by the control that wrote it. A pane
	 that had to remember to name the reload itself was a pane that could name
	 the wrong one, and one of them did: the input-history reload was copied onto
	 two keyboard toggles and threw the history away whenever either was
	 flipped. */
	private func reload(_ key: some AnySettingsKey) {
		/* Every branch the connection code takes on a setting reads the
		 snapshot, so it is refreshed before anything else reacts to the write. */
		AppServices.chatSession?.refreshEnvironmentSettings()
		SettingsReload.perform(
			SettingsReload.action(forKeys: [key.name]).subtracting(.wholeSessionOnly)
		)
		/* The store drops a write that matches what is already stored, so it
		 posts nothing; a view that pushed the value still has to be told
		 that its read is stale. */
		invalidate()
	}

	/// Marks every reading view stale. Public because a few values -- the
	/// transcript folder bookmark, and everything a settings import writes --
	/// reach the store without going through this one, so nothing announces them.
	func invalidate() {
		revision &+= 1
	}
}
