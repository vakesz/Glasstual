@testable import Glasstual
import XCTest

@MainActor
final class IRCValueModelTests: XCTestCase {
	func testNativeEnumRawValuesRemainStable() {
		XCTAssertEqual(IRCAddressBookEntryType.ignore.rawValue, 0)
		XCTAssertEqual(IRCAddressBookEntryType.userTracking.rawValue, 1)
		XCTAssertEqual(IRCAddressBookEntryType.mixed.rawValue, 2)

		XCTAssertEqual(IRCAddressBookUserTrackingStatus.unknown.rawValue, 0)
		XCTAssertEqual(IRCAddressBookUserTrackingStatus.signedOff.rawValue, 1)
		XCTAssertEqual(IRCAddressBookUserTrackingStatus.signedOn.rawValue, 2)
		XCTAssertEqual(IRCAddressBookUserTrackingStatus.available.rawValue, 3)
		XCTAssertEqual(IRCAddressBookUserTrackingStatus.notAvailable.rawValue, 4)
		XCTAssertEqual(IRCAddressBookUserTrackingStatus.away.rawValue, 5)
		XCTAssertEqual(IRCAddressBookUserTrackingStatus.notAway.rawValue, 6)

		XCTAssertEqual(IRCISupportInfoListType.ban.rawValue, 0)
		XCTAssertEqual(IRCISupportInfoListType.banException.rawValue, 1)
		XCTAssertEqual(IRCISupportInfoListType.inviteException.rawValue, 2)
		XCTAssertEqual(IRCISupportInfoListType.quiet.rawValue, 3)

		XCTAssertEqual(IRCISupportInfoCaseMapping.rfc1459.rawValue, 0)
		XCTAssertEqual(IRCISupportInfoCaseMapping.strictRFC1459.rawValue, 1)
		XCTAssertEqual(IRCISupportInfoCaseMapping.ascii.rawValue, 2)

		XCTAssertEqual(IRCNetworkRegistration.none.rawValue, 0)
		XCTAssertEqual(IRCNetworkRegistration.optional.rawValue, 1)
		XCTAssertEqual(IRCNetworkRegistration.required.rawValue, 2)
	}

	func testProtocolLimitsRemainStable() {
		XCTAssertEqual(IRCProtocolLimits.maximumBodyLength, 510)
		XCTAssertEqual(IRCProtocolLimits.maximumNicknameLength, 50)
		XCTAssertEqual(IRCProtocolLimits.maximumUsernameLength, 40)
		XCTAssertEqual(IRCProtocolLimits.maximumTCPPort, 65535)
		XCTAssertEqual(IRCProtocolLimits.maximumNodesPerModeCommand, 4)
		XCTAssertEqual(IRCProtocolLimits.defaultNicknameMaximumLength, 31)
	}
}
