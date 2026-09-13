/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import CocoaExtensions
import Foundation
import SwiftUI

extension Binding where Value == Bool {
	/** Reads as off and writes nothing while `isEnabled` is false.

	 A setting another setting has made irrelevant has one condition behind it,
	 so the switch cannot read as on while it is drawn disabled. */
	func gated(by isEnabled: Bool) -> Binding<Bool> {
		let stored = self

		return Binding(
			get: { isEnabled && stored.wrappedValue },
			set: { newValue in
				guard isEnabled else { return }
				stored.wrappedValue = newValue
			}
		)
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
	func numberFieldBinding(
		for key: PreferenceKey<UInt>,
		didSet: @escaping () -> Void = {}
	) -> Binding<String> {
		Binding(
			get: { String(self[key]) },
			set: { newValue in
				guard let value = UInt(newValue), key.accepts(value) else { return }
				self[key] = value
				didSet()
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
	func portFieldBinding(
		for key: PreferenceKey<UInt16>,
		limitedBy other: PreferenceKey<UInt16>?
	) -> Binding<String> {
		Binding(
			get: { String(self[key]) },
			set: { newValue in
				guard let value = UInt16(newValue) else { return }
				var others: [String: PropertyListValue] = [:]
				if let other {
					others[other.name] = other.propertyListValue
				}
				guard key.accepts(value, alongside: others) else { return }
				self[key] = value
			}
		)
	}
}
