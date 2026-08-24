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

@objc(TDCOnboardingStylePreviewView)
public final class OnboardingStylePreviewView: NSView {
	private var canvas: NSView!
	private var messageStack: NSStackView!
	private var titleField: NSTextField!
	private var descriptionField: NSTextField!
	private var checkmarkView: NSImageView!

	private var styleNameStorage = ""
	private var styleTitleStorage = ""
	private var styleDescriptionStorage = ""
	private var selectedStorage = false
	private var messageFontSizeStorage: CGFloat = 13

	@objc public var styleName: String {
		get { styleNameStorage }
		set {
			styleNameStorage = newValue
			rebuildMessages()
		}
	}

	@objc public var styleTitle: String {
		get { styleTitleStorage }
		set {
			styleTitleStorage = newValue
			titleField.stringValue = newValue
		}
	}

	@objc public var styleDescription: String {
		get { styleDescriptionStorage }
		set {
			styleDescriptionStorage = newValue
			descriptionField.stringValue = newValue
		}
	}

	@objc public var selected: Bool {
		@objc(isSelected) get { selectedStorage }
		@objc(setSelected:) set {
			selectedStorage = newValue
			updateSelectionAppearance()
		}
	}

	@objc public var messageFontSize: CGFloat {
		get { messageFontSizeStorage }
		set {
			messageFontSizeStorage = newValue
			rebuildMessages()
		}
	}

	@objc public weak var target: AnyObject?
	@objc public var action: Selector?

