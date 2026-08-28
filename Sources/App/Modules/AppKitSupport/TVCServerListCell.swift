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
import CocoaExtensions

/* Badge metrics track the sidebar's text size rather than a fixed table. */
private let unreadBadgeMinimumWidth: CGFloat = 22.0
private let unreadBadgeHeight: CGFloat = 16.0
private let unreadBadgeTextPadding: CGFloat = 7.0

private func nativeChannel(from item: IRCTreeItem?) -> IRCChannel? {
	(item as AnyObject?) as? IRCChannel
}

private final class ServerListCellDrawingContext: NSObject {
	var isActive = false
	var isGroupItem = false
	var isSelected = false
	var isSelectedFrontmost = false
	var isWindowActive = false
}

@objc(TVCServerListCell)
public class ServerListCell: NSTableCellView {
	@IBOutlet private var cellTextField: NSTextField!
	@IBOutlet private var messageCountBadgeImageView: NSImageView!
	/* Deactivating the constraints will dereference them.
	 We need to maintain a strong reference. */
	@IBOutlet private var messageCountBadgeLeadingConstraint: NSLayoutConstraint!
	@IBOutlet private var messageCountBadgeTrailingConstraint: NSLayoutConstraint!

	@objc
	public func defineConstraints() {}

	override public var wantsUpdateLayer: Bool {
		true
	}

	override public var layerContentsRedrawPolicy: NSView.LayerContentsRedrawPolicy {
		get { .onSetNeedsDisplay }
		set { super.layerContentsRedrawPolicy = newValue }
	}

	override public func updateLayer() {
		updateDrawing()
	}

	private func updateDrawing() {
		let drawingContext = drawingContext
		updateTextField(in: drawingContext)
		updateDrawing(in: drawingContext)
	}

	private func updateTextField(in drawingContext: ServerListCellDrawingContext) {
		guard let cellItem else {
			return
		}

		let stringValueNew = cellItem.label

		if cellTextField.stringValue != stringValueNew {
			cellTextField.stringValue = stringValueNew
		}

		/* The accessibility description spells out the state as well as the name, so
		 it is rebuilt on every pass. Returning early when only the name is unchanged
		 left VoiceOver announcing a channel as joined after it had been parted. */
		let isActive = drawingContext.isActive
		let isGroupItem = drawingContext.isGroupItem

		var accessibilityDescription: String

		if isGroupItem {
			if isActive {
				accessibilityDescription = AccessibilityStrings.connectedServer(stringValueNew)
			} else {
				accessibilityDescription = AccessibilityStrings.disconnectedServer(stringValueNew)
			}
		} else {
			guard let channel = nativeChannel(from: cellItem) else {
				return
			}

			if channel.isChannel == false {
				accessibilityDescription = AccessibilityStrings.privateMessageQuery(with: stringValueNew)
			} else if isActive {
				accessibilityDescription = AccessibilityStrings.joinedChannel(stringValueNew)
			} else {
				accessibilityDescription = AccessibilityStrings.unjoinedChannel(stringValueNew)
			}

			/* Unread and highlight counts are part of what the row
			 communicates visually (the badge), so they are spoken too. */
			if let unreadDescription = accessibilityUnreadDescription(for: channel) {
				accessibilityDescription = ChannelSpotlightStrings.combined(
					accessibilityDescription,
					unreadDescription
				)
			}

			/* The symbol in front of the name repeats what the text
			 already says. Hide it from VoiceOver instead of giving it
			 an empty label which is read as "image". */
			imageView?.cell?.setAccessibilityElement(false)
		}

		cellTextField.cell?.setAccessibilityValueDescription(accessibilityDescription)
		setAccessibilityLabel(accessibilityDescription)
	}

	private func accessibilityUnreadDescription(for channel: IRCChannel) -> String? {
		let unreadCount = channel.treeUnreadCount

		guard unreadCount > 0 else {
			return nil
		}

		let unreadCountDescription = ChannelSpotlightStrings.unreadMessages(Int(unreadCount))

		let nicknameHighlightCount = channel.nicknameHighlightCount

		if nicknameHighlightCount == 0 || channel.config.ignoreHighlights {
			return unreadCountDescription
		}

		let nicknameHighlightCountDescription = ChannelSpotlightStrings.highlights(Int(nicknameHighlightCount))

		return ChannelSpotlightStrings.combined(
			unreadCountDescription,
			nicknameHighlightCountDescription
		)
	}

