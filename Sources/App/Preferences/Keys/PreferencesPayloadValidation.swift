/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import CocoaExtensions
import Foundation

/// Legacy plugin payload spelling belongs at the declaration boundary. These
/// checks prevent permissive plugin readers from silently dropping imported rules.
nonisolated enum PreferencesPayloadValidation { // nonisolated: value
	static func nicknameColors(_ value: PropertyListValue) -> Bool {
		guard let overrides = value.dictionary else { return false }
		return overrides.values.allSatisfy { value in
			if let data = value.data {
				return PreferenceColor.preferenceValue(from: data) != nil
			}
			guard let components = value.dictionary,
			      let color = NicknameColorComponents(stored: components.compactMapValues(\.double))
			else { return false }
			return [color.red, color.green, color.blue, color.alpha]
				.allSatisfy { $0.isFinite && (0 ... 1).contains($0) }
		}
	}

	static func chatFilters(_ value: PropertyListValue) -> Bool {
		guard let rules = value.array else { return false }
		var identifiers: Set<String> = []
		for rule in rules {
			guard let dictionary = rule.dictionary,
			      let identifier = dictionary["uniqueIdentifier"]?.string, !identifier.isEmpty,
			      identifiers.insert(identifier).inserted,
			      dictionary.allSatisfy({ validFilterField($0.key, $0.value) }) else { return false }
		}
		return true
	}

	private static func validFilterField(_ name: String, _ value: PropertyListValue) -> Bool {
		switch name {
		case "uniqueIdentifier", "filterAction", "filterForwardToDestination", "filterMatch", "filterNotes",
		     "filterSenderMatch", "filterTitle":
			return value.string != nil
		case "filterLimitedToChannelsIDs", "filterLimitedToClientsIDs", "filterEventsNumerics":
			return value.stringArray != nil
		case "filterIgnoreContent", "filterIgnoresOperators", "filterLimitedToMyself", "filterLogMatch",
		     "filterCommandPRIVMSG", "filterCommandPRIVMSG_ACTION", "filterCommandNOTICE":
			return value.boolean != nil
		case "filterLimitedToValue":
			return integer(value, in: 0 ... 3)
		case "filterAgeComparator":
			return integer(value, in: 0 ... 2)
		case "filterEvents":
			guard case let .integer(number) = value else { return false }
			return number >= 0 && number & ~8190 == 0
		case "filterAgeLimit", "filterActionFloodControlInterval":
			return integer(value, in: 0 ... Int.max)
		default:
			return false
		}
	}

	private static func integer(_ value: PropertyListValue, in range: ClosedRange<Int>) -> Bool {
		guard case let .integer(number) = value else { return false }
		return range.contains(number)
	}
}
