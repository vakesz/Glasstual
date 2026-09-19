// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
import SwiftUI

/** The shapes a control needs that a stored value does not have: a slider wants
 a `Double`, a text field wants a `String` it may not have finished typing, and
 two switches read the opposite of what they store.

 Everything here still goes through the typed key, so no pane touches a raw
 defaults name. */
@MainActor
extension ObservableSettings {
	/// A checkbox whose label states the opposite of the stored key.
	func invertedBinding(for key: SettingsKey<Bool>) -> Binding<Bool> {
		Binding(
			get: { self[key] == false },
			set: { self[key] = ($0 == false) }
		)
	}

	/// A slider over a count the store keeps as a whole number.
	func sliderBinding(for key: SettingsKey<UInt>) -> Binding<Double> {
		Binding(
			get: { Double(self[key]) },
			set: { self[key] = UInt(max(0, $0.rounded())) }
		)
	}

	/// A committed number field. The key's own declaration decides which counts
	/// are valid, so a rejected entry leaves the saved value alone.
	func numberField(for key: SettingsKey<UInt>) -> SettingsFieldValue {
		SettingsFieldValue(
			text: { String(self[key]) },
			write: { newValue in
				guard let value = UInt(newValue.trimmingCharacters(in: .whitespaces)), key.accepts(value) else {
					return false
				}
				self[key] = value
				return true
			}
		)
	}

	/// A colour well over a key that always has a colour.
	func colorBinding(for key: SettingsKey<SettingsColor>) -> Binding<Color> {
		Binding(
			get: { Color(nsColor: self[key].color) },
			set: { self[key] = SettingsColor(NSColor($0)) ?? self[key] }
		)
	}

	/// A colour well over a key whose unset state means "let the appearance
	/// decide"; the well shows clear until the user picks something.
	func storedColorBinding(for key: SettingsKey<SettingsColor>) -> Binding<Color> {
		Binding(
			get: { self[stored: key].map { Color(nsColor: $0.color) } ?? .clear },
			set: { self[stored: key] = SettingsColor(NSColor($0)) }
		)
	}

	/// The same declaration-level port constraints an imported file goes
	/// through, including the ordered-pair rule the two ends of a range share.
	func portField(
		for key: SettingsKey<UInt16>,
		limitedBy other: SettingsKey<UInt16>?
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
