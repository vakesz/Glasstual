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

@objc(TVCMemberListUserInfoPopover)
public final class MemberListUserInfoPopover: NSPopover {
	@IBOutlet public var avatarImageView: NSImageView!
	@IBOutlet public var nicknameField: NSTextField!
	@IBOutlet public var usernameField: NSTextField!
	@IBOutlet public var addressField: NSTextField!
	@IBOutlet public var realNameField: NSTextField!
	@IBOutlet public var accountField: NSTextField!
	@IBOutlet public var privilegesField: NSTextField!
	@IBOutlet public var awayStatusField: NSTextField!

	private var hasConfigured = false

	/// Nib-time configuration, run by the owning member list once the outlet is
	/// connected. `awakeFromNib` is nonisolated, so reaching `behavior` from it
	/// took a runtime assumption about the calling thread; the owner is already
	/// on the main actor and the compiler can see it.
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
