@testable import Glasstual
import Testing

/// These raw values are archived with every log line and written into the
/// renderer's attribute dictionary. Renumbering a case silently reinterprets
/// every historic entry, so the numbers are pinned here as well as in source.
@Suite("Log line enumeration raw values")
struct LogLineTypeRawValueTests {
	@Test("Line type numbers are stable", arguments: [
		(TVCLogLineType.undefined, UInt(0)),
		(.action, 1),
		(.actionNoHighlight, 2),
		(.ctcp, 3),
		(.ctcpQuery, 4),
		(.ctcpReply, 5),
		(.dccFileTransfer, 6),
		(.debug, 7),
		(.invite, 8),
		(.join, 9),
		(.kick, 10),
		(.kill, 11),
		(.mode, 12),
		(.nick, 13),
		(.notice, 14),
		(.offTheRecordEncryptionStatus, 15),
		(.part, 16),
		(.privateMessage, 17),
		(.privateMessageNoHighlight, 18),
		(.quit, 19),
		(.topic, 20),
		(.website, 21),
	])
	func lineTypeRawValuesAreStable(type: TVCLogLineType, rawValue: UInt) {
		#expect(type.rawValue == rawValue)
		#expect(TVCLogLineType(rawValue: rawValue) == type)
	}

	@Test("Member type numbers are stable")
	func memberTypeRawValuesAreStable() {
		#expect(TVCLogLineMemberType.normal.rawValue == 0)
		#expect(TVCLogLineMemberType.localUser.rawValue == 1)
	}

	@Test("Delivery state numbers are stable")
	func deliveryStateRawValuesAreStable() {
		#expect(TVCLogLineDeliveryState.none.rawValue == 0)
		#expect(TVCLogLineDeliveryState.pending.rawValue == 1)
		#expect(TVCLogLineDeliveryState.delivered.rawValue == 2)
		#expect(TVCLogLineDeliveryState.failed.rawValue == 3)
	}

	/// A gap or a duplicate would mean a case was renumbered rather than
	/// appended.
	@Test("Nothing was inserted in the middle")
	func numbersAreContiguous() {
		let highest = TVCLogLineType.website.rawValue
		let resolved = (0 ... highest).compactMap { TVCLogLineType(rawValue: $0) }
		#expect(resolved.count == Int(highest) + 1)
	}
}
