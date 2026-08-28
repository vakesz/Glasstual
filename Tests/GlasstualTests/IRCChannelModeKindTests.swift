/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation
@testable import Glasstual
import Testing

/// ISUPPORT `CHANMODES` groups used to be stored as integers with 100 standing
/// in for a PREFIX mode. These pin the decoding now that the group is a type.
@MainActor
struct IRCChannelModeKindTests {
	private func supportInfo(_ configuration: String) -> IRCISupportInfo {
		let supportInfo = IRCISupportInfo()
		supportInfo.processConfigurationData(configuration)

		return supportInfo
	}

	@Test
	func decodesTheFourChanModesGroupsInOrder() {
		let info = supportInfo("CHANMODES=beI,k,l,imnpst")

		#expect(info.channelModeKinds["b"] == .list)
		#expect(info.channelModeKinds["e"] == .list)
		#expect(info.channelModeKinds["k"] == .setting)
		#expect(info.channelModeKinds["l"] == .settingWhenSet)
		#expect(info.channelModeKinds["t"] == .flag)
	}

	/// Groups past D have no defined meaning, so their modes are not recorded
	/// and read back as taking no parameter.
	@Test
	func ignoresGroupsBeyondTheFourthOne() {
		let info = supportInfo("CHANMODES=b,k,l,t,XY")

		#expect(info.channelModeKinds["X"] == nil)
		#expect(info.modeHasParameter("X", whenModeIsSet: true) == false)
	}

	@Test
	func marksEveryPrefixModeAsAUserPrefix() {
		let info = supportInfo("PREFIX=(qaohv)~&@%+")

		for symbol in "qaohv" {
			#expect(info.channelModeKinds[symbol] == .userPrefix)
		}
	}

	@Test(arguments: [
		(ChannelModeKind.list, ModeParameterPolicy.always),
		(.setting, .always),
		(.userPrefix, .always),
		(.settingWhenSet, .onlyWhenSet),
		(.flag, .never),
	])
	func mapsEachKindToItsParameterPolicy(testCase: (ChannelModeKind, ModeParameterPolicy)) {
		#expect(testCase.0.parameterPolicy == testCase.1)
	}

	@Test
	func onlyRequiresAParameterForASettingWhenSetWhileItIsBeingSet() {
		#expect(ModeParameterPolicy.onlyWhenSet.requiresParameter(whenModeIsSet: true))
		#expect(ModeParameterPolicy.onlyWhenSet.requiresParameter(whenModeIsSet: false) == false)
		#expect(ModeParameterPolicy.always.requiresParameter(whenModeIsSet: false))
		#expect(ModeParameterPolicy.never.requiresParameter(whenModeIsSet: true) == false)
	}

	@Test
	func parsesModeParametersAccordingToTheDecodedGroups() {
		let info = supportInfo("CHANMODES=beI,k,l,imnpst PREFIX=(ov)@+")
		let modes = info.parseModes("+ol alice 10 -k")

		#expect(modes.count == 3)
		#expect(modes[0].modeSymbol == "o")
		#expect(modes[0].modeParameter == "alice")
		#expect(modes[1].modeSymbol == "l")
		#expect(modes[1].modeParameter == "10")
		#expect(modes[2].modeSymbol == "k")
		// Clearing a group B mode still carries its parameter, and there is none.
		#expect(modes[2].modeParameter == nil)
	}

	@Test(arguments: [
		(IRCISupportInfoCaseMapping.rfc1459, "nick{}|^"),
		(.strictRFC1459, "nick{}|~"),
		(.ascii, "nick[]\\~"),
	])
	func foldsCaseAccordingToTheMappingEnum(testCase: (IRCISupportInfoCaseMapping, String)) {
		#expect(ISupportTokenParser.casefold("Nick[]\\~", caseMapping: testCase.0) == testCase.1)
	}
}

/// The SASL and ZNC capability bits were anonymous `1 << n` literals built at
/// the point of use. Naming them only helps if the numbers did not move.
struct IRCCapabilityBitTests {
	@Test(arguments: [
		(ClientIRCv3SupportedCapability.saslGeneric, UInt(1) << 22),
		(.zncServerTime, UInt(1) << 25),
		(.zncServerTimeISO, UInt(1) << 26),
		(.zncPlaybackModule, UInt(1) << 27),
	])
	func keepsTheHistoricBitPositions(testCase: (ClientIRCv3SupportedCapability, UInt)) {
		#expect(testCase.0.rawValue == testCase.1)
	}

	@Test
	func doesNotCollideWithTheNeighbouringNamedBits() {
		let named: [ClientIRCv3SupportedCapability] = [
			.labeledResponse, .saslGeneric, .zncServerTime, .zncServerTimeISO,
			.zncPlaybackModule, .accountNotify,
		]

		#expect(Set(named.map(\.rawValue)).count == named.count)
	}
}
