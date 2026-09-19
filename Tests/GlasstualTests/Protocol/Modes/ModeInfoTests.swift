// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
@testable import Glasstual
import Testing

@Suite("Mode info")
struct ModeInfoTests {
	@MainActor
	@Test("Modes parsed off a MODE line survive being stored and read back")
	func parsedModesRoundTripThroughTheContainer() {
		let session = TestServerSession()
		session.supportInfo.processConfigurationData("PREFIX=(ov)@+")

		let parsed = session.supportInfo.parseModes("+nt-k+l secret 10")
		var container = ChannelModeContainer(session: session)
		container.apply(parsed)

		#expect(parsed.isEmpty == false)

		for mode in parsed {
			#expect(container.modeInfo(for: mode.modeSymbol) == mode)
		}
	}

	/// `TestServerSession` and its support info are main-actor isolated; the rest
	/// of this suite works on plain values.
	@MainActor
	@Test("A member mode change needs both a prefix mode and a parameter")
	func memberModeRequiresAParameterAndPrefixMode() {
		let session = TestServerSession()
		session.supportInfo.processConfigurationData("PREFIX=(ov)@+")

		let memberMode = ModeInfo(modeSymbol: "o", modeIsSet: true, modeParameter: "nick")
		let missingParameter = ModeInfo(modeSymbol: "o", modeIsSet: true)
		let channelMode = ModeInfo(modeSymbol: "n", modeIsSet: true, modeParameter: "nick")

		#expect(memberMode.isModeForChangingMemberMode(on: session))
		#expect(missingParameter.isModeForChangingMemberMode(on: session) == false)
		#expect(channelMode.isModeForChangingMemberMode(on: session) == false)
	}
}
