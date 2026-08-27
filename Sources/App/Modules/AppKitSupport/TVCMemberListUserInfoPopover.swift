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

	override public nonisolated func awakeFromNib() {
		super.awakeFromNib()

		MainActor.assumeIsolated {
			behavior = .transient
		}
	}

	override public func mouseDown(with _: NSEvent) {
		close()
	}
}
