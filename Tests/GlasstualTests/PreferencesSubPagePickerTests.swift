/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

@testable import Glasstual
import Testing

/** The Settings sub-page picker draws one segment per sub-page of the selected
 section. A selection with no segment to match is what SwiftUI reports as
 "the selection is invalid and does not have an associated tag". */
@MainActor
@Suite("Settings sub-page picker")
struct PreferencesSubPagePickerTests {
	private var sections: [PreferencesSection] {
		PreferencesSession.sections()
	}

	/// A pane no section lists is a pane the picker can never reach, and a
	/// selection holding it has no tag to match.
	@Test("Every pane the enumeration declares is listed by some section")
	func everyPaneIsListedBySomeSection() {
		let listed = Set(sections.flatMap { section in
			section.subPages.flatMap { $0.panes.map(\.identifier) }
		})

		for pane in PreferencesPaneIdentifier.allCases {
			#expect(listed.contains(pane.rawValue), "\(pane.rawValue) is listed by no section")
		}
	}

	/// The section the sidebar selects and the sub-page the picker draws with
	/// have to agree, `.ircv3` included: it is a section of its own whose only
	/// sub-page carries its own identifier.
	@Test("Each section's own sub-pages carry the identifier it selects")
	func eachSectionSelectsOneOfItsOwnSubPages() {
		let model = PreferencesPaneModel()
		model.sections = sections

		for section in sections {
			model.selectSection(section.identifier)

			let identifiers = section.subPages.map(\.identifier)
			#expect(identifiers.contains(model.selection.subPageIdentifier))
		}
	}

	/// The IRCv3 section holds exactly one sub-page, so no picker is drawn and
	/// its identifier is never handed to one as a selection.
	@Test("A section with a single sub-page draws no picker")
	func singleSubPageSectionDrawsNoPicker() throws {
		let section = try #require(sections.first { $0.identifier == .ircv3 })

		#expect(section.subPages.map(\.identifier) == [PreferencesPaneIdentifier.ircv3.rawValue])
		#expect(PreferencesSubPagePickerPolicy.drawsPicker(
			subPageIdentifiers: section.subPages.map(\.identifier),
			selection: PreferencesPaneIdentifier.ircv3.rawValue
		) == false)
	}

	@Test("A picker is drawn only for a selection one of its segments carries")
	func pickerIsDrawnOnlyForATaggedSelection() {
		let identifiers = PreferencesAdvancedGroup.allCases.map(\.identifier)

		#expect(PreferencesSubPagePickerPolicy.drawsPicker(
			subPageIdentifiers: identifiers,
			selection: PreferencesAdvancedGroup.connection.identifier
		))
		#expect(PreferencesSubPagePickerPolicy.drawsPicker(
			subPageIdentifiers: identifiers,
			selection: PreferencesPaneIdentifier.ircv3.rawValue
		) == false)
		#expect(PreferencesSubPagePickerPolicy.drawsPicker(
			subPageIdentifiers: [PreferencesPaneIdentifier.ircv3.rawValue],
			selection: PreferencesPaneIdentifier.ircv3.rawValue
		) == false)
	}
}
