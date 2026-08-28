/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2018 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import AppKit

@objc(TVCErrorMessagePopoverDelegate)
@MainActor
public protocol ErrorMessagePopoverDelegate: AnyObject {
	@objc optional func errorMessagePopoverWillShow(_ popover: ErrorMessagePopover)
	@objc optional func errorMessagePopoverDidShow(_ popover: ErrorMessagePopover)
	@objc optional func errorMessagePopoverWillClose(_ popover: ErrorMessagePopover)
	@objc optional func errorMessagePopoverDidClose(_ popover: ErrorMessagePopover)
}

private enum Layout {
	static let messageMaximumWidth = 330.0
	static let messageHorizontalPadding = 5.0
	static let messageVerticalPadding = 5.0
	static let errorIconWidth = 15.0
	static let errorIconHeight = 15.0
	static let errorIconHorizontalPadding = 5.0
	static let errorIconVerticalPadding = 6.0
}

@objc(TVCErrorMessagePopoverView)
private final class ErrorMessagePopoverView: NSPopover {
	override func mouseDown(with _: NSEvent) {
		close()
	}
}

@objc(TVCErrorMessagePopover)
@MainActor
public final class ErrorMessagePopover: NSObject, NSPopoverDelegate {
	@objc public weak var delegate: ErrorMessagePopoverDelegate?

	@objc public private(set) var message: String
	@objc public private(set) weak var view: NSView?

	private var popover: NSPopover?

	@available(*, unavailable)
	override public init() {
		fatalError("init() is unavailable; use init(message:relativeTo:)")
	}

	@objc(initWithMessage:relativeToView:)
	public init(message: String, relativeTo view: NSView) {
		self.message = message
		self.view = view
		super.init()
	}

	isolated deinit {
		close()
	}

	private func createPopover() {
		let viewController = NSViewController()
		let popoverView = NSView(frame: .zero)
		popoverView.translatesAutoresizingMaskIntoConstraints = false
		viewController.view = popoverView

		let errorIcon = NSImageView()
		errorIcon.translatesAutoresizingMaskIntoConstraints = false
		errorIcon.isEditable = false

		let errorImage = NSImage(
			systemSymbolName: "exclamationmark.circle.fill",
			accessibilityDescription: AccessibilityStrings.errorIcon
		)

		let errorImageConfiguration = NSImage.SymbolConfiguration(pointSize: 16.0, weight: .regular, scale: .large)
			.applying(
				NSImage.SymbolConfiguration(paletteColors: [.white, .systemRed])
			)

		errorIcon.image = errorImage?.withSymbolConfiguration(errorImageConfiguration)

		NSLayoutConstraint.activate([
			errorIcon.widthAnchor.constraint(equalToConstant: Layout.errorIconWidth),
			errorIcon.heightAnchor.constraint(equalToConstant: Layout.errorIconHeight),
			errorIcon.leadingAnchor.constraint(
				equalTo: popoverView.leadingAnchor,
				constant: Layout.errorIconHorizontalPadding
			),
			errorIcon.topAnchor.constraint(
				equalTo: popoverView.topAnchor,
				constant: Layout.errorIconVerticalPadding
			),
		])

		popoverView.addSubview(errorIcon)

		let errorMessage = NSTextField(labelWithString: message)
		errorMessage.translatesAutoresizingMaskIntoConstraints = false
		errorMessage.isEditable = false
		errorMessage.isBordered = false
		errorMessage.drawsBackground = false
		errorMessage.cell?.wraps = true
		errorMessage.preferredMaxLayoutWidth = Layout.messageMaximumWidth

		popoverView.addSubview(errorMessage)

		NSLayoutConstraint.activate([
			errorMessage.leadingAnchor.constraint(
				equalTo: errorIcon.trailingAnchor,
				constant: Layout.messageHorizontalPadding
			),
			errorMessage.trailingAnchor.constraint(
				equalTo: popoverView.trailingAnchor,
				constant: -Layout.messageHorizontalPadding
			),
			errorMessage.topAnchor.constraint(
				equalTo: popoverView.topAnchor,
				constant: Layout.messageVerticalPadding
			),
			errorMessage.bottomAnchor.constraint(
				equalTo: popoverView.bottomAnchor,
				constant: -Layout.messageVerticalPadding
			),
		])

		let popover = ErrorMessagePopoverView()
		popover.delegate = self
		popover.contentViewController = viewController
		popover.behavior = .transient
		popover.animates = false

		self.popover = popover
	}

	@objc(showRelativeToRect:)
	public func showRelative(to rect: NSRect) {
		showRelative(to: rect, preferredEdge: .maxY)
	}

	@objc(showRelativeToRect:preferredEdge:)
	public func showRelative(to rect: NSRect, preferredEdge: NSRectEdge) {
		if popover == nil {
			createPopover()
		}

		guard let view, let popover else {
			return
		}

		popover.show(relativeTo: rect, of: view, preferredEdge: preferredEdge)

		NSAccessibility.post(
			element: view,
			notification: .announcementRequested,
			userInfo: [
				NSAccessibility.NotificationUserInfoKey.announcement: message,
				NSAccessibility.NotificationUserInfoKey.priority: NSAccessibilityPriorityLevel.high.rawValue,
			]
		)
	}

	@objc public func close() {
		guard let popover else {
			return
		}

		popover.close()
		self.popover = nil
	}

	public func popoverWillShow(_: Notification) {
		delegate?.errorMessagePopoverWillShow?(self)
	}

	public func popoverDidShow(_: Notification) {
		delegate?.errorMessagePopoverDidShow?(self)
	}

	public func popoverWillClose(_: Notification) {
		delegate?.errorMessagePopoverWillClose?(self)
	}

	public func popoverDidClose(_: Notification) {
		delegate?.errorMessagePopoverDidClose?(self)
	}
}
