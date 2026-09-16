/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import CocoaExtensions
@testable import Glasstual
import SwiftUI
import Testing

/// The Settings window is SwiftUI over the typed key store; these check that
/// the two halves still line up.
@MainActor
@Suite("Settings pane inventory")
struct PreferencesPaneInventoryTests {
	@Test("Settings search finds localized control labels inside grouped destinations")
	func settingsSearchFindsControls() throws {
		let identity = try #require(SettingsDestination.builtIn.first { $0.selection == .identity })
		#expect(identity.matches(searchText: "  NICKNAME  "))
		#expect(identity.matches(searchText: "identity nickname"))
		#expect(identity.matches(searchText: "nickname unfindable-setting") == false)
		let controls = try #require(SettingsDestination.builtIn.first { $0.selection == .controls })
		#expect(controls.matches(searchText: "spell check"))
		#expect(SettingsDestination.builtIn.allSatisfy { $0.matches(searchText: " \n ") })
	}

	/** A pane may only bind to a key the code declares: a name spelled straight
	 into a view would miss the registration domain, export and import. */
	@Test("Every key a pane binds to is one the key store declares")
	func boundKeysAreDeclared() {
		for pane in SettingsPane.allCases {
			for entry in SettingsPaneKeys.keys(for: pane) {
				#expect(
					Preferences.key(named: entry.key.name) != nil,
					"\(pane.rawValue) binds to the undeclared key \(entry.key.name)"
				)
			}
		}
	}

	/** Nothing shows a raw defaults name to anyone: an import preview names the
	 settings it is about to change, so every key a pane binds carries the
	 words that pane puts beside its control. */
	@Test("Every key a pane binds to has a name the window can show")
	func boundKeysHaveDisplayNames() {
		for pane in SettingsPane.allCases {
			for entry in SettingsPaneKeys.keys(for: pane) {
				let displayName = SettingsPaneKeys.displayName(forKeyNamed: entry.key.name)
				#expect(
					displayName?.isEmpty == false,
					"\(pane.rawValue) shows \(entry.key.name) with no name of its own"
				)
				/* A defaults name is a path, not a phrase: "Preferences ->
				 Something" reaching an alert is exactly what this rules out. */
				#expect(
					displayName?.contains(" -> ") == false,
					"\(pane.rawValue) shows \(entry.key.name) under its defaults name"
				)
			}
		}
	}

	/// A key no pane shows has no name worth printing either, so the lookup
	/// says so rather than handing back the defaults spelling.
	@Test("A key no pane binds has no display name")
	func unboundKeysHaveNoDisplayName() {
		#expect(SettingsPaneKeys.displayName(forKeyNamed: "Not A Preference") == nil)
		#expect(
			SettingsPaneKeys.displayName(
				forKeyNamed: Preferences.Internals.selectedPreferencePane.name
			) == nil
		)
	}

	/// A pane no row draws is a pane nothing can reach, and a pane two rows
	/// draw is a setting shown in two places.
	@Test("Every catalogued pane is drawn by exactly one sidebar row")
	func everyPaneBelongsToOneRow() {
		var seen: [SettingsPane: Int] = [:]
		for destination in SettingsDestination.builtIn {
			for pane in destination.panes {
				seen[pane, default: 0] += 1
			}
		}
		for pane in SettingsPane.allCases {
			#expect(seen[pane] == 1, "\(pane.rawValue) is drawn by \(seen[pane] ?? 0) rows")
		}
	}

	@Test("Every sidebar row has a title, a symbol and something to draw")
	func rowsAreComplete() {
		for destination in SettingsDestination.builtIn {
			#expect(destination.title.isEmpty == false)
			#expect(destination.symbolName.isEmpty == false)
			#expect(
				destination.panes.isEmpty == false,
				"\(destination.selection.storedIdentifier) shows nothing"
			)
		}
	}

	/// The sidebar is one level deep, so a title appearing twice would give the
	/// user two rows that read the same.
	@Test("No two sidebar rows share a title or a selection")
	func rowsAreDistinct() {
		let destinations = SettingsDestination.builtIn
		#expect(Set(destinations.map(\.title)).count == destinations.count)
		#expect(Set(destinations.map(\.selection)).count == destinations.count)
		#expect(Set(destinations.map(\.selection.storedIdentifier)).count == destinations.count)
	}

	/// Every pane gathered with a neighbour wears its own heading, so a row
	/// that draws two of them says which settings are which.
	@Test("Every pane has a heading of its own")
	func panesHaveTitles() {
		for pane in SettingsPane.allCases {
			#expect(String(localized: pane.title).isEmpty == false, "\(pane.rawValue) has no heading")
		}
	}

	/// What the window stores has to name the same row when it is read back.
	@Test("A stored row identifier round-trips")
	func storedIdentifiersRoundTrip() {
		for destination in SettingsDestination.builtIn {
			let stored = destination.selection.storedIdentifier
			#expect(SettingsSelection(storedIdentifier: stored) == destination.selection)
		}
	}

	/** A name written before the sidebar was flattened points at a pane rather
	 than at a row, and still has to land on the row that draws it. */
	@Test("A pane identifier stored before the flattening finds its row")
	func storedPaneIdentifiersResolve() {
		#expect(SettingsSelection(storedIdentifier: SettingsPane.hidden.rawValue) == .advanced)
		#expect(SettingsSelection(storedIdentifier: SettingsPane.floodControl.rawValue) == .connection)
		#expect(
			SettingsSelection(storedIdentifier: SettingsPane.defaultIRCopMessages.rawValue) == .identity
		)
	}

	@Test("An identifier nothing answers to names no row")
	func unknownIdentifiersAreRejected() {
		#expect(SettingsSelection(storedIdentifier: "not-a-pane") == nil)
		// The Add-ons row and the rows its bundles supplied are gone.
		#expect(SettingsSelection(storedIdentifier: "addons") == nil)
		#expect(SettingsSelection(storedIdentifier: "plugin:com.example.addon") == nil)
		// The Behavior pane was folded into General and Controls.
		#expect(SettingsSelection(storedIdentifier: "behavior") == nil)
	}

	@Test("Every sidebar row is a destination the model accepts")
	func everyRowIsSelectable() {
		let model = SettingsModel()
		model.destinations = SettingsDestination.builtIn
		var changes: [SettingsSelection] = []
		model.onSelectionChange = { changes.append($0) }

		let expected = model.destinations.map(\.selection).filter { $0 != model.selection }
		for selection in expected {
			#expect(model.select(selection))
			#expect(model.selection == selection)
		}
		#expect(changes == expected)
	}

	@Test("A row the sidebar is not listing is rejected without publishing")
	func invalidSelectionIsRejected() {
		let model = SettingsModel()
		model.destinations = SettingsDestination.builtIn.filter { $0.selection != .fileTransfers }
		let original = model.selection
		var changeCount = 0
		model.onSelectionChange = { _ in changeCount += 1 }

		#expect(model.select(.fileTransfers) == false)
		#expect(model.selection == original)
		#expect(changeCount == 0)
	}
}

