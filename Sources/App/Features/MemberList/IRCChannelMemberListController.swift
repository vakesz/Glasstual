/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import AppKit

/// The ordered members the member list draws, and the only writer of them.
///
/// This was an `NSArrayController` subclass, which bought nothing — the table
/// view is driven by a data source, not by bindings, so the controller was only
/// ever an array with change notifications attached. It cost something, though:
/// `insert(_:atArrangedObjectIndex:)` and `remove(atArrangedObjectIndex:)` are
/// declared nonisolated on `NSController`, so both overrides had to carry the
/// controller and the inserted member across a main-actor assumption inside an
/// `@unchecked Sendable` box. A plain main-actor model needs neither.
@objc(IRCChannelMemberListController)
@MainActor
public final class IRCChannelMemberListController: NSObject {
	private weak var memberList: ChannelMemberList?
	private var members: [ChannelUser] = []

	@IBOutlet public private(set) var tableView: MemberList!

	/// Named for what the array controller used to call it: the member list
	/// reads its rows from here.
	public var arrangedObjects: [ChannelUser] {
		members
	}

	@objc(assignToChannel:)
	public func assign(to channel: IRCChannel?) {
		if let memberList {
			memberList.assign(nil)
		}

		let newList = channel?.memberInfo as? ChannelMemberList

		if let newList {
			newList.assign(self)
		}

		memberList = newList

		if channel == nil || newList == nil {
			replaceContents([])
		}
	}

	@objc(replaceContents:)
	public func replaceContents(_ contents: [ChannelUser]) {
		members = contents
		tableView?.membersReplaced()
	}

	public func insert(_ member: ChannelUser, atArrangedObjectIndex index: Int) {
		guard index >= 0, index <= members.count else {
			return
		}

		members.insert(member, at: index)
		tableView?.memberInserted(at: UInt(index))
	}

	public func remove(atArrangedObjectIndex index: Int) {
		guard members.indices.contains(index) else {
			return
		}

		members.remove(at: index)
		tableView?.memberRemoved(at: UInt(index))
	}
}