	private func updateDrawing(in drawingContext: ServerListCellDrawingContext) {
		let isGroupItem = drawingContext.isGroupItem
		let isActive = drawingContext.isActive

		if isGroupItem == false, let cellItem {
			guard let channel = nativeChannel(from: cellItem) else {
				return
			}

			var symbolName = "person.fill"

			if channel.isChannel {
				symbolName = "number"
			} else if channel.isDirectChat {
				symbolName = "bubble.left.and.bubble.right.fill"
			}

			let icon = NSImage(systemSymbolName: symbolName, accessibilityDescription: channel.name)
			icon?.isTemplate = true

			imageView?.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12.0, weight: .medium)
			imageView?.contentTintColor = isActive ? .secondaryLabelColor : .tertiaryLabelColor
			imageView?.image = icon
		}

		cellTextField.attributedStringValue = attributedTextFieldValue(in: drawingContext)

		if isGroupItem == false {
			populateMessageCountBadge(in: drawingContext)
		}
	}

	private func attributedTextFieldValue(in drawingContext: ServerListCellDrawingContext) -> NSAttributedString {
		let isActive = drawingContext.isActive
		let isGroupItem = drawingContext.isGroupItem
		let isSelected = drawingContext.isSelected

		var isHighlight = false
		var isErroneous = false

		if isGroupItem == false, let associatedChannel = nativeChannel(from: cellItem) {
			isErroneous = associatedChannel.errorOnLastJoinAttempt
			isHighlight = associatedChannel.nicknameHighlightCount > 0
		}

		let stringValue = cellTextField.attributedStringValue
		let mutableStringValue = NSMutableAttributedString(attributedString: stringValue)

		mutableStringValue.beginEditing()

		let controlFont: NSFont
		let controlColor: NSColor

		if isGroupItem {
			controlFont = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
			controlColor = .labelColor
		} else {
			controlFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)

			/* On a selected row the label colours are swapped by AppKit to suit
			 the selection fill; a fixed red or blue would not be. */
			if isErroneous, isSelected == false {
				controlColor = .systemRed
			} else if isActive, isHighlight, isSelected == false {
				controlColor = .systemBlue
			} else if isActive == false {
				controlColor = .tertiaryLabelColor
			} else {
				controlColor = .labelColor
			}
		}

		let stringValueRange = NSRange(location: 0, length: stringValue.length)
		mutableStringValue.addAttribute(.font, value: controlFont, range: stringValueRange)
		mutableStringValue.addAttribute(.foregroundColor, value: controlColor, range: stringValueRange)

		/* Mark connections secured by TLS alongside the name they belong to, which
		 keeps the indicator visible for every connection instead of only whichever
		 one happens to be frontmost. */
		if isGroupItem, let securedBadge = attributedSecuredBadge(for: cellItem as? IRCClient) {
			mutableStringValue.append(securedBadge)
		}

		mutableStringValue.endEditing()

		return mutableStringValue
	}

	private func attributedSecuredBadge(for client: IRCClient?) -> NSAttributedString? {
		guard let client, client.isSecured else {
			return nil
		}

		let symbolConfiguration = NSImage.SymbolConfiguration(
			pointSize: 9.0,
			weight: .semibold,
			scale: .small
		)

		guard let lockImage = NSImage(
			systemSymbolName: "lock.fill",
			accessibilityDescription: MainWindowStrings.Toolbar.connectionSecurity
		)?.withSymbolConfiguration(symbolConfiguration) else {
			return nil
		}

		let attachment = NSTextAttachment()
		attachment.image = lockImage

		let badge = NSMutableAttributedString(string: " ")
		badge.append(NSAttributedString(attachment: attachment))
		badge.addAttribute(
			.foregroundColor,
			value: NSColor.secondaryLabelColor,
			range: NSRange(location: 0, length: badge.length)
		)

		return badge
	}

	// MARK: - Badge Drawing

	@objc
	public func populateMessageCountBadge() {
		populateMessageCountBadge(in: drawingContext)
	}

	private func populateMessageCountBadge(in drawingContext: ServerListCellDrawingContext) {
		let isSelected = drawingContext.isSelected
		let isSelectedFrontmost = drawingContext.isSelectedFrontmost
		let isWindowActive = drawingContext.isWindowActive
		let multipleRowsSelected = (serverList?.numberOfSelectedRows ?? 0) > 1

		guard let associatedChannel = nativeChannel(from: cellItem) else {
			return
		}

		var drawMessageBadge =
			isSelected == false
				|| (isSelectedFrontmost == false && isSelected && multipleRowsSelected)
				|| (isWindowActive == false && isSelected)

		if associatedChannel.config.showTreeBadgeCount == false {
			drawMessageBadge = false
		}

		let treeUnreadCount = associatedChannel.treeUnreadCount
		var isHighlight = associatedChannel.nicknameHighlightCount > 0

		if associatedChannel.config.ignoreHighlights {
			isHighlight = false
		}

		if treeUnreadCount == 0 || drawMessageBadge == false {
			messageCountBadgeImageView.image = nil
			messageCountBadgeImageView.cell?.setAccessibilityElement(false)

			/* Disable constraints when badge is not visible to
			 allow text field to hug the right of the table view. */
			messageCountBadgeLeadingConstraint.isActive = false
			messageCountBadgeTrailingConstraint.isActive = false

			return
		}

		/* The inverted palette only matches the accent fill that is drawn
		 while the window is active; an inactive selection is grey. */
		messageCountBadgeImageView.image = messageCountBadge(
			forCount: UInt(max(0, treeUnreadCount)),
			isHighlight: isHighlight,
			isSelected: isSelected && isWindowActive
		)

		/* The count is already spoken as part of the row label; the badge
		 itself is decorative for VoiceOver. */
		messageCountBadgeImageView.cell?.setAccessibilityElement(false)

		messageCountBadgeLeadingConstraint.isActive = true
		messageCountBadgeTrailingConstraint.isActive = true
	}

	private func messageCountBadgeHighlightColorByUser() -> NSColor? {
		guard let color = TextualUserDefaults.shared().color(
			forKey: "Server List Unread Message Count Badge Colors -> Highlight"
		),
			color != .clear
		else {
			return nil
		}

		return color
	}

	private func messageCountBadge(
		forCount messageCount: UInt,
		isHighlight: Bool,
		isSelected: Bool
	) -> NSImage {
		let backgroundColor: NSColor
		let textColor: NSColor

		if isSelected {
			/* Invert against the row's selection fill so the badge stays legible. */
			backgroundColor = .alternateSelectedControlTextColor
			textColor = .selectedContentBackgroundColor
		} else if isHighlight {
			backgroundColor = messageCountBadgeHighlightColorByUser() ?? .controlAccentColor
			textColor = .alternateSelectedControlTextColor
		} else {
			/* tertiaryLabelColor is already translucent; scaling it again left the
			 capsule at roughly 9% alpha, which read as no capsule at all. The system
			 fill colors are the semantic answer for a shape behind small text. */
			backgroundColor = .secondarySystemFill
			textColor = .secondaryLabelColor
		}

		let controlFont = NSFont.monospacedDigitSystemFont(ofSize: 11.0, weight: .medium)

		let paragraphStyle = NSMutableParagraphStyle()
		paragraphStyle.alignment = .center

		let stringToDraw = NSAttributedString(
			string: formattedNumber(Int(messageCount)) as String,
			attributes: [
				.foregroundColor: textColor,
				.font: controlFont,
				.paragraphStyle: paragraphStyle,
			]
		)

		let badgeWidth = max(
			stringToDraw.size().width + (unreadBadgeTextPadding * 2.0),
			unreadBadgeMinimumWidth
		)

		return NSImage(size: NSSize(width: badgeWidth, height: unreadBadgeHeight), flipped: false) { dstRect in
			backgroundColor.setFill()

			NSBezierPath(
				roundedRect: dstRect,
				xRadius: dstRect.height / 2.0,
				yRadius: dstRect.height / 2.0
			).fill()

			/* Centre on the font's cap height so the digits sit optically level. */
			var textRect = dstRect
			textRect.origin.y = dstRect.midY - (controlFont.capHeight / 2.0) + controlFont.descender
			textRect.size.height = dstRect.height - textRect.origin.y

			stringToDraw.draw(in: textRect)

			return true
		}
	}

	// MARK: - Cell Information

	private var isGroupItem: Bool {
		self is ServerListCellGroupItem
	}

	private var rowCell: ServerListRowCell? {
		superview as? ServerListRowCell
	}

	private var cellItem: IRCTreeItem? {
		objectValue as? IRCTreeItem
	}

	private var serverList: ServerList? {
		rowCell?.serverList
	}

	private var drawingContext: ServerListCellDrawingContext {
		let drawingContext = ServerListCellDrawingContext()

		guard let serverList, let cellItem else {
			return drawingContext
		}

		let rowIndex = serverList.row(forItem: cellItem)

		drawingContext.isActive = cellItem.isActive
		drawingContext.isGroupItem = isGroupItem
		drawingContext.isSelected = serverList.isRowSelected(rowIndex)
		drawingContext.isSelectedFrontmost = mainWindow?.isItemSelected(cellItem) ?? false
		drawingContext.isWindowActive = mainWindow?.ceIsActiveForDrawing ?? false

		return drawingContext
	}

	override public var needsDisplayWhenApplicationAppearanceChanges: Bool {
		false
	}

	override public var needsDisplayWhenSystemAppearanceChanges: Bool {
		false
	}
}

