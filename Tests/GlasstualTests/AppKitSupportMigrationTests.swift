/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
import CocoaExtensions
import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("AppKit support", .serialized)
struct AppKitSupportMigrationTests {
	@Test("A field reports its value trimmed, and a text view reports its length in UTF-16 units")
	func textHelpersTrimValuesAndExposeTextViewState() throws {
		let field = NSTextField(string: "  join #swift  \n")
		#expect(field.trimmedStringValue == "join #swift")
		#expect(field.trimmedFirstTokenStringValue == "join")

		let scrollView = NSTextView.scrollableTextView()
		let textView = try #require(scrollView.documentView as? NSTextView)
		textView.string = "hello 👋"

		#expect(textView.stringLength == 8)
		#expect(textView.range == NSRange(location: 0, length: 8))
		#expect(textView.scrollView === scrollView)
	}

	@Test("Restoring the default size grows a window down and to the left")
	func windowDefaultSizeRestorationKeepsTopRightCornerFixed() {
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

		#expect(window.frame.size == savedFrame.size)
		#expect(window.frame.maxX == expandedFrame.maxX)
		#expect(window.frame.maxY == expandedFrame.maxY)
	}

	@Test("A wrapping field lays itself out against its own width")
	func autoExpandingFieldsTrackTheirLayoutWidth() {
		let textField = AutoExpandingTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 20))
		textField.cell?.wraps = true
		textField.layout()

		#expect(textField.preferredMaxLayoutWidth == 240)

		let tokenField = AutoExpandingTokenField(frame: NSRect(x: 0, y: 0, width: 180, height: 20))
		tokenField.cell?.wraps = true
		tokenField.layout()

		#expect(tokenField.preferredMaxLayoutWidth == 180)
	}

	@Test("A field that does not wrap is left with no preferred width")
	func autoExpandingHelperIgnoresNonWrappingFields() {
		let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 20))
		field.cell?.wraps = false

		#expect(updatePreferredMaxLayoutWidth(of: field) == false)
		#expect(field.preferredMaxLayoutWidth == 0)
	}

	/// `stringValueIsTrimmed` is what keeps a pasted "  #swift  " from being
	/// sent to the server with its whitespace.
	@Test("A validated control reports its value trimmed once asked to")
	func validatedControlsTrimTheirValue() {
		let textField = ValidatedTextField(string: "  #swift  ")
		textField.stringValueIsTrimmed = true
		#expect(textField.value == "#swift")

		let comboBox = ValidatedComboBox()
		comboBox.stringValue = "  libera  "
		comboBox.stringValueIsTrimmed = true
		#expect(comboBox.value == "libera")
	}

	/// The suppression family is catalogued as a container key, so the flags are
	/// stored there rather than in UserDefaults.standard, which is what makes an
	/// imported "do not ask again" take effect.
	@Test("An alert is suppressed exactly when its stored preference says so")
	func alertSuppressionDecisionFollowsTheStoredPreference() {
		let baseKey = "AppKitSupportMigrationTests.\(UUID().uuidString)"
		let defaultsKey = TDCAlert.suppressionKey(withBase: baseKey)
		let defaults = TextualUserDefaults.container
		defer { defaults.removeObject(forKey: defaultsKey) }

		#expect(TDCAlert.isSuppressed(baseKey: baseKey) == false)

		defaults.set(true, forKey: defaultsKey)

		#expect(TDCAlert.isSuppressed(baseKey: baseKey))
	}

	@Test("The Settings window is built in code")
	func preferencesControllerBuildsItsWindow() {
		let controller = PreferencesController()

		#expect(controller.value(forKey: "window") != nil)
	}

	@Test("The member info popover dismisses itself when the user clicks away")
	func memberInfoPopoverUsesTransientBehavior() {
		let popover = MemberListUserInfoPopover()

		popover.configure()

		#expect(popover.behavior == .transient)
	}

	@Test("The topic sheet loads from its nib and keeps hold of its channel")
	func channelModifyTopicSheetLoadsFromNib() {
		let client = GLTTestClient()
		let channel = makeChannel(named: "#chat", client: client)
		let sheet = ChannelModifyTopicSheet(channel: channel)

		#expect(sheet.client === client)
		#expect(sheet.channel === channel)
		#expect(sheet.channelId == channel.uniqueIdentifier)
		#expect(sheet.sheet != nil)
	}

	@Test("An onboarding style preview reads to VoiceOver as a radio button")
	func onboardingStylePreviewViewExposesRadioButtonAccessibility() {
		let view = OnboardingStylePreviewView()
		view.styleTitle = "Bubbles"

		#expect(view.isAccessibilityElement())
		#expect(view.accessibilityRole() == .radioButton)
		#expect(view.accessibilityLabel() == "Bubbles")
		#expect((view.accessibilityValue() as? Bool) == false)

		view.selected = true

		#expect((view.accessibilityValue() as? Bool) == true)
	}

	@Test("A notification about a client names that client and no channel")
	func spokenNotificationResolvesClientTarget() {
		let client = GLTTestClient()
		let notification = SpokenNotification(
			notificationType: .connect,
			lineType: .notice,
			target: client,
			nickname: "alice",
			text: "connected"
		)

		#expect(notification.clientIdentifier == client.uniqueIdentifier)
		#expect(notification.channelIdentifier == nil)
		#expect(notification.notificationType == .connect)
		#expect(notification.lineType == .notice)
		#expect(notification.nickname == "alice")
		#expect(notification.text == "connected")
	}

	@Test("A notification about a channel names the channel and the client behind it")
	func spokenNotificationResolvesChannelAndItsClient() {
		let client = GLTTestClient()
		let channel = makeChannel(named: "#chat", client: client)
		let notification = SpokenNotification(
			notificationType: .channelMessage,
			lineType: .privateMessage,
			target: channel,
			nickname: "alice",
			text: "hello"
		)

		#expect(notification.clientIdentifier == client.uniqueIdentifier)
		#expect(notification.channelIdentifier == channel.uniqueIdentifier)
	}

	private func makeChannel(named name: String, client: IRCClient) -> Channel {
		let channel = Channel(config: ChannelConfig(channelName: name))

		channel.associatedClient = client

		return channel
	}
}
