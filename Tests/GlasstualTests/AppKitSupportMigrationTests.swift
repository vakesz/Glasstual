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
		XCTAssertNotNil(NSClassFromString("TVCAutoExpandingTextField"))
		XCTAssertNotNil(NSClassFromString("TVCAutoExpandingTokenField"))

		let textField = AutoExpandingTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 20))
		textField.cell?.wraps = true
		textField.layout()

		XCTAssertEqual(textField.preferredMaxLayoutWidth, 240)

		let tokenField = AutoExpandingTokenField(frame: NSRect(x: 0, y: 0, width: 180, height: 20))
		tokenField.cell?.wraps = true
		tokenField.layout()

		XCTAssertEqual(tokenField.preferredMaxLayoutWidth, 180)
	}

	func testAutoExpandingHelperIgnoresNonWrappingFields() {
		let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 20))
		field.cell?.wraps = false

		XCTAssertFalse(updatePreferredMaxLayoutWidth(of: field))
		XCTAssertEqual(field.preferredMaxLayoutWidth, 0)
	}

	func testNativeInputAndValidationControlsPreserveRuntimeContracts() {
		/* TDCAlert's Objective-C surface is gone; its response values are still
		 the AppKit modal-response constants the panel returns. */
		XCTAssertEqual(TDCAlertResponse.default.rawValue, 1000)
		XCTAssertEqual(TDCAlertResponse.alternate.rawValue, 1001)
		XCTAssertEqual(TDCAlertResponse.other.rawValue, 1002)

		XCTAssertNotNil(NSClassFromString("TDCInputPrompt"))
		XCTAssertTrue(
			InputPrompt.responds(
				to: NSSelectorFromString(
					"promptWithMessage:title:defaultButton:alternateButton:prefillString:completionBlock:"
				)
			)
		)

		let textField = ValidatedTextField(string: "  #swift  ")
		textField.stringValueIsTrimmed = true
		XCTAssertEqual(textField.value, "#swift")
		XCTAssertEqual(NSStringFromClass(type(of: textField)), "TVCValidatedTextField")

		let comboBox = ValidatedComboBox()
		comboBox.stringValue = "  libera  "
		comboBox.stringValueIsTrimmed = true
		XCTAssertEqual(comboBox.value, "libera")
		XCTAssertEqual(NSStringFromClass(type(of: comboBox)), "TVCValidatedComboBox")
		XCTAssertNotNil(NSClassFromString("TVCValidatedComboBoxCell"))
		XCTAssertEqual(NSStringFromClass(TextViewWithIRCFormatter.self), "TVCTextViewWithIRCFormatter")
		XCTAssertEqual(NSStringFromClass(BasicTableView.self), "TVCBasicTableView")
		XCTAssertEqual(TVCTextViewCaretLocation.onlyLine.rawValue, 0)
		XCTAssertEqual(TVCTextViewCaretLocation.firstLine.rawValue, 1)
		XCTAssertEqual(TVCTextViewCaretLocation.middle.rawValue, 2)
		XCTAssertEqual(TVCTextViewCaretLocation.lastLine.rawValue, 3)
	}

	/// The suppression family is catalogued as a container key, so the flags are
	/// stored there rather than in UserDefaults.standard, which is what makes an
	/// imported "do not ask again" take effect.
	func testAlertSuppressionDecisionFollowsTheStoredPreference() {
		let baseKey = "AppKitSupportMigrationTests.\(UUID().uuidString)"
		let defaultsKey = TDCAlert.suppressionKey(withBase: baseKey)
		let defaults = TextualUserDefaults.shared()
		defer { defaults.removeObject(forKey: defaultsKey) }

		XCTAssertFalse(TDCAlert.isSuppressed(baseKey: baseKey))

		defaults.set(true, forKey: defaultsKey)

		XCTAssertTrue(TDCAlert.isSuppressed(baseKey: baseKey))
	}

	func testPreferencesControllerLoadsWindowFromNib() {
		let controller = PreferencesController()

		XCTAssertNotNil(controller.value(forKey: "window"))
	}

	func testMemberInfoPopoverUsesTransientBehavior() {
		let popover = MemberListUserInfoPopover()

		popover.awakeFromNib()

		XCTAssertEqual(popover.behavior, .transient)
	}

	func testChannelModifyTopicSheetLoadsFromNib() {
		let client = GLTTestClient()
		let channel = makeChannel(named: "#chat", client: client)
		let sheet = ChannelModifyTopicSheet(channel: channel)

		XCTAssertTrue(sheet.client === client)
		XCTAssertTrue(sheet.channel === channel)
		XCTAssertEqual(sheet.channelId, channel.uniqueIdentifier)
		XCTAssertNotNil(sheet.sheet)
	}

	func testMigratedDialogRuntimeNamesRemainAvailable() {
		let runtimeClassNames = [
			"TDCAddressBookSheet",
			"TDCChannelBanListSheet",
			"TDCChannelModifyModesSheet",
			"TDCHighlightEntrySheet",
			"TDCPreferencesUserStyleSheet",
			"TDCServerHighlightListSheet",
		]

		for runtimeClassName in runtimeClassNames {
			XCTAssertNotNil(NSClassFromString(runtimeClassName), runtimeClassName)
		}

		XCTAssertEqual(ChannelBanListEntryType.ban.rawValue, IRCISupportInfoListType.ban.rawValue)
		XCTAssertEqual(ChannelBanListEntryType.banException.rawValue, IRCISupportInfoListType.banException.rawValue)
		XCTAssertEqual(
			ChannelBanListEntryType.inviteException.rawValue,
			IRCISupportInfoListType.inviteException.rawValue
		)
		XCTAssertEqual(ChannelBanListEntryType.quiet.rawValue, IRCISupportInfoListType.quiet.rawValue)
	}

	func testOnboardingStylePreviewViewExposesRadioButtonAccessibility() {
		let view = OnboardingStylePreviewView()
		view.styleTitle = "Bubbles"

		XCTAssertTrue(view.isAccessibilityElement())
		XCTAssertEqual(view.accessibilityRole(), .radioButton)
		XCTAssertEqual(view.accessibilityLabel(), "Bubbles")
		XCTAssertEqual(view.accessibilityValue() as? Bool, false)

		view.selected = true

		XCTAssertEqual(view.accessibilityValue() as? Bool, true)
	}

	func testSpokenNotificationResolvesClientTarget() {
		let client = GLTTestClient()
		let notification = SpokenNotification(
			notificationType: .connect,
			lineType: .notice,
			target: client,
			nickname: "alice",
			text: "connected"
		)

		XCTAssertEqual(notification.clientIdentifier, client.uniqueIdentifier)
		XCTAssertNil(notification.channelIdentifier)
		XCTAssertEqual(notification.notificationType, .connect)
		XCTAssertEqual(notification.lineType, .notice)
		XCTAssertEqual(notification.nickname, "alice")
		XCTAssertEqual(notification.text, "connected")
	}

	func testSpokenNotificationResolvesChannelAndItsClient() {
		let client = GLTTestClient()
		let channel = makeChannel(named: "#chat", client: client)
		let notification = SpokenNotification(
			notificationType: .channelMessage,
			lineType: .privateMessage,
			target: channel,
			nickname: "alice",
			text: "hello"
		)

		XCTAssertEqual(notification.clientIdentifier, client.uniqueIdentifier)
		XCTAssertEqual(notification.channelIdentifier, channel.uniqueIdentifier)
	}

	func testFormatterColorsIncludeCanonicalIRCPalette() {
		XCTAssertEqual(NSColor.formatterColors.count, 99)
		XCTAssertEqual(NSColor.formatterWhiteColor, NSColor.formatterColors[0])
		XCTAssertEqual(NSColor.formatterBlackColor, NSColor.formatterColors[1])
		XCTAssertEqual(NSColor.formatterLightGrayColor, NSColor.formatterColors[15])
	}

	private func makeChannel(named name: String, client: IRCClient) -> Channel {
		let channel = Channel(config: ChannelConfig(channelName: name))

		channel.setValue(client, forKey: "associatedClient")

		return channel
	}
}