@objc(TVCServerListCellGroupItem)
public final class ServerListCellGroupItem: ServerListCell {}

@objc(TVCServerListCellChildItem)
public final class ServerListCellChildItem: ServerListCell {
	override public func defineConstraints() {
		guard let imageView else {
			return
		}

		imageView.imageScaling = .scaleProportionallyUpOrDown

		/* Only the width is pinned. Symbols differ in width, and the label is laid
		 out against the trailing edge of this view, so without a fixed width the
		 names in the list do not line up with one another. The height is left
		 alone: the nib already fixes it by insetting the image view from the top
		 and the bottom of the row, and adding a height here conflicts with that. */
		for constraint in imageView.constraints where constraint.firstAttribute == .width {
			return
		}

		imageView.widthAnchor.constraint(equalToConstant: 16.0).isActive = true
	}
}

// MARK: - Row Cell

@objc(TVCServerListRowCell)
public class ServerListRowCell: NSTableRowView {
	@objc public private(set) weak var serverList: ServerList?
	private weak var cachedChildCell: ServerListCell?

	@objc(initWithServerList:)
	public init(serverList: ServerList) {
		self.serverList = serverList
		super.init(frame: .zero)
	}

	@available(*, unavailable)
	required init?(coder _: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override public func drawDraggingDestinationFeedback(in _: NSRect) {
		/* Do nothing for this... */
	}

	override public var isSelected: Bool {
		didSet {
			setNeedsDisplayOnChild()
		}
	}

	private func setNeedsDisplayOnChild() {
		childCell?.needsDisplay = true
	}

	/** AppKit emphasizes a selection only while the window is key. Mail and
	 Finder keep the accent fill while a sheet or panel is key, so emphasis
	 follows main-window status instead. Both the getter and the background
	 style are overridden so that drawing and text colours agree regardless
	 of whether AppKit consults the accessor or the stored value. */
	override public var isEmphasized: Bool {
		get {
			guard let window else {
				return super.isEmphasized
			}

			return window.isMainWindow
		}
		set {
			if let window {
				super.isEmphasized = window.isMainWindow
			} else {
				super.isEmphasized = newValue
			}

			setNeedsDisplayOnChild()
		}
	}

	@objc
	public func refreshEmphasis() {
		isEmphasized = isEmphasized
	}

	override public var interiorBackgroundStyle: NSView.BackgroundStyle {
		if isSelected, isEmphasized {
			return .emphasized
		}

		return super.interiorBackgroundStyle
	}

	override public func didAddSubview(_ subview: NSView) {
		childCell?.defineConstraints()
		super.didAddSubview(subview)
	}

	private var childCell: ServerListCell? {
		if cachedChildCell == nil {
			if numberOfColumns == 0 {
				return nil
			}

			cachedChildCell = view(atColumn: 0) as? ServerListCell
		}

		return cachedChildCell
	}

	private var isGroupItem: Bool {
		self is ServerListGroupRowCell
	}

	override public func accessibilityLabel() -> String? {
		if let label = childCell?.accessibilityLabel(), label.isEmpty == false {
			return label
		}

		return super.accessibilityLabel()
	}
}

@objc(TVCServerListGroupRowCell)
public final class ServerListGroupRowCell: ServerListRowCell {}

@objc(TVCServerListChildRowCell)
public final class ServerListChildRowCell: ServerListRowCell {}
