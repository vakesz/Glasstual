/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
@testable import Glasstual
import SwiftUI
import XCTest

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
final class ChannelModesFeatureTests: XCTestCase {
	func testModeRawValuesMatchIRCWireSchema() {
		XCTAssertEqual(
			ChannelMode.allCases.map(\.rawValue),
			["i", "m", "n", "p", "s", "t", "k", "l"]
		)
		XCTAssertEqual(
			ChannelMode.booleanModes,
			[.secretChannel, .privateChannel, .noExternalMessages, .operatorTopic, .inviteOnly, .moderated]
		)
		XCTAssertEqual(
			ChannelValidationSuppressionKey.maximumSecretKeyLength.rawValue,
			"maximum_secret_key_length"
		)
	}

	func testModelCopiesAllInitialModesAndParameters() throws {
		let (sourceModes, model) = try makeModel(
			modeString: "+imnpstk secret +l 007",
			maximumKeyLength: 8
		)

		for mode in ChannelMode.allCases {
			XCTAssertTrue(model.isEnabled(mode), mode.rawValue)
		}
		XCTAssertEqual(model.secretKey, "secret")
		XCTAssertEqual(model.userLimit, "007")

		model.setMode(.moderated, enabled: false)
		model.updateSecretKey("replacement")
		model.updateUserLimit("25")

		XCTAssertTrue(try XCTUnwrap(sourceModes.modeInfo(for: ChannelMode.moderated.rawValue)).modeIsSet)
		XCTAssertEqual(sourceModes.modeInfo(for: ChannelMode.key.rawValue)?.modeParameter, "secret")
		XCTAssertEqual(sourceModes.modeInfo(for: ChannelMode.userLimit.rawValue)?.modeParameter, "007")
	}

	func testSecretAndPrivateModesAreMutuallyExclusiveAfterInteraction() throws {
		let (_, model) = try makeModel(modeString: "+sp")

		XCTAssertTrue(model.isEnabled(.secretChannel))
		XCTAssertTrue(model.isEnabled(.privateChannel))

		model.setMode(.secretChannel, enabled: true)
		XCTAssertTrue(model.isEnabled(.secretChannel))
		XCTAssertFalse(model.isEnabled(.privateChannel))

		model.setMode(.privateChannel, enabled: true)
		XCTAssertFalse(model.isEnabled(.secretChannel))
		XCTAssertTrue(model.isEnabled(.privateChannel))
	}

	func testParameterValuesSurviveDisabledModesAndAreAppliedOnSubmission() throws {
		let (_, model) = try makeModel(modeString: "+kl old-key 12")

		model.setMode(.key, enabled: false)
		model.setMode(.userLimit, enabled: false)
		model.updateSecretKey("new-key")
		model.updateUserLimit("44")

		let submittedModes = model.modesForSubmission()
		let keyMode = try XCTUnwrap(submittedModes.modeInfo(for: ChannelMode.key.rawValue))
		let limitMode = try XCTUnwrap(submittedModes.modeInfo(for: ChannelMode.userLimit.rawValue))

		XCTAssertFalse(keyMode.modeIsSet)
		XCTAssertEqual(keyMode.modeParameter, "new-key")
		XCTAssertFalse(limitMode.modeIsSet)
		XCTAssertEqual(limitMode.modeParameter, "44")
	}

	func testUserLimitEditsNormalizeToSupportedRange() throws {
		let (_, model) = try makeModel()

		for (input, expected) in [
			// An empty field stays empty, and junk leaves the last valid
			// value alone rather than collapsing to 0.
			("", ""),
			("not a number", ""),
			("-1", "0"),
			("00007", "7"),
			("0", "0"),
			("99999", "99999"),
			("100000", "99999"),
		] {
			model.updateUserLimit(input)
			XCTAssertEqual(model.userLimit, expected, input)
		}
	}

	func testMaximumKeyLengthWarningIsNonzeroAndOneTime() throws {
		let (_, model) = try makeModel(maximumKeyLength: 3)

		XCTAssertFalse(model.updateSecretKey("abc"))
		XCTAssertTrue(model.updateSecretKey("abcd"))
		XCTAssertTrue(model.hasPresentedMaximumKeyLengthWarning)
		XCTAssertFalse(model.updateSecretKey("abcde"))
		XCTAssertFalse(model.updateSecretKey("a"))

		let (_, unlimitedModel) = try makeModel(maximumKeyLength: 0)
		XCTAssertFalse(unlimitedModel.updateSecretKey(String(repeating: "x", count: 1000)))

		// KEYLEN is an octet count, so a single emoji is four bytes over a
		// one-byte limit.
		let (_, graphemeModel) = try makeModel(maximumKeyLength: 1)
		XCTAssertTrue(graphemeModel.updateSecretKey("💬"))
	}

