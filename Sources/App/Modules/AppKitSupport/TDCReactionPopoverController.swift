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

@objc(TDCReactionPopoverController)
@MainActor
public final class ReactionPopoverController: NSViewController, NSPopoverDelegate, NSTextFieldDelegate {
	@objc public private(set) var messageIdentifier: String
	@objc public var completionBlock: ((String, String) -> Void)?

	private var popover: NSPopover?
	private var emojiField: NSTextField!
	private var sendButton: NSButton!

	@objc(initWithMessageIdentifier:)
	public init(messageIdentifier: String) {
		self.messageIdentifier = messageIdentifier
		super.init(nibName: nil, bundle: nil)
	}

	@available(*, unavailable)
	public required init?(coder _: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override public func loadView() {
		let view = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 44))

		let field = NSTextField(frame: .zero)
		field.translatesAutoresizingMaskIntoConstraints = false
		field.placeholderString = LocalizedKey("TXMenuController[rct-ph]")
		field.font = NSFont.systemFont(ofSize: 16.0)
		field.alignment = .center
		field.delegate = self
		field.bezelStyle = .roundedBezel
		field.usesSingleLineMode = true

		let send = NSButton(
			title: LocalizedKey("TXMenuController[rct-sd]"),
			target: self,
			action: #selector(send(_:))
		)
		send.translatesAutoresizingMaskIntoConstraints = false
		send.bezelStyle = .rounded
		send.keyEquivalent = "\r"
		send.isEnabled = false

		view.addSubview(field)
		view.addSubview(send)

		NSLayoutConstraint.activate([
			field.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12.0),
			field.centerYAnchor.constraint(equalTo: view.centerYAnchor),
			field.widthAnchor.constraint(equalToConstant: 120.0),

			send.leadingAnchor.constraint(equalTo: field.trailingAnchor, constant: 8.0),
			send.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12.0),
			send.firstBaselineAnchor.constraint(equalTo: field.firstBaselineAnchor),

			view.heightAnchor.constraint(equalToConstant: 44.0),
		])

		emojiField = field
		sendButton = send
		self.view = view
	}

	@objc(presentRelativeToRect:ofView:)
	public func present(relativeTo rect: NSRect, of view: NSView) {
		let popover = NSPopover()
		popover.behavior = .transient
		popover.contentViewController = self
		popover.delegate = self

		self.popover = popover
		popover.show(relativeTo: rect, of: view, preferredEdge: .maxY)

		self.view.window?.makeFirstResponder(emojiField)
	}

	@objc public func close() {
		popover?.close()
	}

	public func popoverDidClose(_: Notification) {
		popover = nil
	}

	private var emoji: String? {
		let value = emojiField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

		guard value.isEmpty == false else {
			return nil
		}

		let first = value.rangeOfComposedCharacterSequence(at: value.startIndex)
		return String(value[first])
	}

	public func controlTextDidChange(_: Notification) {
		sendButton.isEnabled = (emoji != nil)
	}

	@IBAction public func send(_: Any?) {
		guard let emoji else {
			return
		}

		completionBlock?(emoji, messageIdentifier)
		close()
	}
}
