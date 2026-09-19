// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit

/// A single reusable native cell. Configuration replaces every presentation
/// value, including the values a previous occupant needed and this one does not.
final class SidebarCellView: NSTableCellView {
	static let reuseIdentifier = NSUserInterfaceItemIdentifier("sidebar-cell")
	let titleField = NSTextField(labelWithString: "")
	let leadingImage = NSImageView()
	let securityImage = NSImageView()
	let badge = SidebarUnreadBadge()
	private var content: SidebarOutlineNode.Content?
	var showMenu: (() -> Bool)?
	var move: ((Bool) -> Bool)?

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		identifier = Self.reuseIdentifier
		titleField.lineBreakMode = .byTruncatingTail
		titleField.maximumNumberOfLines = 1
		titleField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
		let spacer = NSView()
		spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
		let stack = NSStackView(views: [leadingImage, titleField, securityImage, spacer, badge])
		stack.orientation = .horizontal
		stack.alignment = .centerY
		stack.spacing = UISpacing.regular
		stack.detachesHiddenViews = true
		stack.translatesAutoresizingMaskIntoConstraints = false
		addSubview(stack)
		textField = titleField
		NSLayoutConstraint.activate([
			stack.leadingAnchor.constraint(equalTo: leadingAnchor),
			stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -UISpacing.tight),
			stack.centerYAnchor.constraint(equalTo: centerYAnchor),
			leadingImage.widthAnchor.constraint(equalToConstant: UIListMetrics.glyphWidth),
			leadingImage.heightAnchor.constraint(equalToConstant: 14),
			securityImage.widthAnchor.constraint(equalToConstant: 10),
			securityImage.heightAnchor.constraint(equalToConstant: 12),
		])
		for view in [titleField, leadingImage, securityImage, badge] {
			view.setAccessibilityElement(false)
		}
		setAccessibilityElement(true)
		setAccessibilityRole(.staticText)
		setAccessibilityChildren([])
	}

	@available(*, unavailable)
	required init?(coder _: NSCoder) {
		fatalError("SidebarCellView is programmatic")
	}

	func configure(with node: SidebarOutlineNode) {
		guard content != node.content else { return }
		content = node.content
		setAccessibilityLabel(node.accessibilityDescription)
		leadingImage.image = nil
		leadingImage.isHidden = true
		leadingImage.toolTip = nil
		securityImage.image = nil
		securityImage.isHidden = true
		securityImage.toolTip = nil
		badge.configure(count: 0, emphasized: false, tint: nil)
		badge.isHidden = true
		badge.toolTip = nil
		switch node.content {
		case let .server(server):
			titleField.stringValue = server.title
			titleField.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
			if server.isSecured {
				securityImage.image = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: nil)
				securityImage.toolTip = String(localized: .MainWindow.connectionSecurity)
				securityImage.isHidden = false
			}
		case let .conversation(conversation):
			titleField.stringValue = conversation.title
			titleField.font = .systemFont(ofSize: NSFont.systemFontSize)
			let symbol: String? = if conversation.hasJoinError {
				"exclamationmark.triangle.fill"
			} else {
				switch conversation.kind {
				case .channel: nil
				case .directChat: "bubble.left.and.bubble.right.fill"
				case .direct, .console: "person.fill"
				}
			}
			if let symbol {
				leadingImage.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
				leadingImage.isHidden = false
			}
			if conversation.hasJoinError {
				leadingImage.toolTip = String(localized: .MainWindow.sidebarJoinFailed)
			}
			badge.configure(count: conversation.unreadCount, emphasized: conversation.isEmphasized,
			                tint: conversation.unreadBadgeTint)
			badge.isHidden = !conversation.showsUnreadBadge
			badge.toolTip = conversation.showsUnreadBadge
				? String(localized: .ChannelSpotlight.unreadMessageCount(conversation.unreadCount)) : nil
		}
		titleField.toolTip = titleField.stringValue
		updateColors()
	}

	/// Native outline proxies expose the cell's metadata. Keep disclosure and
	/// selection on AppKit's rows, and place secondary actions on this cell.
	func configureAccessibilityActions(with node: SidebarOutlineNode, canMoveUp: Bool, canMoveDown: Bool) {
		setAccessibilityIdentifier("sidebar-row-\(node.identity.itemIdentifier)")
		var actions: [NSAccessibilityCustomAction] = []
		if canMoveUp {
			actions.append(NSAccessibilityCustomAction(name: String(localized: .MainWindow.sidebarMoveUp),
			                                           target: self, selector: #selector(moveSidebarUp)))
		}
		if canMoveDown {
			actions.append(NSAccessibilityCustomAction(name: String(localized: .MainWindow.sidebarMoveDown),
			                                           target: self, selector: #selector(moveSidebarDown)))
		}
		setAccessibilityCustomActions(actions)
	}

	override func accessibilityPerformShowMenu() -> Bool {
		showMenu?() ?? false
	}

	@objc private func moveSidebarUp() -> Bool {
		move?(true) ?? false
	}

	@objc private func moveSidebarDown() -> Bool {
		move?(false) ?? false
	}

	override var backgroundStyle: NSView.BackgroundStyle {
		didSet { updateColors() }
	}

	private func updateColors() {
		// NSTableCellView forwards backgroundStyle to direct controls. The
		// stack owns these controls, so forward the native style through it.
		titleField.cell?.backgroundStyle = backgroundStyle
		leadingImage.cell?.backgroundStyle = backgroundStyle
		securityImage.cell?.backgroundStyle = backgroundStyle
		securityImage.contentTintColor = .secondaryLabelColor
		leadingImage.contentTintColor = .secondaryLabelColor
		if backgroundStyle == .emphasized {
			titleField.textColor = .labelColor
			leadingImage.contentTintColor = .labelColor
			securityImage.contentTintColor = .labelColor
			return
		}
		switch content {
		case let .server(server):
			titleField.textColor = server.isActive ? .labelColor : .secondaryLabelColor
		case let .conversation(conversation):
			if conversation.hasJoinError {
				titleField.textColor = .systemRed
				leadingImage.contentTintColor = .systemRed
			} else if conversation.isActive, conversation.isEmphasized {
				titleField.textColor = .controlAccentColor
			} else {
				titleField.textColor = conversation.isActive ? .labelColor : .secondaryLabelColor
			}
		case nil:
			titleField.textColor = .labelColor
		}
	}
}

final class SidebarUnreadBadge: NSView {
	private let label = NSTextField(labelWithString: "")
	private var emphasized = false
	private var tint: NSColor?

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		label.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
		label.alignment = .center
		label.translatesAutoresizingMaskIntoConstraints = false
		label.setAccessibilityElement(false)
		addSubview(label)
		NSLayoutConstraint.activate([
			label.centerXAnchor.constraint(equalTo: centerXAnchor),
			label.centerYAnchor.constraint(equalTo: centerYAnchor),
		])
		setContentHuggingPriority(.required, for: .horizontal)
		setContentCompressionResistancePriority(.required, for: .horizontal)
	}

	@available(*, unavailable)
	required init?(coder _: NSCoder) {
		fatalError("SidebarUnreadBadge is programmatic")
	}

	func configure(count: Int, emphasized: Bool, tint: NSColor?) {
		label.stringValue = count.formatted()
		self.emphasized = emphasized
		self.tint = tint
		updateColors()
		invalidateIntrinsicContentSize()
	}

	override var intrinsicContentSize: NSSize {
		NSSize(width: max(24, label.intrinsicContentSize.width + 12), height: 18)
	}

	private var fillColor: NSColor {
		emphasized ? (tint ?? .selectedContentBackgroundColor) : .quaternaryLabelColor
	}

	private func updateColors() {
		label.textColor = emphasized ? fillColor.legibleForeground : .labelColor
		needsDisplay = true
	}

	override func viewDidChangeEffectiveAppearance() {
		super.viewDidChangeEffectiveAppearance()
		updateColors()
	}

	override func draw(_ dirtyRect: NSRect) {
		super.draw(dirtyRect)
		fillColor.setFill()
		NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2).fill()
	}
}
