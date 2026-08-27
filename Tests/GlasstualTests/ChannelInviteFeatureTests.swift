/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
@testable import Glasstual
import XCTest

@MainActor
private final class ChannelInviteDelegateSpy: NSObject, ChannelInviteSheetDelegate {
	private(set) var selectedChannel: String?
	private(set) var didClose = false

	func channelInviteSheet(_: ChannelInviteSheet, onSelectChannel channelName: String) {
		selectedChannel = channelName
	}

	func channelInviteSheetWillClose(_: ChannelInviteSheet) {
		didClose = true
	}
}

@MainActor
final class ChannelInviteFeatureTests: XCTestCase {
	func testPresentationDescribesOneTwoAndManyInvitees() {
		let channels = ["#general", "#support"]

		XCTAssertEqual(
			ChannelInviteContent(nicknames: ["alice"], channels: channels).headerTitle,
			"Invite alice to:"
		)
		XCTAssertEqual(
			ChannelInviteContent(nicknames: ["alice", "bob"], channels: channels).headerTitle,
			"Invite alice and bob to:"
		)
		XCTAssertEqual(
			ChannelInviteContent(nicknames: ["alice", "bob", "carol"], channels: channels).headerTitle,
			"Invite 3 users to:"
		)
	}

	func testPresentationPreservesChannelOrderAndLocalizedControls() {
		let content = ChannelInviteContent(nicknames: ["alice"], channels: ["#zeta", "#alpha"])

		XCTAssertEqual(content.channels, ["#zeta", "#alpha"])
		XCTAssertEqual(content.channelPickerLabel, "Channel to invite users to")
		XCTAssertEqual(content.inviteButtonTitle, "Invite")
		XCTAssertEqual(content.cancelButtonTitle, "Cancel")
	}

	func testRuntimeClassAndSelectorsRemainStableWithoutANib() {
		XCTAssertEqual(NSStringFromClass(ChannelInviteSheet.self), "TDCChannelInviteSheet")
		XCTAssertNotNil(NSProtocolFromString("TDCChannelInviteSheetDelegate"))
		XCTAssertNil(Bundle.main.path(forResource: "TDCChannelInviteSheet", ofType: "nib"))

		for selectorName in [
			"initWithNicknames:onClient:",
			"startWithChannels:",
			"ok:",
			"cancel:",
			"windowWillClose:",
		] {
			XCTAssertTrue(ChannelInviteSheet.instancesRespond(to: NSSelectorFromString(selectorName)), selectorName)
		}
	}

	func testAdapterUsesTheTypedLegacyDelegateContract() {
		let adapter = ChannelInviteSheet(nicknames: ["alice"], on: GLTTestClient())
		let delegate = ChannelInviteDelegateSpy()
		adapter.delegate = delegate

		adapter.start(withChannels: ["#general", "#support"])
		adapter.ok(nil)
		adapter.windowWillClose(Notification(name: NSWindow.willCloseNotification))

		XCTAssertEqual(delegate.selectedChannel, "#general")
		XCTAssertTrue(delegate.didClose)
	}
}
