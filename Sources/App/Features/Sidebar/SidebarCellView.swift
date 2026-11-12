// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit

/// A single reusable native cell. Configuration replaces every presentation
/// value, including the values a previous occupant needed and this one does not.
final class SidebarCellView: NSTableCellView {
	static let reuseIdentifier = NSUserInterfaceItemIdentifier("sidebar-cell")
	let titleField = NSTextField(labelWithString: "")
	let subtitleField = NSTextField(labelWithString: "")
	let networkImage = NSImageView()
	private let subtitleStack = NSStackView()
	let leadingImage = NSImageView()
	let securityImage = NSImageView()
	/// The unread count: plain trailing text, as a source list draws it.
	let unreadCountField = NSTextField(labelWithString: "")
	private var content: SidebarOutlineNode.Content?
	private var metrics = ListRowMetrics(.medium)
	private var leadingWidth: NSLayoutConstraint?
	private var leadingHeight: NSLayoutConstraint?
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
		subtitleField.lineBreakMode = .byTruncatingTail
		subtitleField.maximumNumberOfLines = 1
		subtitleField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
		unreadCountField.alignment = .right
		unreadCountField.setContentHuggingPriority(.required, for: .horizontal)
		unreadCountField.setContentCompressionResistancePriority(.required, for: .horizontal)
		leadingImage.imageScaling = .scaleProportionallyDown
		subtitleStack.addArrangedSubview(networkImage)
		subtitleStack.addArrangedSubview(subtitleField)
		subtitleStack.orientation = .horizontal
		subtitleStack.alignment = .centerY
		subtitleStack.spacing = UISpacing.tight
		let labels = NSStackView(views: [titleField, subtitleStack])
		labels.orientation = .vertical
		labels.alignment = .leading
		labels.spacing = 1
		labels.detachesHiddenViews = true
		let stack = NSStackView(views: [leadingImage, labels, securityImage, spacer, unreadCountField])
		stack.orientation = .horizontal
		stack.alignment = .centerY
		stack.spacing = UISpacing.regular
		stack.detachesHiddenViews = true
		stack.translatesAutoresizingMaskIntoConstraints = false
		addSubview(stack)
		textField = titleField
		let leadingWidth = leadingImage.widthAnchor.constraint(equalToConstant: metrics.glyphWidth)
		let leadingHeight = leadingImage.heightAnchor.constraint(equalToConstant: metrics.glyphWidth)
		self.leadingWidth = leadingWidth
		self.leadingHeight = leadingHeight
		NSLayoutConstraint.activate([
			stack.leadingAnchor.constraint(equalTo: leadingAnchor),
			stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -UISpacing.tight),
			stack.centerYAnchor.constraint(equalTo: centerYAnchor),
			leadingWidth,
			leadingHeight,
		])
		for view in [titleField, subtitleField, networkImage, subtitleStack, leadingImage, securityImage, unreadCountField] {
			view.setAccessibilityElement(false)
		}
		/* One element per row, as a cell: the row's name, state and counts are
		 its label; its value is the state the end-to-end harness reads. */
		setAccessibilityElement(true)
		setAccessibilityRole(.cell)
		setAccessibilityChildren([])
		applyMetrics()
	}

	@available(*, unavailable)
	required init?(coder _: NSCoder) {
		fatalError("SidebarCellView is programmatic")
	}

	/// AppKit sets the table's effective row size here, which follows
	/// System Settings › Appearance › Sidebar icon size.
	override var rowSizeStyle: NSTableView.RowSizeStyle {
		didSet {
			let next = ListRowMetrics(ListRowMetrics.Size(rowSizeStyle))
			guard next != metrics else { return }
			metrics = next
			applyMetrics()
		}
	}

	private func applyMetrics() {
		leadingWidth?.constant = metrics.glyphWidth
		leadingHeight?.constant = metrics.glyphWidth
		leadingImage.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: metrics.textPointSize, weight: .regular)
		let secondary = NSImage.SymbolConfiguration(pointSize: metrics.secondaryPointSize, weight: .regular)
		networkImage.symbolConfiguration = secondary
		securityImage.symbolConfiguration = secondary
		subtitleField.font = .systemFont(ofSize: metrics.secondaryPointSize)
		applyFonts()
	}

	private func applyFonts() {
		let isServer = if case .server = content {
			true
		} else {
			false
		}
		titleField.font = .systemFont(ofSize: metrics.textPointSize, weight: isServer ? .semibold : .regular)
		let countIsEmphasized = if case let .conversation(conversation) = content {
			conversation.isEmphasized
		} else {
			false
		}
		unreadCountField.font = .monospacedDigitSystemFont(
			ofSize: metrics.textPointSize,
			weight: countIsEmphasized ? .semibold : .regular
		)
	}

	func configure(with node: SidebarOutlineNode) {
		guard content != node.content else { return }
		content = node.content
		setAccessibilityLabel(node.accessibilityDescription)
		subtitleField.stringValue = ""
		subtitleStack.isHidden = true
		networkImage.image = nil
		networkImage.isHidden = true
		leadingImage.image = nil
		leadingImage.isHidden = true
		leadingImage.toolTip = nil
		securityImage.image = nil
		securityImage.isHidden = true
		securityImage.toolTip = nil
		unreadCountField.stringValue = ""
		unreadCountField.isHidden = true
		unreadCountField.toolTip = nil
		applyFonts()
		switch node.content {
		case let .server(server):
			titleField.stringValue = server.title
			if server.isFavoritesGroup {
				leadingImage.image = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: nil)
				leadingImage.isHidden = false
			} else if let networkIcon = server.networkIcon {
				leadingImage.image = networkIcon
				leadingImage.isHidden = false
			} else {
				leadingImage.image = NSImage(systemSymbolName: server.identityStyle.icon.symbolName, accessibilityDescription: nil)
				leadingImage.isHidden = false
			}
			if let status = server.bouncerStatus {
				subtitleField.stringValue = status.text
				subtitleStack.isHidden = false
			}
			if server.isSecured {
				securityImage.image = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: nil)
				securityImage.toolTip = String(localized: .MainWindow.connectionSecurity)
				securityImage.isHidden = false
			}
		case let .conversation(conversation):
			titleField.stringValue = conversation.title
			if let network = conversation.networkTitle {
				subtitleField.stringValue = network
				subtitleStack.isHidden = false
				if let style = conversation.networkIdentityStyle {
					networkImage.image = NSImage(systemSymbolName: style.icon.symbolName, accessibilityDescription: nil)
					networkImage.isHidden = false
				}
			}
			let symbol: String? = if conversation.hasJoinError {
				"exclamationmark.triangle.fill"
			} else {
				switch conversation.kind {
				case .channel: conversation.isFavorite ? "pin.fill" : nil
				case .directChat, .direct, .console: conversation.kind.glyphSymbolName
				}
			}
			if let symbol {
				leadingImage.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
				leadingImage.isHidden = false
			}
			if conversation.hasJoinError {
				leadingImage.toolTip = String(localized: .MainWindow.sidebarJoinFailed)
			}
			if let security = conversation.directChatSecurity {
				let description = security == .unverified
					? String(localized: .MainWindow.encryptedDirectChatUnverified)
					: String(localized: .MainWindow.encryptedDirectChat)
				securityImage.image = NSImage(systemSymbolName: security.symbolName, accessibilityDescription: description)
				securityImage.toolTip = description
				securityImage.isHidden = false
			}
			if conversation.showsUnreadBadge {
				unreadCountField.stringValue = conversation.unreadCount.formatted()
				unreadCountField.isHidden = false
				unreadCountField.toolTip = String(localized: .ChannelSpotlight.unreadMessageCount(conversation.unreadCount))
			}
		}
		titleField.toolTip = titleField.stringValue
		updateColors()
	}

	/// Native outline proxies expose the cell's metadata. Keep disclosure and
	/// selection on AppKit's rows, and place secondary actions on this cell.
	func configureAccessibilityActions(with node: SidebarOutlineNode, canMoveUp: Bool, canMoveDown: Bool) {
		if case .favorite = node.identity {
			setAccessibilityIdentifier("sidebar-favorite-" + node.identity.itemIdentifier)
			setAccessibilityValue(nil)
		} else {
			let (identifier, state) = Self.accessibilityIdentity(of: node.content)
			setAccessibilityIdentifier(identifier)
			setAccessibilityValue(state.rawValue)
		}
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

	/// `sidebar-row-<kind>-<name>`, and whether the server is connected or the
	/// conversation joined.
	private static func accessibilityIdentity(of content: SidebarOutlineNode.Content)
		-> (identifier: String, state: SidebarRowState)
	{
		switch content {
		case let .server(server):
			return (
				AccessibilityIdentifier.sidebarRow("server", server.title),
				server.isActive ? .connected : .disconnected
			)
		case let .conversation(conversation):
			let kind = switch conversation.kind {
			case .channel: "channel"
			case .direct: "direct"
			case .directChat: "direct-chat"
			case .console: "console"
			}
			return (
				AccessibilityIdentifier.sidebarRow(kind, conversation.title),
				conversation.isActive ? .joined : .notJoined
			)
		}
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
		for field in [titleField, subtitleField, unreadCountField] {
			field.cell?.backgroundStyle = backgroundStyle
		}
		for image in [leadingImage, securityImage, networkImage] {
			image.cell?.backgroundStyle = backgroundStyle
		}
		subtitleField.textColor = backgroundStyle == .emphasized ? .labelColor : .secondaryLabelColor
		networkImage.contentTintColor = .secondaryLabelColor
		securityImage.contentTintColor = .secondaryLabelColor
		leadingImage.contentTintColor = .secondaryLabelColor
		unreadCountField.textColor = .secondaryLabelColor
		leadingImage.alphaValue = 1
		if backgroundStyle == .emphasized {
			titleField.textColor = .labelColor
			leadingImage.contentTintColor = .labelColor
			securityImage.contentTintColor = .labelColor
			networkImage.contentTintColor = .labelColor
			unreadCountField.textColor = .labelColor
			return
		}
		switch content {
		case let .server(server):
			titleField.textColor = server.isActive ? .labelColor : .secondaryLabelColor
			leadingImage.contentTintColor = server.identityStyle.color.nsColor
			leadingImage.alphaValue = server.isActive ? 1 : 0.6
		case let .conversation(conversation):
			leadingImage.alphaValue = 1
			networkImage.contentTintColor = conversation.networkIdentityStyle?.color.nsColor ?? .secondaryLabelColor
			unreadCountField.textColor = Self.unreadCountColor(for: conversation)
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

	/// An ordinary count is secondary text. A count that asks for attention
	/// takes the colour the reader chose for it, or the accent colour.
	static func unreadCountColor(for conversation: ConversationRow) -> NSColor {
		conversation.isEmphasized ? (conversation.unreadBadgeTint ?? .controlAccentColor) : .secondaryLabelColor
	}
}

extension ListRowMetrics.Size {
	/// A table's effective row size. A table's own `.default` and a custom
	/// height read as medium, the size AppKit gives a table that sets neither.
	init(_ style: NSTableView.RowSizeStyle) {
		switch style {
		case .small: self = .small
		case .large: self = .large
		case .default, .medium, .custom: self = .medium
		@unknown default: self = .medium
		}
	}
}
