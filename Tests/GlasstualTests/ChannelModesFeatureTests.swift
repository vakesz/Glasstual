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
	private(set) var events: [String] = []

	func channelModifyModesSheet(_: ChannelModifyModesSheet, onOk modes: ChannelModeContainer) {
		acceptedModes = modes
		events.append("accept")
	}

	func channelModifyModesSheetWillClose(_: ChannelModifyModesSheet) {
		events.append("close")
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

	/// The key is what a suppressed alert is remembered by, so it outlives the
	/// build that wrote it.
	@Test("The maximum key length alert keeps the key it is suppressed under")
	func suppressionKeySurvivesRenames() {
		#expect(ChannelValidationSuppressionKey.maximumSecretKeyLength.rawValue == "maximum_secret_key_length")
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
			("0", "0"),
			("99999", "99999"),
			("100000", "99999"),
		] {
			model.updateUserLimit(input)
			#expect(model.userLimit == expected, "\(input)")
		}
	}

	@Test("The key length warning is shown once, and only for a limit the server declared")
	func maximumKeyLengthWarningIsNonzeroAndOneTime() throws {
		let (_, model) = try makeModel(maximumKeyLength: 3)

		#expect(model.updateSecretKey("abc") == false)
		#expect(model.updateSecretKey("abcd"))
		#expect(model.hasPresentedMaximumKeyLengthWarning)
		#expect(model.updateSecretKey("abcde") == false)
		#expect(model.updateSecretKey("a") == false)

		let (_, unlimitedModel) = try makeModel(maximumKeyLength: 0)
		#expect(unlimitedModel.updateSecretKey(String(repeating: "x", count: 1000)) == false)

		// KEYLEN is an octet count, so a single emoji is four bytes over a
		// one-byte limit.
		let (_, graphemeModel) = try makeModel(maximumKeyLength: 1)
		#expect(graphemeModel.updateSecretKey("💬"))
	}

	@Test("Sheet copy comes from the namespaced table and the shared validation table")
	func contentUsesNamespacedLocalizedCopyAndSharedValidationCopy() {
		let content = ChannelModesContent.current(channelName: "#swift")

		#expect(content.headingTitle == "Modes for #swift")
		#expect(content.title(for: .secretChannel) == "Secret channel (+s)")
		#expect(content.title(for: .privateChannel) == "Private channel (+p)")
		#expect(content.title(for: .noExternalMessages) == "No external channel messages (+n)")
		#expect(content.title(for: .operatorTopic) == "Only operators can change topic (+t)")
		#expect(content.title(for: .inviteOnly) == "Invite-only channel (+i)")
		#expect(content.title(for: .moderated) == "Moderated channel (+m)")
		#expect(content.title(for: .key) == "Password (+k):")
		#expect(content.title(for: .userLimit) == "Limit number of users (+l):")
		#expect(content.saveButtonTitle == "Save")
		#expect(content.cancelButtonTitle == "Cancel")
		#expect(content.windowTitle == "Channel Modes")
		#expect(
			ChannelValidationStrings.maximumKeyLengthMessage ==
				"If you continue typing, the end of your secret key may be cut off."
		)
		#expect(
			ChannelValidationStrings.maximumKeyLengthTitle(networkName: "ExampleNet", maximumLength: 16) ==
				"You have exceeded the secret key length defined by ExampleNet which is 16 characters"
		)
	}

	@Test("The sheet adapter copies the channel's modes and reports edits to its delegate")
	func adapterPreservesIdentityCopiedModesAndTypedDelegateCallbacks() throws {
		let client = GLTTestClient()
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

		adapter.ok(nil)

		let acceptedModes = try #require(delegate.acceptedModes)
		let acceptedModerated = try #require(acceptedModes.modeInfo(for: ChannelMode.moderated.rawValue))
		#expect(acceptedModerated.modeIsSet)
		#expect(acceptedModes.modeInfo(for: ChannelMode.key.rawValue)?.modeParameter == "edited")
		#expect(delegate.events == ["accept"])

		adapter.sheetDidEnd(withReturnCode: 0)
		#expect(delegate.events == ["accept", "close"])
	}

	private func makeModel(
		modeString: String = "",
		maximumKeyLength: UInt = 0
	) throws -> (ChannelModeContainer, ChannelModesModel) {
		let client = GLTTestClient()
		client.supportInfo.processConfigurationData("CHANMODES=beI,k,l,imnpst PREFIX=(ov)@+")
		let channel = try #require(client.findChannelOrCreate("#test"))
		let state = ChannelModeState(channel: channel)
		_ = state.updateModes(modeString)

		return (
			state.modes,
			ChannelModesModel(copying: state.modes, maximumKeyLength: maximumKeyLength)
		)
	}
}