	func testContentUsesNamespacedLocalizedCopyAndSharedValidationCopy() {
		let content = ChannelModesContent.current(channelName: "#swift")

		XCTAssertEqual(content.headingTitle, "Modes for #swift")
		XCTAssertEqual(content.title(for: .secretChannel), "Secret channel (+s)")
		XCTAssertEqual(content.title(for: .privateChannel), "Private channel (+p)")
		XCTAssertEqual(content.title(for: .noExternalMessages), "No external channel messages (+n)")
		XCTAssertEqual(content.title(for: .operatorTopic), "Only operators can change topic (+t)")
		XCTAssertEqual(content.title(for: .inviteOnly), "Invite-only channel (+i)")
		XCTAssertEqual(content.title(for: .moderated), "Moderated channel (+m)")
		XCTAssertEqual(content.title(for: .key), "Password (+k):")
		XCTAssertEqual(content.title(for: .userLimit), "Limit number of users (+l):")
		XCTAssertEqual(content.saveButtonTitle, "Save")
		XCTAssertEqual(content.cancelButtonTitle, "Cancel")
		XCTAssertEqual(content.windowTitle, "Channel Modes")
		XCTAssertEqual(
			ChannelValidationStrings.maximumKeyLengthMessage,
			"If you continue typing, the end of your secret key may be cut off."
		)
		XCTAssertEqual(
			ChannelValidationStrings.maximumKeyLengthTitle(networkName: "ExampleNet", maximumLength: 16),
			"You have exceeded the secret key length defined by ExampleNet which is 16 characters"
		)
	}

	func testRuntimeSheetContractSurvivesWithoutANib() {
		XCTAssertEqual(NSStringFromClass(ChannelModifyModesSheet.self), "TDCChannelModifyModesSheet")
		XCTAssertNotNil(NSProtocolFromString("TDCChannelModifyModesSheetDelegate"))
		XCTAssertNil(Bundle.main.path(forResource: "TDCChannelModifyModesSheet", ofType: "nib"))

		for selectorName in [
			"initWithChannel:",
			"start",
			"ok:",
			"cancel:",
			"windowWillClose:",
		] {
			XCTAssertTrue(
				ChannelModifyModesSheet.instancesRespond(to: NSSelectorFromString(selectorName)),
				selectorName
			)
		}

		XCTAssertFalse(ChannelModifyModesSheet.instancesRespond(to: NSSelectorFromString("onChangeCheck:")))
		XCTAssertFalse(
			ChannelModifyModesSheet.instancesRespond(to: NSSelectorFromString("controlTextDidChange:"))
		)
	}

	func testAdapterPreservesIdentityCopiedModesAndTypedDelegateCallbacks() throws {
		let client = GLTTestClient()
		client.supportInfo.processConfigurationData("CHANMODES=beI,k,l,imnpst PREFIX=(ov)@+ KEYLEN=8")
		let channel = try XCTUnwrap(client.findChannelOrCreate("#swift"))
		channel.activate()
		_ = channel.modeInfo?.updateModes("+ntk original +l 12")

		let adapter = ChannelModifyModesSheet(channel: channel)
		let channelPrototype: TDCChannelPrototype = adapter
		let delegate = ChannelModesDelegateSpy()
		adapter.delegate = delegate

		XCTAssertIdentical(adapter.client, client)
		XCTAssertIdentical(adapter.channel, channel)
		XCTAssertEqual(channelPrototype.clientId, client.uniqueIdentifier)
		XCTAssertEqual(channelPrototype.channelId, channel.uniqueIdentifier)
		XCTAssertTrue(adapter.model.isEnabled(.noExternalMessages))
		XCTAssertTrue(adapter.model.isEnabled(.operatorTopic))
		XCTAssertTrue(adapter.model.isEnabled(.key))
		XCTAssertTrue(adapter.model.isEnabled(.userLimit))
		XCTAssertEqual(adapter.model.secretKey, "original")
		XCTAssertEqual(adapter.model.userLimit, "12")
		XCTAssertTrue(adapter.sheet.delegate === adapter)
		XCTAssertTrue(adapter.sheet.contentViewController is NSHostingController<ChannelModesView>)
		XCTAssertFalse(adapter.sheet.styleMask.contains(.resizable))
		XCTAssertFalse(adapter.sheet.isReleasedWhenClosed)
		XCTAssertFalse(adapter.sheet.isRestorable)
		XCTAssertEqual(adapter.sheet.tabbingMode, .disallowed)
		XCTAssertEqual(adapter.sheet.contentMinSize, NSSize(width: 440, height: 390))
		XCTAssertEqual(adapter.sheet.contentMaxSize, NSSize(width: 440, height: 390))

		adapter.model.setMode(.moderated, enabled: true)
		adapter.model.updateSecretKey("edited")
		XCTAssertEqual(channel.modeInfo?.modes.modeInfo(for: ChannelMode.key.rawValue)?.modeParameter, "original")

		adapter.ok(nil)

		let acceptedModes = try XCTUnwrap(delegate.acceptedModes)
		XCTAssertTrue(try XCTUnwrap(acceptedModes.modeInfo(for: ChannelMode.moderated.rawValue)).modeIsSet)
		XCTAssertEqual(acceptedModes.modeInfo(for: ChannelMode.key.rawValue)?.modeParameter, "edited")
		XCTAssertEqual(delegate.events, ["accept"])

		adapter.windowWillClose(Notification(name: NSWindow.willCloseNotification))
		XCTAssertEqual(delegate.events, ["accept", "close"])
	}

	private func makeModel(
		modeString: String = "",
		maximumKeyLength: UInt = 0
	) throws -> (ChannelModeContainer, ChannelModesModel) {
		let client = GLTTestClient()
		client.supportInfo.processConfigurationData("CHANMODES=beI,k,l,imnpst PREFIX=(ov)@+")
		let channel = try XCTUnwrap(client.findChannelOrCreate("#test"))
		let state = ChannelModeState(channel: channel)
		_ = state.updateModes(modeString)

		return (
			state.modes,
			ChannelModesModel(copying: state.modes, maximumKeyLength: maximumKeyLength)
		)
	}
}
