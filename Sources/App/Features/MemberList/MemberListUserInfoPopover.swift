/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import AppKit

public final class MemberListUserInfoPopover: NSPopover {
	public private(set) var avatarImageView = NSImageView()
	public private(set) var nicknameField = NSTextField(labelWithString: "")
	public private(set) var usernameField = NSTextField(labelWithString: "")
	public private(set) var addressField = NSTextField(labelWithString: "")
	public private(set) var realNameField = NSTextField(labelWithString: "")
	public private(set) var accountField = NSTextField(labelWithString: "")
	public private(set) var privilegesField = NSTextField(labelWithString: "")
	public private(set) var awayStatusField = NSTextField(labelWithString: "")

	private var hasConfigured = false

	override public init() {
		super.init()
		installContent()
	}

	@available(*, unavailable)
	required init?(coder _: NSCoder) {
		fatalError("MemberListUserInfoPopover is programmatic")
	}

	private func installContent() {
		avatarImageView.imageScaling = .scaleProportionallyDown
		avatarImageView.translatesAutoresizingMaskIntoConstraints = false
		NSLayoutConstraint.activate([
			avatarImageView.widthAnchor.constraint(equalToConstant: 64),
			avatarImageView.heightAnchor.constraint(equalToConstant: 64),
		])

		nicknameField.font = NSFont.systemFont(ofSize: 18, weight: .semibold)
		let details = NSStackView(views: [
			row(MainWindowStrings.MemberInfo.username, usernameField),
			row(MainWindowStrings.MemberInfo.address, addressField),
			row(MainWindowStrings.MemberInfo.realName, realNameField),
			row(MainWindowStrings.MemberInfo.account, accountField),
			row(MainWindowStrings.MemberInfo.privileges, privilegesField),
			row(MainWindowStrings.MemberInfo.status, awayStatusField),
		])
		details.orientation = .vertical
		details.alignment = .leading
		details.spacing = 5

		let header = NSStackView(views: [avatarImageView, nicknameField])
		header.orientation = .horizontal
		header.alignment = .centerY
		header.spacing = 12

		let content = NSStackView(views: [header, details])
		content.orientation = .vertical
		content.alignment = .leading
		content.spacing = 12
		content.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
		content.translatesAutoresizingMaskIntoConstraints = false

		let controller = NSViewController()
		controller.view = content
		controller.preferredContentSize = NSSize(width: 340, height: 250)
		contentViewController = controller
	}

	private func row(_ title: String, _ value: NSTextField) -> NSView {
		let label = NSTextField(labelWithString: title)
		label.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
		label.textColor = .secondaryLabelColor
		label.alignment = .right
		label.widthAnchor.constraint(equalToConstant: 72).isActive = true
		value.lineBreakMode = .byTruncatingTail
		let row = NSStackView(views: [label, value])
		row.orientation = .horizontal
		row.alignment = .firstBaseline
		row.spacing = 8
		return row
	}

	/// Completes popover behavior setup once, at the main-actor use site.
	public func configure() {
		guard hasConfigured == false else {
			return
		}

		hasConfigured = true
		behavior = .transient
	}

	override public func mouseDown(with _: NSEvent) {
		close()
	}
}
