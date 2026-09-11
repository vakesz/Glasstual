/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import CocoaExtensions
import Foundation
import Testing

/// Numbers the property-list machinery hands back, narrowed into the enum the
/// preference layer carries them in.
@Suite("Property list numbers")
struct PropertyListValueNumberTests {
	private func narrowed(_ object: Any) throws -> PropertyListValue {
		try #require(PropertyListValue(propertyList: object))
	}

	/** `intValue` reinterprets the bit pattern, so a count or an identifier
	 another process wrote above `Int.max` used to read back as a negative
	 number and pass a lower bound it is nowhere near. */
	@Test("An unsigned value larger than Int.max keeps its magnitude")
	func largeUnsignedValueKeepsItsMagnitude() throws {
		/* `Int.max + 1` is 2^63, which is also what `Double(Int.max)` rounds
		 to; the comparison below needs a value a double keeps above it. */
		let stored = UInt64.max

		let value = try narrowed(NSNumber(value: stored))

		#expect(value.integer == nil)
		if case let .double(magnitude) = value {
			#expect(magnitude > Double(Int.max))
		} else {
			Issue.record("A value above Int.max narrowed to \(value)")
		}
	}

	/// The same number as a file on disk holds it, which is the way it reaches
	/// a preference read.
	@Test("An unsigned value larger than Int.max survives the serializer")
	func largeUnsignedValueSurvivesSerialization() throws {
		let document: [String: Any] = ["count": NSNumber(value: UInt64.max)]
		let data = try PropertyListSerialization.data(fromPropertyList: document, format: .xml, options: 0)
		let read = try #require(
			PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
		)

		let object = try #require(read["count"])
		let value = try narrowed(object)

		if case let .double(magnitude) = value {
			#expect(magnitude > Double(Int.max))
		} else {
			Issue.record("A value above Int.max narrowed to \(value)")
		}
	}

	@Test("The integers that fit still narrow to integers")
	func representableIntegersStayIntegers() throws {
		for stored in [Int.min, -1, 0, 1, Int.max] {
			#expect(try narrowed(NSNumber(value: stored)).integer == stored)
		}
	}

	@Test("Booleans and doubles keep telling the truth about themselves")
	func booleansAndDoublesAreUnchanged() throws {
		#expect(try narrowed(NSNumber(value: true)).boolean == true)
		#expect(try narrowed(NSNumber(value: 1.5)).double == 1.5)
	}
}
