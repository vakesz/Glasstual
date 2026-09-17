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
 view that reads any preference through this store is re-evaluated when any
 preference changes. That is coarse, and right for a settings sheet, where the
 alternative — 170 published properties — buys precision nothing needs. */
@MainActor
@Observable
final class ObservablePreferences {
	static let shared = ObservablePreferences()

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
		for name in [UserDefaults.didChangeNotification, .glasstualUserDefaultsDidChange] {
			observations.observe(name) { [weak self] _ in
				self?.invalidate()
			}
		}
	}

	subscript<Value>(key: PreferenceKey<Value>) -> Value {
		get {
			_ = revision
			return key.value
		}
		set {
			key.value = newValue
			AppServices.clientDirectory?.refreshEnvironmentPreferences()
			/* The store drops a write that matches what is already stored, so it
			 posts nothing; a view that pushed the value still has to be told
			 that its read is stale. */
			invalidate()
		}
	}

	/// `nil` while nothing has been written — for the settings whose unset state
	/// means something, such as a colour well that follows the appearance until
	/// the user picks a colour.
	subscript<Value>(stored key: PreferenceKey<Value>) -> Value? {
		get {
			_ = revision
			return key.storedValue
		}
		set {
			key.storedValue = newValue
			AppServices.clientDirectory?.refreshEnvironmentPreferences()
			invalidate()
		}
	}

	func binding<Value>(for key: PreferenceKey<Value>) -> Binding<Value> {
		Binding(
			get: { self[key] },
			set: { self[key] = $0 }
		)
	}

	/// A binding that runs `didSet` after the write — for the controls whose
	/// change also has to reload part of the interface.
	func binding<Value>(
		for key: PreferenceKey<Value>,
		didSet: @escaping (Value) -> Void
	) -> Binding<Value> {
		Binding(
			get: { self[key] },
			set: { newValue in
				self[key] = newValue
				didSet(newValue)
			}
		)
	}

	/// Restores a key to its declared default.
	func reset(_ key: some AnyPreferenceKey) {
		key.reset()
		AppServices.clientDirectory?.refreshEnvironmentPreferences()
		invalidate()
	}

	/// Marks every reading view stale. Public because a few values (a folder
	/// bookmark, the channel font) are written outside the key store, so
	/// nothing announces them.
	func invalidate() {
		revision &+= 1
	}
}

/** The shapes a control needs that a stored value does not have: a slider wants
 a `Double`, a text field wants a `String` it may not have finished typing, and
 two switches read the opposite of what they store.

 Everything here still goes through the typed key, so no pane touches a raw
 defaults name. */
@MainActor
extension ObservablePreferences {
	/// A checkbox whose label states the opposite of the stored key.
	func invertedBinding(for key: PreferenceKey<Bool>) -> Binding<Bool> {
		Binding(
			get: { self[key] == false },
			set: { self[key] = ($0 == false) }
		)
	}

	/// A slider over a count the store keeps as a whole number.
	func sliderBinding(
		for key: PreferenceKey<UInt>,
		didSet: @escaping () -> Void = {}
	) -> Binding<Double> {
		Binding(
			get: { Double(self[key]) },
			set: { newValue in
				self[key] = UInt(max(0, newValue.rounded()))
				didSet()
			}
		)
	}

	/// A committed number field. The key's own declaration decides which counts
	/// are valid, so a rejected entry leaves the saved value alone.
	func numberField(
		for key: PreferenceKey<UInt>,
		didSet: @escaping () -> Void = {}
	) -> SettingsFieldValue {
		SettingsFieldValue(
			text: { String(self[key]) },
			write: { newValue in
				guard let value = UInt(newValue.trimmingCharacters(in: .whitespaces)), key.accepts(value) else {
					return false
				}
				self[key] = value
				didSet()
				return true
			}
		)
	}

	/// A colour well over a key that always has a colour.
	func colorBinding(
		for key: PreferenceKey<PreferenceColor>,
		didSet: @escaping () -> Void = {}
	) -> Binding<Color> {
		Binding(
			get: { Color(nsColor: self[key].color) },
			set: { newValue in
				self[key] = PreferenceColor(NSColor(newValue)) ?? self[key]
				didSet()
			}
		)
	}

	/// A colour well over a key whose unset state means "let the appearance
	/// decide"; the well shows clear until the user picks something.
	func storedColorBinding(
		for key: PreferenceKey<PreferenceColor>,
		didSet: @escaping () -> Void = {}
	) -> Binding<Color> {
		Binding(
			get: { self[stored: key].map { Color(nsColor: $0.color) } ?? .clear },
			set: { newValue in
				self[stored: key] = PreferenceColor(NSColor(newValue))
				didSet()
			}
		)
	}

	/// The same declaration-level port constraints an imported file goes
	/// through, including the ordered-pair rule the two ends of a range share.
	func portField(
		for key: PreferenceKey<UInt16>,
		limitedBy other: PreferenceKey<UInt16>?
	) -> SettingsFieldValue {
		SettingsFieldValue(
			text: { String(self[key]) },
			write: { newValue in
				guard let value = UInt16(newValue.trimmingCharacters(in: .whitespaces)) else { return false }
				var others: [String: PropertyListValue] = [:]
				if let other {
					others[other.name] = other.propertyListValue
				}
				guard key.accepts(value, alongside: others) else { return false }
				self[key] = value
				return true
			}
		)
	}
}
