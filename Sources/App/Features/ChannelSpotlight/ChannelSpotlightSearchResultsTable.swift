/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import AppKit
import CocoaExtensions
import Combine

@objc(TDCChannelSpotlightSearchResultCellView)
public final class ChannelSpotlightSearchResultCellView: NSTableCellView {
	@IBOutlet private var channelNameField: NSTextField!
	@IBOutlet private var keyboardShortcutField: NSTextField!
	@IBOutlet private var keyboardShortcutFieldOffsetConstraint: NSLayoutConstraint!
	@IBOutlet private var unreadCountDescriptionField: NSTextField!

	private var observedChannel: IRCChannel?
	/** Internal rather than private so the teardown on reuse can be tested;
	 nothing else has a reason to look at them. */
	private(set) var channelObservations: [Task<Void, Never>] = []

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
		keyboardShortcutChanged()
		unreadCountDescriptionChanged()
	}

	private func updateAppearance() {
		updateTextFieldTextColor(isSelected: rowCell.isSelected)
	}

	private func updateTextFieldTextColor(isSelected: Bool) {
		let appearance = userInterfaceObjects
		let rowCell = rowCell

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

	public var channelName: NSAttributedString {
		guard let searchResult = objectValue as? ChannelSpotlightSearchResult,
		      let channel = searchResult.channel
		else {
			return NSAttributedString()
		}

		guard let paragraphStyle = NSParagraphStyle.default.mutableCopy() as? NSMutableParagraphStyle else {
			return NSAttributedString()
		}
		paragraphStyle.lineBreakMode = .byTruncatingTail

		let channelName = channel.name
		let channelNameFieldFont = channelNameField.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)

		let resultString = NSMutableAttributedString(
			string: ChannelSpotlightStrings.channelName(channelName),
			attributes: [
				.font: channelNameFieldFont,
				.paragraphStyle: paragraphStyle,
			]
		)

		let searchString = controller.searchString
		let matchedRanges = resultString.string.rangesOfFirstOccurrences(
			ofCharactersIn: searchString,
			options: .caseInsensitive
		)

		if !matchedRanges.isEmpty {
			let boldFont = NSFontManager.shared.convert(channelNameFieldFont, toHaveTrait: .boldFontMask)

			for range in matchedRanges {
				resultString.addAttribute(.font, value: boldFont, range: range)
			}
		}

		let networkName = channel.associatedClient?.networkNameAlt ?? ""
		resultString.append(
			NSAttributedString(string: ChannelSpotlightStrings.networkSuffix(networkName))
		)

		return resultString
	}

	/// The three fields used to be pulled by bindings whenever the cell said the
	/// value had changed. Nothing is watching now, so the cell writes them.
	///
	/// Each is guarded on its outlet: a cell built in code has none, and the
	/// values below reach for the controller through the row view, which such a
	/// cell does not have either.
	private func channelNameChanged() {
		guard let channelNameField else {
			return
		}

		channelNameField.attributedStringValue = channelName
	}

	public var keyboardShortcut: String {
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
		guard let keyboardShortcutField else {
			return
		}

		keyboardShortcutField.stringValue = keyboardShortcut
	}

	public var unreadCountDescription: String {
		guard let searchResult = objectValue as? ChannelSpotlightSearchResult,
		      let channel = searchResult.channel
		else {
			return ""
		}

		let nicknameHighlightCount = channel.nicknameHighlightCount
		let nicknameHighlightCountDescription = ChannelSpotlightStrings.highlights(Int(nicknameHighlightCount))

		let unreadCount = channel.treeUnreadCount
		let unreadCountDescription = ChannelSpotlightStrings.unreadMessages(Int(unreadCount))

		return ChannelSpotlightStrings.combined(
			nicknameHighlightCountDescription,
			unreadCountDescription
		)
	}

	private func unreadCountDescriptionChanged() {
		unreadCountDescriptionField?.stringValue = unreadCountDescription

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
			ChannelSpotlightStrings.channelName(channelName)
				+ ChannelSpotlightStrings.networkSuffix(networkName)

		setAccessibilityLabel(ChannelSpotlightStrings.combined(label, unreadCountDescription))
	}

	private var rowCell: ChannelSpotlightSearchResultRowView {
		guard let rowCell = superview as? ChannelSpotlightSearchResultRowView else {
			preconditionFailure("Search-result content must be hosted by its row view")
		}

		return rowCell
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

		/* `observe(_:options:changeHandler:)` calls back nonisolated; awaiting
		 the same key paths inside main-actor tasks puts the redraw where the
		 cell lives. `.initial` is dropped with it — `setInitialValues()` below
		 already covers the first draw, and it does so synchronously. */
		channelObservations = [
			Task { @MainActor [weak self] in
				for await _ in channel.publisher(for: \.nicknameHighlightCount, options: [.new]).bufferedValues {
					guard let self else {
						return
					}

					unreadCountDescriptionChanged()
				}
			},
			Task { @MainActor [weak self] in
				for await _ in channel.publisher(for: \.treeUnreadCount, options: [.new]).bufferedValues {
					guard let self else {
						return
					}

					unreadCountDescriptionChanged()
				}
			},
		]

		setInitialValues()
	}

	private func stopObservingChannel() {
		channelObservations.forEach { $0.cancel() }
		channelObservations.removeAll()
		observedChannel = nil
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
	public required init?(coder _: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override public var isSelected: Bool {
		didSet {
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

	public var userInterfaceObjects: ChannelSpotlightAppearance {
		controller.userInterfaceObjects
	}
}
