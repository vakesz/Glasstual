/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\\_\\__|\\__,_|\\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import AppKit

@objc(TDCChannelSpotlightSearchResultCellView)
public final class ChannelSpotlightSearchResultCellView: NSTableCellView {
	@IBOutlet private weak var channelNameField: NSTextField!
	@IBOutlet private weak var keyboardShortcutField: NSTextField!
	@IBOutlet private weak var keyboardShortcutFieldOffsetConstraint: NSLayoutConstraint!
	@IBOutlet private weak var unreadCountDescriptionField: NSTextField!

	private var observedChannel: IRCChannel?

	override public var wantsLayer: Bool {
		get { true }
		set {}
	}

	override public var layerContentsRedrawPolicy: NSView.LayerContentsRedrawPolicy {
		get { .onSetNeedsDisplay }
		set {}
	}

	override public func updateLayer() {
		updateAppearance()
		keyboardShortcutChanged()
	}

	private func setInitialValues() {
		channelNameChanged()
	}

	private func updateAppearance() {
		updateTextFieldTextColor(isSelected: rowCell.isSelected)
	}

	private func updateTextFieldTextColor(isSelected: Bool) {
		let appearance = userInterfaceObjects
		let rowCell = self.rowCell

		/* Selection is drawn by AppKit. Only the text colours follow it:
		 an emphasized (key window) selection is drawn with the accent
		 colour and needs the alternate text colour, every other state
		 uses the vibrant label colours. */
		if isSelected, rowCell.isEmphasized {
			let selectedTextColor = NSColor.alternateSelectedControlTextColor
			channelNameField.textColor = selectedTextColor
			unreadCountDescriptionField.textColor = selectedTextColor
			keyboardShortcutField.textColor = selectedTextColor
		} else {
			channelNameField.textColor = .labelColor
			unreadCountDescriptionField.textColor = .secondaryLabelColor
			keyboardShortcutField.textColor = isSelected ? .labelColor : .secondaryLabelColor
		}

		if isSelected {
			keyboardShortcutFieldOffsetConstraint.constant = appearance.searchResultKeyboardShortcutSelectedOffset
		} else {
			keyboardShortcutFieldOffsetConstraint.constant = appearance.searchResultKeyboardShortcutDeselectedOffset
		}
	}

	@objc public var channelName: NSAttributedString {
		guard let searchResult = objectValue as? ChannelSpotlightSearchResult,
			let channel = searchResult.channel
		else {
			return NSAttributedString()
		}

		let paragraphStyle = NSParagraphStyle.default.mutableCopy() as! NSMutableParagraphStyle
		paragraphStyle.lineBreakMode = .byTruncatingTail

		let channelName = channel.name
		let channelNameFieldFont = channelNameField.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)

		let resultString = NSMutableAttributedString(
			string: LocalizedKey("TDCChannelSpotlightController[jpw-cj]", channelName),
			attributes: [
				.font: channelNameFieldFont,
				.paragraphStyle: paragraphStyle,
			]
		)

		let searchString = controller.searchString
		(resultString.string as NSString).enumerateFirstOccurrenceOfCharacters(
			in: searchString,
			with: { range, _ in
				let boldFont = NSFontManager.shared.convert(channelNameFieldFont, toHaveTrait: .boldFontMask)
				resultString.addAttribute(.font, value: boldFont, range: range)
			},
			options: .caseInsensitive
		)

		let networkName = channel.associatedClient?.networkNameAlt ?? ""
		resultString.append(
			NSAttributedString(string: LocalizedKey("TDCChannelSpotlightController[z68-5q]", networkName))
		)

