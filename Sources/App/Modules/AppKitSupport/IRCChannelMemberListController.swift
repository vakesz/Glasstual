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

private nonisolated struct SynchronousMainActorValue<Value>: @unchecked Sendable {
	let value: Value
}

@objc(IRCChannelMemberListController)
@MainActor
public final class IRCChannelMemberListController: NSArrayController {
	/** NSController's initializers are nonisolated, so they have to be spelled out
	 to opt back out of the module's main-actor default. */
	override public nonisolated init(content: Any?) {
		super.init(content: content)
	}

	public required nonisolated init?(coder: NSCoder) {
		super.init(coder: coder)
	}

	private weak var memberList: ChannelMemberList?

	@IBOutlet public private(set) var tableView: MemberList!

	@objc(assignToChannel:)
	public func assign(to channel: IRCChannel?) {
		if let memberList {
			memberList.assign(nil)
		}

		let newList = (channel?.memberInfo as AnyObject?) as? ChannelMemberList

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
		content = NSMutableArray(array: contents)
		tableView.membersReplaced()
	}

	override public nonisolated func insert(_ object: Any, atArrangedObjectIndex index: Int) {
		let controller = SynchronousMainActorValue(value: self)
		let object = SynchronousMainActorValue(value: object)

		MainActor.assumeIsolated {
			controller.value.insertOnMain(object.value, atArrangedObjectIndex: index)
		}
	}

	private func insertOnMain(_ object: Any, atArrangedObjectIndex index: Int) {
		super.insert(object, atArrangedObjectIndex: index)
		tableView.memberInserted(at: UInt(index))
	}

	override public nonisolated func remove(atArrangedObjectIndex index: Int) {
		let controller = SynchronousMainActorValue(value: self)

		MainActor.assumeIsolated {
			controller.value.removeOnMain(atArrangedObjectIndex: index)
		}
	}

	private func removeOnMain(atArrangedObjectIndex index: Int) {
		super.remove(atArrangedObjectIndex: index)
		tableView.memberRemoved(at: UInt(index))
	}
}