	override public init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		prepareInitialState()
	}

	public required init?(coder: NSCoder) {
		super.init(coder: coder)
		prepareInitialState()
	}

	private func prepareInitialState() {
		wantsLayer = true

		let canvas = NSView()
		canvas.wantsLayer = true
		canvas.layer?.cornerRadius = 10
		canvas.layer?.borderWidth = 1
		canvas.layer?.masksToBounds = true
		canvas.translatesAutoresizingMaskIntoConstraints = false

		let messageStack = NSStackView()
		messageStack.orientation = .vertical
		messageStack.alignment = .width
		messageStack.spacing = 6
		messageStack.translatesAutoresizingMaskIntoConstraints = false
		canvas.addSubview(messageStack)

		let titleField = NSTextField(labelWithString: "")
		titleField.font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
		titleField.alignment = .center
		titleField.translatesAutoresizingMaskIntoConstraints = false

		let descriptionField = NSTextField(labelWithString: "")
		descriptionField.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
		descriptionField.textColor = .secondaryLabelColor
		descriptionField.alignment = .center
		descriptionField.translatesAutoresizingMaskIntoConstraints = false

		let checkmarkView = NSImageView()
		checkmarkView.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)
		checkmarkView.contentTintColor = .controlAccentColor
		checkmarkView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 18, weight: .regular)
		checkmarkView.translatesAutoresizingMaskIntoConstraints = false

		addSubview(canvas)
		addSubview(titleField)
		addSubview(descriptionField)
		addSubview(checkmarkView)

		NSLayoutConstraint.activate([
			canvas.topAnchor.constraint(equalTo: topAnchor),
			canvas.leadingAnchor.constraint(equalTo: leadingAnchor),
			canvas.trailingAnchor.constraint(equalTo: trailingAnchor),
			canvas.heightAnchor.constraint(equalToConstant: 170),

			messageStack.topAnchor.constraint(equalTo: canvas.topAnchor, constant: 14),
			messageStack.leadingAnchor.constraint(equalTo: canvas.leadingAnchor, constant: 14),
			messageStack.trailingAnchor.constraint(equalTo: canvas.trailingAnchor, constant: -14),

			titleField.topAnchor.constraint(equalTo: canvas.bottomAnchor, constant: 10),
			titleField.centerXAnchor.constraint(equalTo: centerXAnchor),
			descriptionField.topAnchor.constraint(equalTo: titleField.bottomAnchor, constant: 2),
			descriptionField.centerXAnchor.constraint(equalTo: centerXAnchor),
			descriptionField.bottomAnchor.constraint(equalTo: bottomAnchor),

			checkmarkView.topAnchor.constraint(equalTo: canvas.topAnchor, constant: 8),
			checkmarkView.trailingAnchor.constraint(equalTo: canvas.trailingAnchor, constant: -8),
		])

		self.canvas = canvas
		self.messageStack = messageStack
		self.titleField = titleField
		self.descriptionField = descriptionField
		self.checkmarkView = checkmarkView

		updateSelectionAppearance()
	}

	override public func isAccessibilityElement() -> Bool {
		true
	}

	override public func accessibilityLabel() -> String? {
		styleTitle
	}

	override public func accessibilityRole() -> NSAccessibility.Role? {
		.radioButton
	}

	override public func accessibilityValue() -> Any? {
		selected
	}

	override public func accessibilityPerformPress() -> Bool {
		select()
		return true
	}

	override public func viewDidChangeEffectiveAppearance() {
		super.viewDidChangeEffectiveAppearance()
		updateLayerColors()
	}

	private func updateSelectionAppearance() {
		checkmarkView.isHidden = selected == false
		updateLayerColors()
	}

	private func updateLayerColors() {
		effectiveAppearance.performAsCurrentDrawingAppearance {
			canvas.layer?.backgroundColor = NSColor.textBackgroundColor.cgColor

			if selected {
				canvas.layer?.borderColor = NSColor.controlAccentColor.cgColor
				canvas.layer?.borderWidth = 2
			} else {
				canvas.layer?.borderColor = NSColor.separatorColor.cgColor
				canvas.layer?.borderWidth = 1
			}

			for row in messageStack.arrangedSubviews {
				for bubble in row.subviews {
					guard let identifier = bubble.identifier?.rawValue else {
						continue
					}

					let outgoing = identifier == "outgoing"
					bubble.layer?.backgroundColor =
						(outgoing ? NSColor.controlAccentColor : NSColor.unemphasizedSelectedContentBackgroundColor)
							.cgColor
				}
			}
		}
	}

	private var sampleMessages: [[String]] {
		[
			[LocalizedKey("TDCOnboardingWindow[lf1-n1]"), LocalizedKey("TDCOnboardingWindow[lf1-m1]")],
			[LocalizedKey("TDCOnboardingWindow[lf1-n2]"), LocalizedKey("TDCOnboardingWindow[lf1-m2]")],
			[LocalizedKey("TDCOnboardingWindow[lf1-n3]"), LocalizedKey("TDCOnboardingWindow[lf1-m3]")],
		]
	}

	private func rebuildMessages() {
		guard let messageStack else {
			return
		}

		for view in messageStack.arrangedSubviews {
			messageStack.removeArrangedSubview(view)
			view.removeFromSuperview()
		}

		let bubbles = styleName == "Bubbles"
		let messages = sampleMessages

		for (index, message) in messages.enumerated() {
			let outgoing = index == messages.count - 1
			let row =
				bubbles
					? bubbleRow(nickname: message[0], text: message[1], outgoing: outgoing, fontSize: messageFontSize)
					: lineRow(nickname: message[0], text: message[1], outgoing: outgoing, fontSize: messageFontSize)

			messageStack.addArrangedSubview(row)
		}

		updateLayerColors()
	}

	private func bubbleRow(nickname: String, text: String, outgoing: Bool, fontSize: CGFloat) -> NSView {
		let row = NSView()
		row.translatesAutoresizingMaskIntoConstraints = false

		let bubble = NSView()
		bubble.wantsLayer = true
		bubble.layer?.cornerRadius = 12
		bubble.identifier = NSUserInterfaceItemIdentifier(outgoing ? "outgoing" : "incoming")
		bubble.translatesAutoresizingMaskIntoConstraints = false
		row.addSubview(bubble)

		let textField = NSTextField(wrappingLabelWithString: text)
		textField.font = NSFont.systemFont(ofSize: fontSize)
		textField.textColor = outgoing ? .white : .labelColor
		textField.translatesAutoresizingMaskIntoConstraints = false
		bubble.addSubview(textField)

		var constraints: [NSLayoutConstraint] = [
			bubble.topAnchor.constraint(equalTo: row.topAnchor),
			bubble.bottomAnchor.constraint(equalTo: row.bottomAnchor),
			bubble.widthAnchor.constraint(lessThanOrEqualTo: row.widthAnchor, multiplier: 0.8),
			textField.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 10),
			textField.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -10),
			textField.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -6),
		]

		if outgoing {
			constraints.append(bubble.trailingAnchor.constraint(equalTo: row.trailingAnchor))
			constraints.append(textField.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 6))
		} else {
			constraints.append(bubble.leadingAnchor.constraint(equalTo: row.leadingAnchor))

			let nickField = NSTextField(labelWithString: nickname)
			nickField.font = NSFont.systemFont(ofSize: fontSize - 2, weight: .semibold)
			nickField.textColor = .secondaryLabelColor
			nickField.translatesAutoresizingMaskIntoConstraints = false
			bubble.addSubview(nickField)

			constraints.append(contentsOf: [
				nickField.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 5),
				nickField.leadingAnchor.constraint(equalTo: textField.leadingAnchor),
				textField.topAnchor.constraint(equalTo: nickField.bottomAnchor, constant: 1),
			])
		}

		NSLayoutConstraint.activate(constraints)

		return row
	}

	private func lineRow(nickname: String, text: String, outgoing: Bool, fontSize: CGFloat) -> NSView {
		let row = NSView()
		row.translatesAutoresizingMaskIntoConstraints = false

		let timeField = NSTextField(labelWithString: LocalizedKey("TDCOnboardingWindow[lf1-tm]"))
		timeField.font = NSFont.monospacedDigitSystemFont(ofSize: fontSize - 2, weight: .regular)
		timeField.textColor = .tertiaryLabelColor
		timeField.translatesAutoresizingMaskIntoConstraints = false

		let nickField = NSTextField(labelWithString: "<\(nickname)>")
		nickField.font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
		nickField.textColor = outgoing ? .controlAccentColor : .labelColor
		nickField.translatesAutoresizingMaskIntoConstraints = false

		let textField = NSTextField(wrappingLabelWithString: text)
		textField.font = NSFont.systemFont(ofSize: fontSize)
		textField.translatesAutoresizingMaskIntoConstraints = false

		row.addSubview(timeField)
		row.addSubview(nickField)
		row.addSubview(textField)

		NSLayoutConstraint.activate([
			timeField.leadingAnchor.constraint(equalTo: row.leadingAnchor),
			timeField.firstBaselineAnchor.constraint(equalTo: textField.firstBaselineAnchor),
			nickField.leadingAnchor.constraint(equalTo: timeField.trailingAnchor, constant: 8),
			nickField.firstBaselineAnchor.constraint(equalTo: textField.firstBaselineAnchor),
			textField.leadingAnchor.constraint(equalTo: nickField.trailingAnchor, constant: 6),
			textField.trailingAnchor.constraint(lessThanOrEqualTo: row.trailingAnchor),
			textField.topAnchor.constraint(equalTo: row.topAnchor),
			textField.bottomAnchor.constraint(equalTo: row.bottomAnchor),
		])

		return row
	}

	private func select() {
		if let target, let action {
			NSApp.sendAction(action, to: target, from: self)
		}
	}

	override public func mouseDown(with _: NSEvent) {
		select()
	}
}
