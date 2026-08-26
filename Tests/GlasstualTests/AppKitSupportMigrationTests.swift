/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
import CocoaExtensions
@testable import Glasstual
import XCTest

@MainActor
final class AppKitSupportMigrationTests: XCTestCase {
	func testTextHelpersTrimValuesAndExposeTextViewState() throws {
		let field = NSTextField(string: "  join #swift  \n")
		XCTAssertEqual(field.trimmedStringValue, "join #swift")
		XCTAssertEqual(field.trimmedFirstTokenStringValue, "join")

		let scrollView = NSTextView.scrollableTextView()
		let textView = try XCTUnwrap(scrollView.documentView as? NSTextView)
		textView.string = "hello 👋"

		XCTAssertEqual(textView.stringLength, 8)
		XCTAssertEqual(textView.range, NSRange(location: 0, length: 8))
		XCTAssertTrue(textView.scrollView === scrollView)
		XCTAssertTrue(NSTextView.instancesRespond(to: NSSelectorFromString("isFocused")))
	}

	func testWindowDefaultSizeRestorationKeepsTopRightCornerFixed() {
		let window = NSWindow(
			contentRect: NSRect(x: 100, y: 200, width: 640, height: 480),
			styleMask: [.titled, .resizable],
			backing: .buffered,
			defer: false
		)
		window.ce_saveSizeAsDefault()
		let savedFrame = window.frame

		window.setFrame(
			NSRect(
				x: savedFrame.minX,
				y: savedFrame.minY,
				width: savedFrame.width + 200,
				height: savedFrame.height + 100
			),
			display: false
		)
		let expandedFrame = window.frame
		window.ce_restoreDefaultSize(display: false)

		XCTAssertEqual(window.frame.size, savedFrame.size)
		XCTAssertEqual(window.frame.maxX, expandedFrame.maxX)
		XCTAssertEqual(window.frame.maxY, expandedFrame.maxY)
	}

	func testWindowHelperRetainsObjectiveCSelectors() {
		XCTAssertTrue(NSWindow.instancesRespond(to: NSSelectorFromString("saveSizeAsDefault")))
		XCTAssertTrue(NSWindow.instancesRespond(to: NSSelectorFromString("restoreDefaultSizeAndDisplay:")))
		XCTAssertTrue(NSWindow.instancesRespond(to: NSSelectorFromString("isActiveForDrawing")))
	}

	func testAutoExpandingFieldsTrackTheirLayoutWidth() {
		let textField = TVCAutoExpandingTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 20))
		textField.cell?.wraps = true
		textField.layout()

		XCTAssertEqual(textField.preferredMaxLayoutWidth, 240)

		let tokenField = TVCAutoExpandingTokenField(frame: NSRect(x: 0, y: 0, width: 180, height: 20))
		tokenField.cell?.wraps = true
		tokenField.layout()

		XCTAssertEqual(tokenField.preferredMaxLayoutWidth, 180)
	}

	func testAutoExpandingHelperIgnoresNonWrappingFields() {
		let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 20))
		field.cell?.wraps = false

		XCTAssertFalse(TVCAutoExpandingFieldUpdatePreferredMaxLayoutWidth(field))
		XCTAssertEqual(field.preferredMaxLayoutWidth, 0)
	}

	func testPreferencesControllerLoadsWindowFromNib() {
		let controller = PreferencesController()

		XCTAssertNotNil(controller.value(forKey: "window"))
	}

	func testMemberInfoPopoverUsesTransientBehavior() {
		let popover = TVCMemberListUserInfoPopover()

		popover.awakeFromNib()

		XCTAssertEqual(popover.behavior, .transient)
	}

	func testChannelModifyTopicSheetLoadsFromNib() {
		let client = GLTTestClient()
		let channel = makeChannel(named: "#chat", client: client)
		let sheet = TDCChannelModifyTopicSheet(channel: channel)

		XCTAssertTrue(sheet.client === client)
		XCTAssertTrue(sheet.channel === channel)
		XCTAssertEqual(sheet.channelId, channel.uniqueIdentifier)
		XCTAssertNotNil(sheet.sheet)
	}

	func testOnboardingStylePreviewViewExposesRadioButtonAccessibility() {
		let view = TDCOnboardingStylePreviewView()
		view.styleTitle = "Bubbles"

		XCTAssertTrue(view.isAccessibilityElement())
		XCTAssertEqual(view.accessibilityRole(), .radioButton)
		XCTAssertEqual(view.accessibilityLabel(), "Bubbles")
		XCTAssertEqual(view.accessibilityValue() as? Bool, false)

		view.isSelected = true

		XCTAssertEqual(view.accessibilityValue() as? Bool, true)
	}

	func testSpokenNotificationResolvesClientTarget() {
		let client = GLTTestClient()
		let notification = TLOSpokenNotification(
			notification: .connect,
			lineType: .notice,
			target: client,
			nickname: "alice",
			text: "connected"
		)

		XCTAssertTrue(notification.client === client)
		XCTAssertNil(notification.channel)
		XCTAssertEqual(notification.notificationType, .connect)
		XCTAssertEqual(notification.lineType, .notice)
		XCTAssertEqual(notification.nickname, "alice")
		XCTAssertEqual(notification.text, "connected")
	}

	func testSpokenNotificationResolvesChannelAndItsClient() {
		let client = GLTTestClient()
		let channel = makeChannel(named: "#chat", client: client)
		let notification = TLOSpokenNotification(
			notification: .channelMessage,
			lineType: .privateMessage,
			target: (channel as AnyObject) as! IRCTreeItem,
			nickname: "alice",
			text: "hello"
		)

		XCTAssertTrue(notification.client === client)
		XCTAssertTrue(notification.channel === channel)
	}

	func testFormatterColorsIncludeCanonicalIRCPalette() {
		XCTAssertEqual(NSColor.formatterColors.count, 99)
		XCTAssertEqual(NSColor.formatterWhiteColor, NSColor.formatterColors[0])
		XCTAssertEqual(NSColor.formatterBlackColor, NSColor.formatterColors[1])
		XCTAssertEqual(NSColor.formatterLightGrayColor, NSColor.formatterColors[15])
	}

	func testUnicodeHelperClassifiesCodePoints() {
		XCTAssertTrue(THOUnicodeHelper.isAlphabeticalCodePoint(Int(Unicode.Scalar("A").value)))
		XCTAssertTrue(THOUnicodeHelper.isAlphabeticalCodePoint(Int(Unicode.Scalar("z").value)))
		XCTAssertFalse(THOUnicodeHelper.isAlphabeticalCodePoint(Int(Unicode.Scalar("1").value)))
		XCTAssertTrue(THOUnicodeHelper.isPrivate(0xE010))
		XCTAssertTrue(THOUnicodeHelper.isIdeographic(0x4E00))
		XCTAssertTrue(THOUnicodeHelper.isIdeographicOrPrivate(0xE010))
	}

	private func makeChannel(named name: String, client: IRCClient) -> IRCChannel {
		let channel = IRCChannel(configDictionary: ["channelName": name])

		channel.setValue(client, forKey: "associatedClient")

		return channel
	}
}
