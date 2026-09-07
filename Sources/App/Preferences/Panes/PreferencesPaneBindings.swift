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

/** The shapes a control needs that a stored value does not have: a slider wants
 a `Double`, a text field wants a `String` it may not have finished typing, and
 three checkboxes read the opposite of what they store.

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

	/// A checkbox that reads as off while `enabledWhen` is false, the way the
	/// nib's disabled checkboxes did, and still writes its own key.
	func gatedBinding(
		for key: PreferenceKey<Bool>,
		enabledWhen isEnabled: @escaping () -> Bool
	) -> Binding<Bool> {
		Binding(
			get: { isEnabled() && self[key] },
			set: { self[key] = $0 }
		)
	}

	func sliderBinding(
		for key: PreferenceKey<Double>,
		didSet: @escaping () -> Void = {}
	) -> Binding<Double> {
		Binding(
			get: { self[key] },
			set: { newValue in
				self[key] = newValue
				didSet()
			}
		)
	}

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
				guard let value = UInt(newValue), let object = value.preferenceObject,
				      let plist = PropertyListValue(propertyList: object), key.coerce(plist) != nil else { return }
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

	/// The same declaration-level port constraints used by configuration import,
	/// including the ordered-pair rule the two ends of a range share.
	func portFieldBinding(
		for key: PreferenceKey<UInt16>,
		limitedBy other: PreferenceKey<UInt16>?
	) -> Binding<String> {
		Binding(
			get: { String(self[key]) },
			set: { newValue in
				guard let value = UInt16(newValue), let object = value.preferenceObject,
				      let plist = PropertyListValue(propertyList: object) else { return }
				var values: [String: PropertyListValue] = [:]
				if let other {
					values[other.name] = other.propertyListValue
				}
				guard key.isValid(plist, in: values) else { return }
				self[key] = value
			}
		)
	}
}
