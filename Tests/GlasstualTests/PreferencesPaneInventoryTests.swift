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

	@Test("Every catalogued pane belongs to exactly one sub-page")
	func everyPaneBelongsToOneSubPage() {
		var seen: [String: Int] = [:]
		for section in PreferencesSession.sections() {
			for pane in section.subPages.flatMap(\.panes) {
				seen[pane.identifier, default: 0] += 1
			}
		}
		for pane in PreferencesPaneIdentifier.allCases {
			#expect(seen[pane.rawValue] == 1, "\(pane.rawValue) appears in \(seen[pane.rawValue] ?? 0) sub-pages")
		}
	}

	@Test("Every section has a title, a symbol and at least one sub-page")
	func sectionsAreComplete() {
		let sections = PreferencesSession.sections()
		#expect(Set(sections.map(\.identifier)) == Set(PreferencesSectionIdentifier.allCases))
		for section in sections {
			#expect(section.title.isEmpty == false)
			#expect(section.symbolName.isEmpty == false)
			#expect(section.subPages.isEmpty == false, "\(section.identifier.rawValue) shows nothing")
		}
	}

	@Test("A sub-page names something the window can show")
	func subPagesResolve() {
		for section in PreferencesSession.sections() {
			for subPage in section.subPages {
				#expect(
					PreferencesSession.paneExists(subPage.identifier),
					"unknown sub-page \(subPage.identifier)"
				)
				for pane in subPage.panes {
					#expect(PreferencesSession.paneExists(pane.identifier), "unknown pane \(pane.identifier)")
				}
			}
		}
	}

	@Test("The Advanced section keeps to five sub-pages")
	func advancedSectionIsGrouped() throws {
		let advanced = PreferencesSession.sections().first { $0.identifier == .advanced }
		let subPages = try #require(advanced?.subPages)
		#expect(subPages.count == PreferencesAdvancedGroup.allCases.count)
	}

	@Test("A pane identifier stored before the grouping still finds its sub-page")
	func storedPaneIdentifiersResolve() {
		let advanced = PreferencesSession.sections().first { $0.identifier == .advanced }
		let subPage = advanced?.subPages.first { $0.contains(PreferencesPaneIdentifier.hidden.rawValue) }
		#expect(subPage?.identifier == PreferencesAdvancedGroup.system.identifier)
	}

	@Test("An identifier nothing answers to is not shown")
	func unknownIdentifiersAreRejected() {
		#expect(PreferencesSession.paneExists("not-a-pane") == false)
		#expect(PreferencesSession.paneExists("plugin-9999") == false)
	}

	@Test("The main sections show one pane each")
	func mainSectionsHoldOnePane() {
		for section in PreferencesSession.sections() where section.identifier.pane != nil {
			#expect(section.subPages.count == 1, "\(section.identifier.rawValue) is not a single pane")
			#expect(section.subPages.first?.identifier == section.identifier.pane?.rawValue)
		}
	}

	@Test("Changing sections replaces the section and sub-page together")
	func selectionChangesAtomically() {
		let model = PreferencesPaneModel()
		model.sections = PreferencesSession.sections()
		var changes: [PreferencesSelection] = []
		model.onSelectionChange = { changes.append($0) }

		let selection = PreferencesSelection(
			sectionIdentifier: .advanced,
			subPageIdentifier: PreferencesAdvancedGroup.channels.identifier
		)

		#expect(model.select(selection))
		#expect(model.selection == selection)
		#expect(model.currentSection?.subPages.contains { $0.identifier == model.selection.subPageIdentifier } == true)
		#expect(changes == [selection])
	}

	@Test("An invalid section and sub-page pair is rejected without publishing")
	func invalidSelectionIsRejected() {
		let model = PreferencesPaneModel()
		model.sections = PreferencesSession.sections()
		let original = model.selection
		var changeCount = 0
		model.onSelectionChange = { _ in changeCount += 1 }

		let invalid = PreferencesSelection(
			sectionIdentifier: .general,
			subPageIdentifier: PreferencesAdvancedGroup.channels.identifier
		)

		#expect(model.select(invalid) == false)
		#expect(model.selection == original)
		#expect(changeCount == 0)
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

	@Test("A gated binding reads as off while its gate is closed")
	func gatedBinding() {
		let key = Preferences.Messages.showInlineMedia
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
