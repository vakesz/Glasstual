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

/// The ordered members the member list draws, and the only writer of them.
///
/// This was an `NSArrayController` subclass, which bought nothing — the table
/// view is driven by a data source, not by bindings, so the controller was only
/// ever an array with change notifications attached. It cost something, though:
/// `insert(_:atArrangedObjectIndex:)` and `remove(atArrangedObjectIndex:)` are
/// declared nonisolated on `NSController`, so both overrides had to carry the
/// controller and the inserted member across a main-actor assumption inside a
/// box that opted out of concurrency checking. A main-actor model needs neither.
///
/// The positions in these calls are the model's, not the table's: the table
/// sections its rows and diffs them, so it asks for members by identity.
@MainActor
public final class IRCChannelMemberListController: ChannelMemberListPresentation {
	private weak var memberList: ChannelMemberList?
	private var members: [ChannelUser] = []
	/// Position in `members` by the person's identity, so the table can go from
	/// the row identity its data source hands back to the value it draws.
	private var indexesByUserID: [User.ID: Int] = [:]

	public private(set) weak var model: MemberList?

	public func attach(to model: MemberList) {
		precondition(self.model == nil || self.model === model)
		self.model = model
	}

	/// Named for what the array controller used to call it: the member list
	/// reads its rows from here.
	public var arrangedObjects: [ChannelUser] {
		members
	}

	/// The member for `id`, or `nil` when that person is not in this channel.
	public func member(withID id: User.ID) -> ChannelUser? {
		indexesByUserID[id].map { members[$0] }
	}

	/** Rebuilds the identity index.

	 It is rebuilt rather than patched because an insert or a removal shifts
	 every position after it anyway. */
	private func reindexMembers() {
		indexesByUserID = Dictionary(
			members.enumerated().map { ($0.element.id, $0.offset) },
			uniquingKeysWith: { _, latest in latest }
		)
	}

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

	/// The list this was drawing is going away; `assign(to:)` does the same for
	/// a list that is merely being swapped out.
	public func memberListDidEnd() {
		memberList = nil
		replaceContents([])
	}

	public func replaceContents(_ contents: [ChannelUser]) {
		members = contents
		reindexMembers()
		model?.membersChanged()
	}

	public func insert(_ member: ChannelUser, atArrangedObjectIndex index: Int) {
		guard index >= 0, index <= members.count else {
			return
		}

		members.insert(member, at: index)
		reindexMembers()
		model?.membersChanged()
	}

	/// Puts an edited member back at the row it already occupies. A member is a
	/// value, so an edit has to be handed over rather than seen through a shared
	/// reference.
	///
	/// The edit still goes through the data source, because a mode change moves
	/// the member to another section; when nothing moved the diff is empty and
	/// only the redraw is left.
	public func replace(_ member: ChannelUser, atArrangedObjectIndex index: Int) {
		guard members.indices.contains(index) else {
			return
		}

		members[index] = member
		reindexMembers()
		model?.membersChanged()
		model?.invalidatePresentation()
	}

	public func remove(atArrangedObjectIndex index: Int) {
		guard members.indices.contains(index) else {
			return
		}

		members.remove(at: index)
		reindexMembers()
		model?.membersChanged()
	}
}