/// The bindings the panes hand to their controls read and write the key store.
@MainActor
@Suite("Settings pane bindings")
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

	/** Declared here rather than borrowed from the shipping catalogue: the
	 inverted binding is what is under test, and a `.standard`-storage key such
	 as `Preferences.Internals.appSleepDisabled` would write the developer's own
	 defaults domain, which the test scheme does not redirect. */
	private static let scratchInversionKey = PreferenceKey(
		"Tests -> Pane Bindings -> Inverted",
		default: false,
		traits: [.unregistered, .uncatalogued]
	)

	@Test("An inverted binding stores the opposite of what it shows")
	func invertedBinding() {
		let key = Self.scratchInversionKey
		defer { key.reset() }

		key.reset()

		let binding = preferences.invertedBinding(for: key)
		binding.wrappedValue = true
		#expect(key.value == false)
		binding.wrappedValue = false
		#expect(key.value == true)

		/* A fresh binding reads the same way round as the one that wrote. */
		#expect(preferences.invertedBinding(for: key).wrappedValue == false)
	}

	/// The switch another setting has made irrelevant reads as off and refuses
	/// the write, so a disabled row cannot leave a value behind it.
	@Test("A gated binding reads as off and writes nothing while its gate is closed")
	func gatedBinding() {
		let key = Preferences.Messages.showInlineMedia
		defer { key.reset() }

		key.value = true
		#expect(preferences.binding(for: key).gated(by: false).wrappedValue == false)
		#expect(preferences.binding(for: key).gated(by: true).wrappedValue)

		preferences.binding(for: key).gated(by: false).wrappedValue = false
		#expect(key.value)

		preferences.binding(for: key).gated(by: true).wrappedValue = false
		#expect(key.value == false)
	}

	/** The bounds the field enforces are the key's own, so an imported file
	 obeys the same ones. A count outside them leaves the saved value alone
	 rather than being silently clamped to the nearest legal one, which is what
	 the old field did and what made "50000" and "5000000" the same setting. */
	@Test("A number field holds counts to the bounds the key declares")
	func numberFieldEnforcesDeclaredBounds() {
		let key = Preferences.Logging.scrollbackSaveLimit
		defer { key.reset() }

		let field = preferences.numberField(for: key)
		#expect(field.write("20000"))
		#expect(key.value == 20000)
		#expect(field.write("1") == false)
		#expect(key.value == 20000)
		#expect(field.write("999999") == false)
		#expect(key.value == 20000)
		#expect(field.write("-7") == false)
		#expect(key.value == 20000)
		#expect(Preferences.Logging.scrollbackSaveRange == 100 ... 50000)
	}

	/// The store normalises what it accepts, so reading back something other
	/// than the typed text is not a refusal.
	@Test("A number entry the store normalises is not reported as rejected", arguments: ["0200", "+200", " 200"])
	func normalisedNumberEntryIsAccepted(_ input: String) {
		let key = Preferences.Logging.scrollbackSaveLimit
		let original = key.storedValue
		defer { key.storedValue = original }

		let field = preferences.numberField(for: key)
		var draft = SettingsFieldDraft()
		draft.edit(input)
		draft.commit(to: field)
		#expect(draft.wasRejected == false)
		#expect(field.text() == "200")
	}

	@Test("Zero survives in the fields where it means 'no limit'")
	func numberFieldAllowsZero() {
		let key = Preferences.Logging.scrollbackVisibleLimit
		defer { key.reset() }

		let field = preferences.numberField(for: key)
		#expect(field.write("0"))
		#expect(key.value == 0)
		#expect(field.write("50") == false)
		#expect(key.value == 0)
		#expect(field.write("15001") == false)
		#expect(key.value == 0)
		#expect(field.write("5000"))
		#expect(key.value == 5000)
		#expect(Preferences.Logging.scrollbackVisibleRange == 100 ... 15000)
	}

	@Test("The port fields reject conflicting bounds without changing the saved values")
	func portFieldsClampAgainstEachOther() {
		let start = Preferences.FileTransfers.portRangeStart
		let end = Preferences.FileTransfers.portRangeEnd
		defer {
			start.reset()
			end.reset()
		}

		start.value = 2000
		end.value = 3000

		#expect(preferences.portField(for: start, limitedBy: end).write("5000") == false)
		#expect(start.value == 2000)

		#expect(preferences.portField(for: end, limitedBy: start).write("1024") == false)
		#expect(end.value == 3000)
	}

	/// A sandboxed process cannot bind a privileged port at all, so the low end
	/// is a bound the field and an import both refuse to cross.
	@Test("The port fields refuse privileged and out-of-range ports")
	func portFieldsRefusePrivilegedPorts() {
		let start = Preferences.FileTransfers.portRangeStart
		let end = Preferences.FileTransfers.portRangeEnd
		defer {
			start.reset()
			end.reset()
		}

		start.value = 2000
		end.value = 65535

		#expect(preferences.portField(for: start, limitedBy: end).write("80") == false)
		#expect(start.value == 2000)
		#expect(preferences.portField(for: start, limitedBy: end).write("1024"))
		#expect(start.value == 1024)
		#expect(preferences.portField(for: end, limitedBy: start).write("70000") == false)
		#expect(end.value == 65535)
		#expect(Preferences.FileTransfers.portRange == 1024 ... 65535)
	}

	/** The Settings slider is a `Double`, so a stored count has to survive that
	 round trip and be renderable at the far end of it: `Int(Double(UInt.max))`
	 traps, which is why the label never converts to an `Int`. */
	@Test("The away-tracking limit stays inside what the slider can render")
	func awayTrackingLimitSurvivesTheSliderRoundTrip() {
		let key = Preferences.Appearance.trackUserAwayStatusMaximumChannelSize
		defer { key.reset() }

		#expect(Preferences.coerce(.integer(Int(Int32.max)), forKey: key.name) != nil)
		#expect(Preferences.coerce(.integer(Int(Int32.max) + 1), forKey: key.name) == nil)

		key.value = UInt(Int32.max)
		let rendered = preferences.sliderBinding(for: key).wrappedValue
		#expect(Int(exactly: rendered.rounded()) == Int(Int32.max))
		#expect(
			rendered.rounded().formatted(.number.precision(.fractionLength(0)))
				== Int(Int32.max).formatted(.number)
		)

		// The old bound let a file store a count whose Double round trip traps.
		GlasstualUserDefaults.container.set(NSNumber(value: UInt.max), forKey: key.name)
		let stored = preferences.sliderBinding(for: key).wrappedValue
		#expect(stored.rounded().formatted(.number.precision(.fractionLength(0))).isEmpty == false)
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
