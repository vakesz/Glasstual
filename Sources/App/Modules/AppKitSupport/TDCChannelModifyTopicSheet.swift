/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\\_\\__|\\__,_|\\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import AppKit

@objc(TDCChannelModifyTopicSheet)
@MainActor
public final class ChannelModifyTopicSheet: SheetBase {
	@objc public private(set) var client: IRCClient!
	@objc public private(set) var channel: IRCChannel!
	@objc public private(set) var clientId = ""
	@objc public private(set) var channelId = ""

	@IBOutlet private var headerTitleTextField: NSTextField!
	@IBOutlet private var topicValueTextField: TextViewWithIRCFormatter!

	private var topicLengthAlertDisplayed = false

	@objc(initWithChannel:)
	public init(channel: IRCChannel) {
		super.init(window: nil)

		client = channel.associatedClient
		clientId = channel.associatedClient!.uniqueIdentifier
		self.channel = channel
		channelId = channel.uniqueIdentifier

		prepareInitialState()
	}

	private func prepareInitialState() {
		Bundle.main.loadNibNamed("TDCChannelModifyTopicSheet", owner: self, topLevelObjects: nil)

		headerTitleTextField.stringValue = String(format: headerTitleTextField.stringValue, channel.name)

		topicValueTextField.preferredFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)
		topicValueTextField.preferredFontColor = NSColor.textColor

		if let topic = channel.topic {
			topicValueTextField.stringValueWithIRCFormatting = topic
		}
	}

	@objc public func start() {
		startSheet()
	}

	@objc public func textDidChange(_ notification: Notification) {
		topicValueTextField.textDidChange(notification)
		updateTopicLengthAlert()
	}

	private func updateTopicLengthAlert() {
		let maximumTopicLength = client.supportInfo.maximumTopicLength

		if maximumTopicLength == 0 {
			return
		}

		if topicValueTextField.stringLength <= Int(maximumTopicLength) {
			return
		}

		if topicLengthAlertDisplayed == false {
			topicLengthAlertDisplayed = true
		} else {
			return
		}

		TDCAlert.alertSheet(
			with: sheet,
			body: LocalizedKey("TDCChannelModifyTopicSheet[zm4-cr]"),
			title: LocalizedKey(
				"TDCChannelModifyTopicSheet[27l-qx]",
				client.networkNameAlt,
				maximumTopicLength
			),
			defaultButton: LocalizedKey("Prompts[c7s-dq]"),
			alternateButton: nil,
			otherButton: nil,
			suppressionKey: "maximum_topic_length",
			suppressionText: nil,
			completionBlock: nil
		)
	}

	@objc public func textView(_: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
		if commandSelector == #selector(NSResponder.insertNewline(_:)) {
			ok(nil)
			return true
		}

		if commandSelector == #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)) {
			return true
		}

		return false
	}

	@IBAction override public func ok(_: Any?) {
		let formattedTopic = topicValueTextField.stringValueWithIRCFormatting
		let topicWithoutNewlines = formattedTopic.replacingOccurrences(of: "\n", with: " ")

		let selector = NSSelectorFromString("channelModifyTopicSheet:onOk:")
		if let delegate, delegate.responds(to: selector) {
			_ = delegate.perform(selector, with: self, with: topicWithoutNewlines)
		}

		super.ok(nil)
	}

	@objc public func windowWillClose(_: Notification) {
		let selector = NSSelectorFromString("channelModifyTopicSheetWillClose:")
		if let delegate, delegate.responds(to: selector) {
			_ = delegate.perform(selector, with: self)
		}
	}
}
