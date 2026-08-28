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

	/** A text field holding a whole number, clamped on commit to the range the
	 nib's formatter enforced.

	 `allowingZero` keeps the two fields where zero means "no limit" from being
	 pulled up to the lower bound. */
	func numberFieldBinding(
		for key: PreferenceKey<UInt>,
		range: ClosedRange<Int>,
		allowingZero: Bool = false,
		didSet: @escaping () -> Void = {}
	) -> Binding<String> {
		Binding(
			get: { String(self[key]) },
			set: { newValue in
				let clamped = PreferencesValueValidation.clamped(
					Int(newValue.filter(\.isNumber)) ?? Int(self[key]),
					to: range,
					allowingZero: allowingZero
				)
				self[key] = UInt(clamped)
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

	/// The two file-transfer port fields, which also clamp against each other.
	func portFieldBinding(
		for key: PreferenceKey<UInt16>,
		limitedBy other: PreferenceKey<UInt16>?,
		isLowerBound: Bool
	) -> Binding<String> {
		Binding(
			get: { String(self[key]) },
			set: { newValue in
				var clamped = PreferencesValueValidation.clamped(
					Int(newValue.filter(\.isNumber)) ?? Int(self[key]),
					to: PreferencesValueValidation.fileTransferPortRange
				)
				if let other {
					clamped = isLowerBound ? min(clamped, Int(self[other])) : max(clamped, Int(self[other]))
				}
				self[key] = UInt16(clamped)
			}
		)
	}
}
