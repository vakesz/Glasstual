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

@objc(IRCChannelMemberListController)
@MainActor
public final class IRCChannelMemberListController: NSArrayController {
	private weak var memberList: IRCChannelMemberList?

	@IBOutlet public private(set) var tableView: TVCMemberList!

	@objc(assignToChannel:)
	public func assign(to channel: IRCChannel?) {
		if let memberList {
			memberList.assign(nil)
		}

		let newList = channel?.memberInfo

		if let newList {
			newList.assign(self)
		}

		memberList = newList

		if channel == nil || newList == nil {
			replaceContents([])
		}
	}

	@objc(replaceContents:)
	public func replaceContents(_ contents: [IRCChannelUser]) {
		content = NSMutableArray(array: contents)
		tableView.membersReplaced()
	}

	override public func insert(_ object: Any, atArrangedObjectIndex index: Int) {
		super.insert(object, atArrangedObjectIndex: index)
		tableView.memberInserted(at: UInt(index))
	}

	override public func remove(atArrangedObjectIndex index: Int) {
		super.remove(atArrangedObjectIndex: index)
		tableView.memberRemoved(at: UInt(index))
	}
}