		return resultString
	}

	private func channelNameChanged() {
		willChangeValue(forKey: "channelName")
		didChangeValue(forKey: "channelName")
	}

	@objc public var keyboardShortcut: String {
		guard let searchResult = objectValue as? ChannelSpotlightSearchResult else {
			return ""
		}

		let searchResults = controller.searchResultsFiltered
		guard let searchResultIndex = searchResults.firstIndex(where: { $0 === searchResult }) else {
			return ""
		}

		if searchResultIndex == controller.selectedSearchResult {
			return "↩︎"
		}

		if searchResultIndex > 9 {
			return ""
		}

		var keyboardShortcutIndex = searchResultIndex + 1
		if keyboardShortcutIndex == 10 {
			keyboardShortcutIndex = 0
		}

		return "⌘\(keyboardShortcutIndex)"
	}

	private func keyboardShortcutChanged() {
		willChangeValue(forKey: "keyboardShortcut")
		didChangeValue(forKey: "keyboardShortcut")
	}

	@objc public var unreadCountDescription: String {
		guard let searchResult = objectValue as? ChannelSpotlightSearchResult,
			let channel = searchResult.channel
		else {
			return ""
		}

		let nicknameHighlightCount = channel.nicknameHighlightCount
		let nicknameHighlightCountDescription: String

		if nicknameHighlightCount == 1 {
			nicknameHighlightCountDescription = LocalizedKey(
				"TDCChannelSpotlightController[0lz-oh]",
				formattedNumber(Int(nicknameHighlightCount)) as String
			)
		} else {
			nicknameHighlightCountDescription = LocalizedKey(
				"TDCChannelSpotlightController[c4u-21]",
				formattedNumber(Int(nicknameHighlightCount)) as String
			)
		}

		let unreadCount = channel.treeUnreadCount
		let unreadCountDescription: String

		if unreadCount == 1 {
			unreadCountDescription = LocalizedKey(
				"TDCChannelSpotlightController[43s-x4]",
				formattedNumber(Int(unreadCount)) as String
			)
		} else {
			unreadCountDescription = LocalizedKey(
				"TDCChannelSpotlightController[vzj-30]",
				formattedNumber(Int(unreadCount)) as String
			)
		}

		return LocalizedKey(
			"TDCChannelSpotlightController[et7-c5]",
			nicknameHighlightCountDescription,
			unreadCountDescription
		)
	}

	private func unreadCountDescriptionChanged() {
		willChangeValue(forKey: "unreadCountDescription")
		didChangeValue(forKey: "unreadCountDescription")
		updateAccessibilityLabel()
	}

	private func updateAccessibilityLabel() {
		guard let searchResult = objectValue as? ChannelSpotlightSearchResult,
			let channel = searchResult.channel
		else {
			setAccessibilityLabel(nil)
			return
		}

		let channelName = channel.name
		let networkName = channel.associatedClient?.networkNameAlt ?? ""
		let label =
			LocalizedKey("TDCChannelSpotlightController[jpw-cj]", channelName)
				+ LocalizedKey("TDCChannelSpotlightController[z68-5q]", networkName)

		setAccessibilityLabel(LocalizedKey("TDCChannelSpotlightController[et7-c5]", label, unreadCountDescription))
	}

	private var rowCell: ChannelSpotlightSearchResultRowView {
		superview as! ChannelSpotlightSearchResultRowView
	}

	private var userInterfaceObjects: ChannelSpotlightAppearance {
		rowCell.userInterfaceObjects
	}

	private var controller: ChannelSpotlightController {
		rowCell.controller
	}

	override public func viewDidMoveToWindow() {
		super.viewDidMoveToWindow()
		updateObservedChannel()
	}

	override public var objectValue: Any? {
		didSet {
			/* Cells are reused. The channel this cell represents can change
			 after the cell has already been placed in a window, so the
			 observation must follow the object value, not the window. */
			updateObservedChannel()
		}
	}

	override public func prepareForReuse() {
		super.prepareForReuse()
		stopObservingChannel()
	}

	deinit {
		stopObservingChannel()
	}

	private func updateObservedChannel() {
		var channel: IRCChannel?

		if window != nil, let searchResult = objectValue as? ChannelSpotlightSearchResult {
			channel = searchResult.channel
		}

		if channel === observedChannel {
			return
		}

		stopObservingChannel()

		guard let channel else {
			return
		}

		observedChannel = channel

		channel.addObserver(
			self,
			forKeyPath: "nicknameHighlightCount",
			options: [.initial, .new],
			context: nil
		)
		channel.addObserver(
			self,
			forKeyPath: "treeUnreadCount",
			options: [.initial, .new],
			context: nil
		)

		setInitialValues()
	}

	private func stopObservingChannel() {
		guard let channel = observedChannel else {
			return
		}

		channel.removeObserver(self, forKeyPath: "nicknameHighlightCount")
		channel.removeObserver(self, forKeyPath: "treeUnreadCount")
		observedChannel = nil
	}

	override public func observeValue(
		forKeyPath keyPath: String?,
		of _: Any?,
		change _: [NSKeyValueChangeKey: Any]?,
		context _: UnsafeMutableRawPointer?
	) {
		if keyPath == "nicknameHighlightCount" || keyPath == "treeUnreadCount" {
			unreadCountDescriptionChanged()
		}
	}
}

// MARK: -

@objc(TDCChannelSpotlightSearchResultRowView)
public final class ChannelSpotlightSearchResultRowView: NSTableRowView {
	@objc public private(set) weak var controller: ChannelSpotlightController!
	private weak var childCellStorage: ChannelSpotlightSearchResultCellView?

	@objc(initWithController:)
	public init(controller: ChannelSpotlightController) {
		self.controller = controller
		super.init(frame: .zero)
	}

	@available(*, unavailable)
	public required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override public var isSelected: Bool {
		didSet {
			if isSelected == false, invalidatingBackgroundForSelection {
				return
			}

			setNeedsDisplayOnChild()
		}
	}

	private func setNeedsDisplayOnChild() {
		childCell?.needsDisplay = true
	}

	override public var isEmphasized: Bool {
		didSet {
			setNeedsDisplayOnChild()
		}
	}

	private var childCell: ChannelSpotlightSearchResultCellView? {
		if childCellStorage == nil {
			if numberOfColumns == 0 {
				return nil
			}

			childCellStorage = view(atColumn: 0) as? ChannelSpotlightSearchResultCellView
		}

		return childCellStorage
	}

	@objc public var userInterfaceObjects: ChannelSpotlightAppearance {
		controller.userInterfaceObjects
	}
}
