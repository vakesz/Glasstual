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

private enum LayoutMetrics {
	static let rowSpacing: CGFloat = 4
	static let bottomGap: CGFloat = 4
	static let typingRowHeight: CGFloat = 18
	static let replyBannerHeight: CGFloat = 30
}

@objc(TVCMainWindowInputAccessoryView)
@MainActor
public final class MainWindowInputAccessoryView: NSView {
	@objc public var cancelReplyBlock: (() -> Void)?
	@objc public private(set) var replyMessageIdentifier: String?
	@objc public var contentDidChangeBlock: (() -> Void)?

	private var stackView: NSStackView!
	private var replyBanner: NSView!
	private var replyLabel: NSTextField!
	private var replyCloseButton: NSButton!
	private var typingRow: NSView!
	private var typingSymbol: NSImageView!
	private var typingLabel: NSTextField!

	override public var allowsVibrancy: Bool {
		false
	}

	override public init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		buildSubviews()
	}

	@available(*, unavailable)
	public required init?(coder _: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	private func buildSubviews() {
		translatesAutoresizingMaskIntoConstraints = false

		let stackView = NSStackView(views: [])
		stackView.orientation = .vertical
		stackView.alignment = .leading
		stackView.spacing = LayoutMetrics.rowSpacing
		stackView.detachesHiddenViews = true
		stackView.translatesAutoresizingMaskIntoConstraints = false

		addSubview(stackView)

		NSLayoutConstraint.activate([
			stackView.topAnchor.constraint(equalTo: topAnchor),
			stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
			stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
			stackView.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
		])

		self.stackView = stackView

		buildReplyBanner()
		buildTypingRow()

		stackView.addArrangedSubview(replyBanner)
		stackView.addArrangedSubview(typingRow)
		stackView.widthAnchor.constraint(equalTo: widthAnchor).isActive = true

		replyBanner.isHidden = true
		typingRow.isHidden = true
	}

	private func buildReplyBanner() {
		let banner = NSView(frame: .zero)
		banner.translatesAutoresizingMaskIntoConstraints = false
		banner.wantsLayer = true
		banner.layer?.cornerRadius = 8
		banner.layer?.cornerCurve = .continuous

		let icon = NSImageView(
			image: NSImage(systemSymbolName: "arrowshape.turn.up.left", accessibilityDescription: nil)!
		)
		icon.translatesAutoresizingMaskIntoConstraints = false
		icon.contentTintColor = .secondaryLabelColor
		icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)

		let label = NSTextField(labelWithString: "")
		label.translatesAutoresizingMaskIntoConstraints = false
		label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
		label.textColor = .labelColor
		label.lineBreakMode = .byTruncatingTail
		label.maximumNumberOfLines = 1
		label.allowsDefaultTighteningForTruncation = true
		label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

		let close = NSButton(
			image: NSImage(
				systemSymbolName: "xmark.circle.fill",
				accessibilityDescription: MainWindowStrings.Reply.cancel
			)!,
			target: self,
			action: #selector(cancelReply(_:))
		)
		close.translatesAutoresizingMaskIntoConstraints = false
		close.isBordered = false
		close.bezelStyle = .accessoryBarAction
		close.contentTintColor = .secondaryLabelColor
		close.toolTip = MainWindowStrings.Reply.cancel
		close.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)

		banner.addSubview(icon)
		banner.addSubview(label)
		banner.addSubview(close)

		NSLayoutConstraint.activate([
			banner.heightAnchor.constraint(equalToConstant: LayoutMetrics.replyBannerHeight),
			icon.leadingAnchor.constraint(equalTo: banner.leadingAnchor, constant: 10),
			icon.centerYAnchor.constraint(equalTo: banner.centerYAnchor),
			label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
			label.centerYAnchor.constraint(equalTo: banner.centerYAnchor),
			label.trailingAnchor.constraint(lessThanOrEqualTo: close.leadingAnchor, constant: -6),
			close.trailingAnchor.constraint(equalTo: banner.trailingAnchor, constant: -6),
			close.centerYAnchor.constraint(equalTo: banner.centerYAnchor),
		])

		replyBanner = banner
		replyLabel = label
		replyCloseButton = close

		updateReplyBannerColors()
	}

	override public func viewDidChangeEffectiveAppearance() {
		super.viewDidChangeEffectiveAppearance()
		updateReplyBannerColors()
	}

	private func updateReplyBannerColors() {
		effectiveAppearance.performAsCurrentDrawingAppearance {
			replyBanner.layer?.backgroundColor = NSColor.quaternarySystemFill.cgColor
		}
	}

	@objc(showReplyToMessageIdentifier:nickname:excerpt:)
	public func showReply(
		toMessageIdentifier messageIdentifier: String,
		nickname: String?,
		excerpt: String?
	) {
		replyMessageIdentifier = messageIdentifier

		let prefix = MainWindowStrings.Reply.target(nickname)

		let text = NSMutableAttributedString(
			string: prefix,
			attributes: [
				.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold),
				.foregroundColor: NSColor.labelColor,
			]
		)

		if let excerpt, excerpt.isEmpty == false {
			let trimmed = excerpt.replacingOccurrences(of: "\n", with: " ")
			text.append(
				NSAttributedString(
					string: ": \(trimmed)",
					attributes: [
						.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
						.foregroundColor: NSColor.secondaryLabelColor,
					]
				)
			)
		}

		replyLabel.attributedStringValue = text
		replyLabel.toolTip = excerpt

		setView(replyBanner, visible: true)
	}

	@objc public func hideReply() {
		guard replyMessageIdentifier != nil else {
			return
		}

		replyMessageIdentifier = nil
		setView(replyBanner, visible: false)
	}

	@objc private func cancelReply(_: Any?) {
		hideReply()
		cancelReplyBlock?()
	}

	private func buildTypingRow() {
		let row = NSView(frame: .zero)
		row.translatesAutoresizingMaskIntoConstraints = false

		let symbol = NSImageView(
			image: NSImage(systemSymbolName: "ellipsis", accessibilityDescription: nil)!
		)
		symbol.translatesAutoresizingMaskIntoConstraints = false
		symbol.contentTintColor = .secondaryLabelColor
		symbol.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .bold)

		let label = NSTextField(labelWithString: "")
		label.translatesAutoresizingMaskIntoConstraints = false
		label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
		label.textColor = .secondaryLabelColor
		label.lineBreakMode = .byTruncatingTail
		label.maximumNumberOfLines = 1
		label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

		row.addSubview(symbol)
		row.addSubview(label)

		NSLayoutConstraint.activate([
			row.heightAnchor.constraint(equalToConstant: LayoutMetrics.typingRowHeight),
			symbol.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 10),
			symbol.centerYAnchor.constraint(equalTo: row.centerYAnchor),
			label.leadingAnchor.constraint(equalTo: symbol.trailingAnchor, constant: 5),
			label.centerYAnchor.constraint(equalTo: row.centerYAnchor),
			label.trailingAnchor.constraint(lessThanOrEqualTo: row.trailingAnchor, constant: -10),
		])

		typingRow = row
		typingSymbol = symbol
		typingLabel = label
	}

	@objc(setTypingNicknames:)
	public func setTypingNicknames(_ nicknames: [String]) {
		if nicknames.isEmpty {
			if typingRow.isHidden == false {
				typingSymbol.removeAllSymbolEffects()
				setView(typingRow, visible: false)
			}

			return
		}

		let caption = MainWindowStrings.Typing.caption(for: nicknames)

		typingLabel.stringValue = caption
		typingRow.toolTip = nicknames.joined(separator: ", ")

		if typingRow.isHidden {
			if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion == false {
				typingSymbol.addSymbolEffect(.variableColor.cumulative.reversing, options: .repeating)
			}

			setView(typingRow, visible: true)
		}
	}

	private func setView(_ view: NSView, visible: Bool) {
		if view.isHidden == !visible {
			return
		}

		view.isHidden = !visible
		contentDidChangeBlock?()
	}

	@objc public var hasContent: Bool {
		replyBanner.isHidden == false || typingRow.isHidden == false
	}

	@objc public var preferredHeight: CGFloat {
		var height: CGFloat = 0
		var rows = 0

		if replyBanner.isHidden == false {
			height += LayoutMetrics.replyBannerHeight
			rows += 1
		}

		if typingRow.isHidden == false {
			height += LayoutMetrics.typingRowHeight
			rows += 1
		}

		if rows == 0 {
			return 0
		}

		return height + (CGFloat(rows - 1) * LayoutMetrics.rowSpacing) + LayoutMetrics.bottomGap
	}
}
