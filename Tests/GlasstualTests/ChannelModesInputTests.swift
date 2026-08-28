/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

@testable import Glasstual
import Testing

@MainActor
@Suite("Channel modes sheet input")
struct ChannelModesInputTests {
	private func makeModel(maximumKeyLength: UInt = 0) throws -> ChannelModesModel {
		let client = GLTTestClient()
		client.supportInfo.processConfigurationData("CHANMODES=beI,k,l,imnpst PREFIX=(ov)@+")
		let channel = try #require(client.findChannelOrCreate("#test"))
		let state = ChannelModeState(channel: channel)
		_ = state.updateModes("")

		return ChannelModesModel(copying: state.modes, maximumKeyLength: maximumKeyLength)
	}

	@Test("Clearing the user limit leaves the field empty")
	func emptyUserLimitStaysEmpty() throws {
		let model = try makeModel()

		model.updateUserLimit("42")
		#expect(model.userLimit == "42")

		model.updateUserLimit("")
		#expect(model.userLimit == "")
	}

	@Test("Non-numeric input is rejected rather than coerced to zero")
	func junkUserLimitIsRejected() throws {
		let model = try makeModel()

		model.updateUserLimit("42")
		model.updateUserLimit("42x")

		#expect(model.userLimit == "42")
	}

	@Test("Numeric input is normalised and clamped", arguments: [
		("00007", "7"),
		("0", "0"),
		("-1", "0"),
		(" 25 ", "25"),
		("99999", "99999"),
		("100000", "99999"),
	])
	func clampsNumericUserLimit(input: String, expected: String) throws {
		let model = try makeModel()

		model.updateUserLimit(input)

		#expect(model.userLimit == expected)
	}

	@Test("KEYLEN is measured in octets, not characters")
	func keyLengthIsMeasuredInOctets() throws {
		let model = try makeModel(maximumKeyLength: 3)

		// One emoji: a single Character, four UTF-8 bytes.
		#expect(model.updateSecretKey("\u{1F4AC}"))
	}

	@Test("An ASCII key inside the limit raises no warning")
	func shortAsciiKeyIsAccepted() throws {
		let model = try makeModel(maximumKeyLength: 8)

		#expect(model.updateSecretKey("hunter2") == false)
	}
}
