/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

@testable import Glasstual
import SwiftUI
import Testing

/// The Settings window is SwiftUI over the typed key store; these check that
/// the two halves still line up.
@MainActor
struct PreferencesPaneInventoryTests {
	@Test("Every catalogued pane declares the keys it binds")
	func everyPaneDeclaresItsKeys() {
		let declared = Set(PreferencesPaneKeys.keysByPane.keys)
		#expect(declared == Set(PreferencesPaneIdentifier.allCases))
	}

	/** A pane may only bind to a key the code declares: a name spelled straight
	 into a view would miss the registration domain, export and import. */
	@Test("Every key a pane binds to is one the key store declares")
	func boundKeysAreDeclared() {
		for (pane, keys) in PreferencesPaneKeys.keysByPane {
			for key in keys {
				#expect(
					Preferences.key(named: key.name) != nil,
					"\(pane.rawValue) binds to the undeclared key \(key.name)"
				)
			}
		}
	}

	@Test("Every catalogued pane has a sidebar entry")
	func everyPaneHasASidebarEntry() {
		let identifiers = Set(PreferencesController.sidebarEntries().map(\.identifier))
		for pane in PreferencesPaneIdentifier.allCases {
			#expect(identifiers.contains(pane.rawValue), "no sidebar entry for \(pane.rawValue)")
		}
	}

	@Test("A sidebar entry names a pane the window can show")
	func sidebarEntriesResolve() {
		for entry in PreferencesController.sidebarEntries() {
			#expect(PreferencesController.paneExists(entry.identifier), "unknown pane \(entry.identifier)")
		}
	}

	@Test("An identifier nothing answers to is not shown")
	func unknownIdentifiersAreRejected() {
		#expect(PreferencesController.paneExists("not-a-pane") == false)
		#expect(PreferencesController.paneExists("plugin-9999") == false)
	}

	@Test("Every sidebar entry carries a symbol and a title")
	func sidebarEntriesAreLabelled() {
		for entry in PreferencesController.sidebarEntries() {
			#expect(entry.title.isEmpty == false)
			#expect(entry.symbolName.isEmpty == false)
		}
	}
}

/// The bindings the panes hand to their controls read and write the key store.
@MainActor
struct PreferencesFacadeBindingTests {
	private let preferences = ObservablePreferences.shared

	@Test("Writing through a binding writes the key")
	func bindingRoundTrip() {
		let key = Preferences.Connection.confirmQuit
		defer { key.reset() }

		let binding = preferences.binding(for: key)
		let original = binding.wrappedValue
		binding.wrappedValue = original == false
		#expect(key.value == (original == false))
		#expect(binding.wrappedValue == key.value)
	}

	@Test("A binding that reloads part of the interface still writes first")
	func bindingRunsItsDidSetAfterWriting() {
		let key = Preferences.Messages.copyOnSelect
		defer { key.reset() }

		var observed: Bool?
		let binding = preferences.binding(for: key) { _ in observed = key.value }
		binding.wrappedValue = key.value == false
		#expect(observed == key.value)
	}

	@Test("An inverted binding stores the opposite of what it shows")
	func invertedBinding() {
		let key = Preferences.Internals.appSleepDisabled
		defer { key.reset() }

		let binding = preferences.invertedBinding(for: key)
		binding.wrappedValue = true
		#expect(key.value == false)
		binding.wrappedValue = false
		#expect(key.value == true)
	}

	@Test("A gated binding reads as off while its gate is closed")
	func gatedBinding() {
		let key = Preferences.InlineMedia.limitBasicsToFiles
		defer { key.reset() }

		key.value = true
		#expect(preferences.gatedBinding(for: key, enabledWhen: { false }).wrappedValue == false)
		#expect(preferences.gatedBinding(for: key, enabledWhen: { true }).wrappedValue)
	}

	@Test("A number field clamps to the range the pane declares")
	func numberFieldClamping() {
		let key = Preferences.Logging.scrollbackSaveLimit
		defer { key.reset() }

		let binding = preferences.numberFieldBinding(
			for: key,
			range: PreferencesValueValidation.scrollbackSaveRange
		)
		binding.wrappedValue = "1"
		#expect(key.value == 100)
		binding.wrappedValue = "999999"
		#expect(key.value == 50000)
	}

	@Test("Zero survives in the fields where it means 'no limit'")
	func numberFieldAllowsZero() {
		let key = Preferences.Logging.scrollbackVisibleLimit
		defer { key.reset() }

		let binding = preferences.numberFieldBinding(
			for: key,
			range: PreferencesValueValidation.scrollbackVisibleRange,
			allowingZero: true
		)
		binding.wrappedValue = "0"
		#expect(key.value == 0)
	}

	@Test("The port fields keep the range in order")
	func portFieldsClampAgainstEachOther() {
		let start = Preferences.FileTransfers.portRangeStart
		let end = Preferences.FileTransfers.portRangeEnd
		defer {
			start.reset()
			end.reset()
		}

		start.value = 2000
		end.value = 3000

		preferences.portFieldBinding(for: start, limitedBy: end, isLowerBound: true)
			.wrappedValue = "5000"
		#expect(start.value == 3000)

		preferences.portFieldBinding(for: end, limitedBy: start, isLowerBound: false)
			.wrappedValue = "1024"
		#expect(end.value == 3000)
	}

	@Test("A slider binding rounds onto the stored integer")
	func sliderBindingStoresIntegers() {
		let key = Preferences.Appearance.trackUserAwayStatusMaximumChannelSize
		defer { key.reset() }

		preferences.sliderBinding(for: key).wrappedValue = 279.6
		#expect(key.value == 280)
	}

	@Test("A colour well that has never been used reads as clear")
	func storedColorBindingStartsUnset() {
		let key = Preferences.Badges.serverListUnreadHighlight
		defer { key.reset() }

		key.reset()
		#expect(preferences.storedColorBinding(for: key).wrappedValue == .clear)

		preferences.storedColorBinding(for: key).wrappedValue = Color(nsColor: .systemBlue)
		#expect(preferences[stored: key] != nil)
	}
}
