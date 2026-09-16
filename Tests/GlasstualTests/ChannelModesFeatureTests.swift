/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
import Foundation
@testable import Glasstual
import SwiftUI
import Testing

@MainActor
private final class ChannelModesDelegateSpy: NSObject, ChannelModifyModesSheetDelegate {
	private(set) var acceptedModes: ChannelModeContainer?

	func channelModifyModesSheet(_: ChannelModifyModesSheet, onOk modes: ChannelModeContainer) {
		acceptedModes = modes
	}
}

@MainActor
@Suite("Channel modes sheet")
struct ChannelModesFeatureTests {
	@Test("Mode raw values are the letters that go on the wire")
	func modeRawValuesMatchIRCWireSchema() {
		#expect(ChannelMode.allCases.map(\.rawValue) == ["i", "m", "n", "p", "s", "t", "k", "l"])
		#expect(ChannelMode.booleanModes == [
			.secretChannel, .privateChannel, .noExternalMessages, .operatorTopic, .inviteOnly, .moderated,
		])
	}

	@Test("The model copies every mode and parameter, leaving the channel's own modes alone")
	func modelCopiesAllInitialModesAndParameters() throws {
		let (sourceModes, model) = try makeModel(
			modeString: "+imnpstk secret +l 007",
			maximumKeyLength: 8
		)

		for mode in ChannelMode.allCases {
			#expect(model.isEnabled(mode), "\(mode.rawValue)")
		}
		#expect(model.secretKey == "secret")
		#expect(model.userLimit == "007")

		model.setMode(.moderated, enabled: false)
		model.updateSecretKey("replacement")
		model.updateUserLimit("25")

		let moderated = try #require(sourceModes.modeInfo(for: ChannelMode.moderated.rawValue))
		#expect(moderated.modeIsSet)
		#expect(sourceModes.modeInfo(for: ChannelMode.key.rawValue)?.modeParameter == "secret")
		#expect(sourceModes.modeInfo(for: ChannelMode.userLimit.rawValue)?.modeParameter == "007")
	}

	@Test("Secret and private turn each other off once either one is touched")
	func secretAndPrivateModesAreMutuallyExclusiveAfterInteraction() throws {
		let (_, model) = try makeModel(modeString: "+sp")

		#expect(model.isEnabled(.secretChannel))
		#expect(model.isEnabled(.privateChannel))

		model.setMode(.secretChannel, enabled: true)
		#expect(model.isEnabled(.secretChannel))
		#expect(model.isEnabled(.privateChannel) == false)

		model.setMode(.privateChannel, enabled: true)
		#expect(model.isEnabled(.secretChannel) == false)
		#expect(model.isEnabled(.privateChannel))
	}

	@Test("A parameter edited while its mode is off is still submitted")
	func parameterValuesSurviveDisabledModesAndAreAppliedOnSubmission() throws {
		let (_, model) = try makeModel(modeString: "+kl old-key 12")

		model.setMode(.key, enabled: false)
		model.setMode(.userLimit, enabled: false)
		model.updateSecretKey("new-key")
		model.updateUserLimit("44")

		let submittedModes = model.modesForSubmission()
		let keyMode = try #require(submittedModes.modeInfo(for: ChannelMode.key.rawValue))
		let limitMode = try #require(submittedModes.modeInfo(for: ChannelMode.userLimit.rawValue))

		#expect(keyMode.modeIsSet == false)
		#expect(keyMode.modeParameter == "new-key")
		#expect(limitMode.modeIsSet == false)
		#expect(limitMode.modeParameter == "44")
	}

	@Test("Clearing the limit and changing the key sets the new key, not the old limit")
	func clearingLimitAndChangingKeySubmitsTheNewKey() throws {
		let fixture = try makeModelState(modeString: "+kl old 50")
		let (state, model) = (fixture.state, fixture.model)

		model.setMode(.userLimit, enabled: false)
		model.updateSecretKey("new")

		withExtendedLifetime(fixture.client) {
			#expect(state.changeGroups(for: model.modesForSubmission()) == [
				ModeChangeGroup(symbols: "-l+k", parameters: ["new"]),
			])
		}
	}

	@Test("Submitting the sheet unchanged sends no mode change")
	func unchangedSubmissionSendsNothing() throws {
		let fixture = try makeModelState(modeString: "+nt")
		let (state, model) = (fixture.state, fixture.model)

		model.setMode(.noExternalMessages, enabled: true)

		withExtendedLifetime(fixture.client) {
			#expect(state.changeGroups(for: model.modesForSubmission()).isEmpty)
		}
	}

	@Test("User limit edits normalize to the supported range")
	func userLimitEditsNormalizeToSupportedRange() throws {
		let (_, model) = try makeModel()

		// Each edit lands on the value the one before it left behind: an empty
		// field stays empty, and junk leaves the last valid value alone rather
		// than collapsing to 0.
		for (input, expected) in [
			("", ""),
			("not a number", ""),
			("-1", "0"),
			("00007", "7"),
			(" 25 ", "25"),
			("0", "0"),
			("99999", "99999"),
			("100000", "99999"),
		] {
			model.updateUserLimit(input)
			#expect(model.userLimit == expected, "\(input)")
		}
	}

	/// The sheet warns beside the field instead of raising an alert on the
	/// keystroke that crosses the limit, and refuses to submit past it.
	@Test("The remaining key length gates submission, and only where a limit was declared")
	func remainingKeyLengthGatesSubmission() throws {
		let (_, model) = try makeModel(maximumKeyLength: 3)

		model.updateSecretKey("abc")
		#expect(model.remainingKeyLength == 0)
		#expect(model.fitsMaximumKeyLength)
		#expect(ChannelModesStrings.keyLengthWarning(remaining: 0) == nil)

		model.updateSecretKey("abcde")
		#expect(model.remainingKeyLength == -2)
		#expect(model.fitsMaximumKeyLength == false)
		#expect(ChannelModesStrings.keyLengthWarning(remaining: -2) == "2 bytes too many")
		#expect(ChannelModesStrings.keyLengthWarning(remaining: -1) == "1 byte too many")

		let (_, unlimitedModel) = try makeModel(maximumKeyLength: 0)
		unlimitedModel.updateSecretKey(String(repeating: "x", count: 1000))
		#expect(unlimitedModel.remainingKeyLength == nil)
		#expect(unlimitedModel.fitsMaximumKeyLength)

		// KEYLEN is an octet count, so a single emoji is four bytes over a
		// one-byte limit.
		let (_, graphemeModel) = try makeModel(maximumKeyLength: 1)
		graphemeModel.updateSecretKey("💬")
		#expect(graphemeModel.remainingKeyLength == -3)
	}

	@Test("Sheet copy comes from the namespaced table")
	func contentUsesNamespacedLocalizedCopy() {
		#expect(ChannelModesStrings.headingTitle(channelName: "#swift") == "Modes for #swift")
		#expect(ChannelMode.secretChannel.title == "Secret channel (+s)")
		#expect(ChannelMode.privateChannel.title == "Private channel (+p)")
		#expect(ChannelMode.noExternalMessages.title == "No external channel messages (+n)")
		#expect(ChannelMode.operatorTopic.title == "Only operators can change topic (+t)")
		#expect(ChannelMode.inviteOnly.title == "Invite-only channel (+i)")
		#expect(ChannelMode.moderated.title == "Moderated channel (+m)")
		// Named for the IRC term, and with no trailing colon: the checkbox is
		// also the field's label for an assistive reader.
		#expect(ChannelMode.key.title == "Channel key (+k)")
		#expect(ChannelMode.userLimit.title == "Limit number of users (+l)")
		#expect(ChannelModesStrings.changeModesButtonTitle == "Change Modes")
		#expect(ChannelModesStrings.cancelButtonTitle == "Cancel")
		#expect(ChannelModesStrings.channelKeyPlaceholder == "Channel key")
		#expect(ChannelModesStrings.userLimitPlaceholder == "0–99999")
	}

	@Test("The sheet adapter copies the channel's modes and reports edits to its delegate")
	func adapterPreservesIdentityCopiedModesAndTypedDelegateCallbacks() throws {
		let client = TestClient()
		client.supportInfo.processConfigurationData("CHANMODES=beI,k,l,imnpst PREFIX=(ov)@+ KEYLEN=8")
		let channel = try #require(client.findChannelOrCreate("#swift"))
		channel.activate()
		_ = channel.modeInfo?.updateModes("+ntk original +l 12")

		let adapter = ChannelModifyModesSheet(channel: channel)
		let channelPrototype: ChannelScoped = adapter
		let delegate = ChannelModesDelegateSpy()
		adapter.delegate = delegate

		#expect(adapter.client === client)
		#expect(adapter.channel === channel)
		#expect(channelPrototype.clientId == client.uniqueIdentifier)
		#expect(channelPrototype.channelId == channel.uniqueIdentifier)
		#expect(adapter.model.isEnabled(.noExternalMessages))
		#expect(adapter.model.isEnabled(.operatorTopic))
		#expect(adapter.model.isEnabled(.key))
		#expect(adapter.model.isEnabled(.userLimit))
		#expect(adapter.model.secretKey == "original")
		#expect(adapter.model.userLimit == "12")
		adapter.model.setMode(.moderated, enabled: true)
		adapter.model.updateSecretKey("edited")
		#expect(channel.modeInfo?.modes.modeInfo(for: ChannelMode.key.rawValue)?.modeParameter == "original")

		adapter.submit()

		let acceptedModes = try #require(delegate.acceptedModes)
		let acceptedModerated = try #require(acceptedModes.modeInfo(for: ChannelMode.moderated.rawValue))
		#expect(acceptedModerated.modeIsSet)
		#expect(acceptedModes.modeInfo(for: ChannelMode.key.rawValue)?.modeParameter == "edited")
	}

	@Test("The submit action rejects a key above KEYLEN even when invoked from Return")
	func submissionRespectsKeyLengthLimit() throws {
		let client = TestClient()
		client.supportInfo.processConfigurationData("CHANMODES=beI,k,l,imnpst PREFIX=(ov)@+ KEYLEN=3")
		let channel = try #require(client.findChannelOrCreate("#swift"))
		channel.activate()
		let adapter = ChannelModifyModesSheet(channel: channel)
		let delegate = ChannelModesDelegateSpy()
		adapter.delegate = delegate
		adapter.model.setMode(.key, enabled: true)
		adapter.model.updateSecretKey("💬")

		adapter.submit()
		#expect(delegate.acceptedModes == nil)

		adapter.model.updateSecretKey("key")
		adapter.submit()
		#expect(delegate.acceptedModes?.modeInfo(for: ChannelMode.key.rawValue)?.modeParameter == "key")
	}

	private func makeModel(
		modeString: String = "",
		maximumKeyLength: UInt = 0
	) throws -> (ChannelModeContainer, ChannelModesModel) {
		let fixture = try makeModelState(modeString: modeString, maximumKeyLength: maximumKeyLength)

		return (fixture.state.modes, fixture.model)
	}

	private struct ModelFixture {
		let client: TestClient
		let state: ChannelModeState
		let model: ChannelModesModel
	}

	private func makeModelState(
		modeString: String,
		maximumKeyLength: UInt = 0
	) throws -> ModelFixture {
		let client = TestClient()
		client.supportInfo.processConfigurationData("CHANMODES=beI,k,l,imnpst PREFIX=(ov)@+")
		let channel = try #require(client.findChannelOrCreate("#test"))
		let state = ChannelModeState(channel: channel)
		_ = state.updateModes(modeString)

		return ModelFixture(
			client: client,
			state: state,
			model: ChannelModesModel(copying: state.modes, maximumKeyLength: maximumKeyLength)
		)
	}
}
