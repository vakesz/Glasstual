/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2020 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *  * Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *  * Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *  * Neither the name of Textual, "Codeux Software, LLC", nor the
 *    names of its contributors may be used to endorse or promote products
 *    derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 *********************************************************************** */

import AppKit
import CocoaExtensions
import GlasstualPluginKit

private let memberRowHeight: CGFloat = 28.0
private let sectionHeaderRowHeight: CGFloat = 22.0
private let memberViewIdentifier = NSUserInterfaceItemIdentifier("MemberView")
private let sectionHeaderViewIdentifier = NSUserInterfaceItemIdentifier("HeaderView")

@MainActor
public protocol MemberListKeyEventDelegate: AnyObject {
	func memberListKeyDown(_ event: NSEvent)
}

/// The identity of one run of members that share a rank.
///
/// The data source sections the list by this. Ranks are contiguous once the
/// members are sorted, so `ordinal` is normally zero for every section; it is
/// carried anyway because a snapshot holding two equal section identifiers
/// traps, and a member that arrives ahead of its sort must not be able to take
/// the window down.
public nonisolated struct MemberListSectionIdentifier: Hashable, Sendable { // nonisolated: value
	public let rank: UserRank
	public let ordinal: Int
}

/// The header row a section draws, and the value its cell view reads.
public final nonisolated class MemberListSection: NSObject { // nonisolated: value
	public let identifier: MemberListSectionIdentifier
	public let title: String

	public var rank: UserRank {
		identifier.rank
	}

	public var objectiveCRankRawValue: UInt {
		rank.rawValue
	}

	fileprivate init(identifier: MemberListSectionIdentifier, title: String) {
		self.identifier = identifier
		self.title = title
		super.init()
	}

	override public var description: String {
		"<TVCMemberListSection \(title)>"
	}
}

private typealias MemberListDataSource =
	NSTableViewDiffableDataSource<MemberListSectionIdentifier, User.ID>
private typealias MemberListSnapshot =
	NSDiffableDataSourceSnapshot<MemberListSectionIdentifier, User.ID>

public final class MemberList: NSTableView, NSTableViewDelegate, AppearanceObserving {
	public var isHiddenByUser = false
	public weak var keyDelegate: (any MemberListKeyEventDelegate)?

	/// The window and scroll-view subscriptions, re-made on every move to a
	/// window and dropped with the table.
	private let notifications = NotificationSubscriptions()

	public private(set) var memberListUserInfoPopover: MemberListUserInfoPopover!
	public private(set) var contentController: IRCChannelMemberListController!

	private var memberDataSource: MemberListDataSource?
	private var sectionHeadersAreShown = false
	private var userPopoverTrackingArea: NSTrackingArea?
	private var userPopoverMouseIsInView = false
	private var userPopoverTask: Task<Void, Never>?
	private var userPopoverLastKnownLocalPoint = NSPoint.zero
	private var lastRowShownUserInfoPopover = -1

	private var members: [ChannelUser] {
		contentController?.arrangedObjects ?? []
	}

	private var hasConfigured = false

	override public init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		memberListUserInfoPopover = MemberListUserInfoPopover()
		contentController = IRCChannelMemberListController()
		contentController.attach(to: self)
	}

	@available(*, unavailable)
	required init?(coder _: NSCoder) {
		fatalError("MemberList is programmatic")
	}

	/// Installs the diffable data source and interaction behavior once.
	public func configure() {
		guard hasConfigured == false else {
			return
		}

		hasConfigured = true

		let memberDataSource = makeDataSource()
		self.memberDataSource = memberDataSource
		dataSource = memberDataSource
		delegate = self
		updateTrackingAreas()
		registerForDraggedTypes([.fileURL])
		applyMembers()
	}

	// MARK: - Data source

	private func makeDataSource() -> MemberListDataSource {
		let dataSource = MemberListDataSource(tableView: self) { [weak self] tableView, _, _, userID in
			let cell = (tableView.makeView(withIdentifier: memberViewIdentifier, owner: self) as? MemberListCell)
				?? MemberListCell(frame: .zero)
			cell.identifier = memberViewIdentifier

			// Programmatic cells are configured where the data source vends them.
			cell.configure()
			cell.objectValue = self?.member(withID: userID)

			return cell
		}

		/* Only member rows get a row view; the data source draws the section
		 headers with its own group-styled row, which is what the delegate used
		 to ask for by answering `nil`. */
		dataSource.rowViewProvider = { [weak self] _, _, _ in
			guard let self else {
				return NSTableRowView()
			}

			return MemberListRowCell(memberList: self)
		}

		return dataSource
	}

	private func makeSectionHeaderViewProvider()
		-> (NSTableView, Int, MemberListSectionIdentifier) -> NSView
	{
		{ [weak self] tableView, _, identifier in
			let cell = (tableView.makeView(withIdentifier: sectionHeaderViewIdentifier, owner: self)
				as? MemberListHeaderCell) ?? MemberListHeaderCell(frame: .zero)
			cell.identifier = sectionHeaderViewIdentifier

			cell.objectValue = MemberList.makeSection(identifier: identifier)

			return cell
		}
	}

	override public func viewDidMoveToWindow() {
		super.viewDidMoveToWindow()

		if window != nil {
			configure()
		}

		/* Emptied first: -viewDidMoveToWindow can run twice for the same window,
		 and a second pass must not leave a duplicate set behind. */
		notifications.cancelAll()

		guard let mainWindow else {
			return
		}

		notifications.observe(NSWindow.didBecomeKeyNotification, object: mainWindow) { [weak self] notification in
			self?.windowDidBecomeKey(notification)
		}
		notifications.observe(NSWindow.didResignKeyNotification, object: mainWindow) { [weak self] notification in
			self?.windowDidResignKey(notification)
		}
		notifications.observe(NSWindow.didBecomeMainNotification, object: mainWindow) { [weak self] notification in
			self?.windowMainStateChanged(notification)
		}
		notifications.observe(NSWindow.didResignMainNotification, object: mainWindow) { [weak self] notification in
			self?.windowMainStateChanged(notification)
		}
		notifications.observe(.mainWindowRedrawSubviews, object: mainWindow) { [weak self] notification in
			self?.mainWindowRequiresRedraw(notification)
		}

		if let contentView = scrollViewContentView {
			notifications.observe(NSView.boundsDidChangeNotification, object: contentView) { [weak self] notification in
				self?.scrollViewBoundsDidChange(notification)
			}
		}
	}

	// MARK: - Content

	public func assign(to channel: IRCChannel?) {
		contentController.assign(to: channel)
	}

	private func member(withID id: User.ID) -> ChannelUser? {
		contentController?.member(withID: id)
	}

	public func item(atRow row: Int) -> Any? {
		/* -1 is what the table reports for "no row", so it is an answer, not a
		 programming error. */
		guard row >= 0, let id = memberDataSource?.itemIdentifier(forRow: row) else {
			return nil
		}

		return member(withID: id)
	}

	public func row(forItem item: Any?) -> Int {
		guard let member = item as? ChannelUser,
		      let row = memberDataSource?.row(forItemIdentifier: member.id)
		else {
			return -1
		}

		return row
	}

	/// Rebuilds the list from the members the controller holds.
	///
	/// The table used to be told what changed — a row inserted here, a section
	/// header dropped there — and kept a parallel array of section ranges in
	/// step by hand, with four ways for the two to disagree. The data source
	/// diffs two snapshots instead, so a caller only has to say that the
	/// membership moved.
	public func membersChanged() {
		applyMembers()
	}

	private func applyMembers() {
		guard let memberDataSource else {
			return
		}

		let snapshot = makeSnapshot()
		let showSectionHeaders = snapshot.numberOfSections > 1

		/* Members of a single rank are drawn as a flat list, and the data source
		 gives every section it has a header row, so whether the provider is
		 installed is what decides. */
		if showSectionHeaders != sectionHeadersAreShown {
			sectionHeadersAreShown = showSectionHeaders
			memberDataSource.sectionHeaderViewProvider =
				showSectionHeaders ? makeSectionHeaderViewProvider() : nil
		}

		let selectedMembers = selectedMemberIDs

		memberDataSource.apply(snapshot, animatingDifferences: false)

		restoreSelection(to: selectedMembers)
		refreshVisibleCellValues()
	}

	private func makeSnapshot() -> MemberListSnapshot {
		var snapshot = MemberListSnapshot()
		var ordinalsByRank: [UserRank: Int] = [:]
		var currentSection: MemberListSectionIdentifier?
		var admitted: Set<User.ID> = []

		for member in members {
			let rank = Self.sectionRank(for: member)

			if currentSection?.rank != rank {
				let ordinal = ordinalsByRank[rank, default: 0]
				ordinalsByRank[rank] = ordinal + 1

				let section = MemberListSectionIdentifier(rank: rank, ordinal: ordinal)
				snapshot.appendSections([section])
				currentSection = section
			}

			/* One channel holds one member per person, so a repeat is a bug
			 upstream rather than something to draw twice — and a snapshot with
			 two equal item identifiers traps. */
			guard let currentSection, admitted.insert(member.id).inserted else {
				continue
			}

			snapshot.appendItems([member.id], toSection: currentSection)
		}

		return snapshot
	}

	// MARK: - Selection

	private var selectedMemberIDs: [User.ID] {
		guard let memberDataSource else {
			return []
		}

		return selectedRowIndexes.compactMap { memberDataSource.itemIdentifier(forRow: $0) }
	}

	/// Puts the selection back on the people who held it.
	///
	/// Applying a snapshot clears the selection outright — it is held by row,
	/// and every row below a join or a part has moved — so the people are
	/// remembered and looked up again afterwards.
	private func restoreSelection(to memberIDs: [User.ID]) {
		guard let memberDataSource, memberIDs.isEmpty == false else {
			return
		}

		let rows = IndexSet(memberIDs.compactMap { memberDataSource.row(forItemIdentifier: $0) })

		guard rows != selectedRowIndexes else {
			return
		}

		selectRowIndexes(rows, byExtendingSelection: false)
	}

	/// Hands every on-screen cell the value it now draws.
	///
	/// A diff moves rows by identity; it does not tell a cell that the member
	/// behind an unchanged identity was edited. Restamping what is visible is
	/// cheaper than tracking which edits a cell has already seen.
	private func refreshVisibleCellValues() {
		let visible = rows(in: visibleRect)

		guard visible.length > 0 else {
			return
		}

		for row in visible.location ..< NSMaxRange(visible) {
			switch view(atColumn: 0, row: row, makeIfNecessary: false) {
			case let cell as MemberListCell:
				cell.objectValue = item(atRow: row)
			case let header as MemberListHeaderCell:
				header.objectValue = section(atRow: row)
			default:
				break
			}
		}
	}

	// MARK: - Sections and row geometry

	private static func sectionRank(for member: ChannelUser) -> UserRank {
		if member.user.isIRCop, Preferences.Appearance.memberListSortFavorsServerStaff.detachedValue {
			return .irCopByMode
		}

		return member.rank
	}

	private static func title(forSectionRank rank: UserRank) -> String {
		MainWindowStrings.MemberList.sectionTitle(for: rank)
	}

	private static func makeSection(identifier: MemberListSectionIdentifier) -> MemberListSection {
		MemberListSection(identifier: identifier, title: title(forSectionRank: identifier.rank))
	}

	/// The section drawn on `row`, or `nil` when the row holds a member.
	public func section(atRow row: Int) -> MemberListSection? {
		guard row >= 0, let identifier = memberDataSource?.sectionIdentifier(forRow: row) else {
			return nil
		}

		return Self.makeSection(identifier: identifier)
	}

	public func isGroupRow(_ row: Int) -> Bool {
		guard row >= 0 else {
			return false
		}

		return memberDataSource?.sectionIdentifier(forRow: row) != nil
	}

	public func rowForMember(at memberIndex: Int) -> Int {
		guard let member = contentController?.member(at: memberIndex) else {
			return -1
		}

		return row(forItem: member)
	}

	// MARK: - NSTableViewDelegate

	public func tableView(_: NSTableView, isGroupRow row: Int) -> Bool {
		isGroupRow(row)
	}

	public func tableView(_: NSTableView, shouldSelectRow row: Int) -> Bool {
		isGroupRow(row) == false
	}

	public func tableView(_: NSTableView, heightOfRow row: Int) -> CGFloat {
		isGroupRow(row) ? sectionHeaderRowHeight : memberRowHeight
	}

	public func tableView(_: NSTableView, typeSelectStringFor _: NSTableColumn?, row: Int) -> String? {
		(item(atRow: row) as? ChannelUser)?.user.nickname
	}

	public func tableView(_: NSTableView, didAdd _: NSTableRowView, forRow row: Int) {
		refreshDrawing(forRow: row)
	}

	// MARK: - Mouse tracking and user popover

	override public func updateTrackingAreas() {
		super.updateTrackingAreas()

		if let userPopoverTrackingArea {
			removeTrackingArea(userPopoverTrackingArea)
		}

		let trackingArea = NSTrackingArea(
			rect: bounds,
			options: [.mouseEnteredAndExited, .mouseMoved, .activeInActiveApp, .inVisibleRect],
			owner: self,
			userInfo: nil
		)
		userPopoverTrackingArea = trackingArea
		addTrackingArea(trackingArea)
	}

	private func destroyUserInfoPopoverOnWindowKeyChange() {
		destroyUserInfoPopover()
	}

	private func destroyUserInfoPopover() {
		userPopoverTask?.cancel()
		userPopoverTask = nil

		lastRowShownUserInfoPopover = -1
		userPopoverMouseIsInView = false
		userPopoverLastKnownLocalPoint = .zero

		if memberListUserInfoPopover?.isShown == true {
			memberListUserInfoPopover.close()
		}
	}

	override public func mouseEntered(with _: NSEvent) {
		userPopoverMouseIsInView = true

		guard userPopoverTask == nil else {
			return
		}

		userPopoverTask = Task { @MainActor [weak self] in
			try? await Task.sleep(for: .seconds(1))

			guard Task.isCancelled == false else {
				return
			}

			self?.popDelayedUserInfoExpansionFrame()
		}
	}

	override public func mouseExited(with _: NSEvent) {
		destroyUserInfoPopover()
	}

	override public func mouseMoved(with event: NSEvent) {
		let localPoint = convert(event.locationInWindow, from: nil)
		popUserInfoExpansionFrame(at: localPoint, ignoringTimer: false)
	}

	private func popUserInfoExpansionFrame(at localPoint: NSPoint, ignoringTimer: Bool) {
		userPopoverLastKnownLocalPoint = localPoint

		guard Accessibility.isVoiceOverEnabled == false else {
			return
		}
		guard ignoringTimer || userPopoverTask == nil else {
			return
		}
		guard window?.isKeyWindow == true else {
			return
		}

		let row = row(at: localPoint)
		guard row >= 0, isGroupRow(row) == false, lastRowShownUserInfoPopover != row else {
			return
		}

		lastRowShownUserInfoPopover = row
		(view(atColumn: 0, row: row, makeIfNecessary: false) as? MemberListCell)?.drawWithExpansionFrame()
	}

	private func popDelayedUserInfoExpansionFrame() {
		userPopoverTask = nil

		if userPopoverMouseIsInView {
			popUserInfoExpansionFrame(at: userPopoverLastKnownLocalPoint, ignoringTimer: true)
		}
	}

	// MARK: - Scroll view

	private var scrollViewContentView: NSClipView? {
		enclosingScrollView?.contentView
	}

	private func scrollViewBoundsDidChange(_ notification: Notification) {
		guard Preferences.Appearance.memberListUpdatesPopoverOnScroll.value else {
			return
		}
		guard notification.object as AnyObject? === scrollViewContentView else {
			return
		}
		guard let window else {
			return
		}

		let mouseLocation = NSEvent.mouseLocation
		let remoteRect = window.convertFromScreen(NSRect(origin: mouseLocation, size: NSSize(width: 1, height: 1)))
		let localPoint = convert(remoteRect.origin, from: nil)
		popUserInfoExpansionFrame(at: localPoint, ignoringTimer: true)
	}

	// MARK: - Drag and drop

	private func draggedRow(from sender: NSDraggingInfo) -> Int {
		let row = row(at: convert(sender.draggingLocation, from: nil))
		return row >= 0 && isGroupRow(row) == false ? row : -1
	}

	private func draggedFiles(from sender: NSDraggingInfo) -> [String] {
		let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
		let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL] ?? []
		return urls.compactMap { $0.path.isEmpty ? nil : $0.path }
	}

	override public func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
		draggingUpdated(sender)
	}

	override public func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
		draggedFiles(from: sender).isEmpty == false && draggedRow(from: sender) >= 0 ? .copy : []
	}

	override public func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
		draggedFiles(from: sender).isEmpty == false && draggedRow(from: sender) >= 0
	}

	override public func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
		let files = draggedFiles(from: sender)
		let row = draggedRow(from: sender)
		guard files.isEmpty == false, row >= 0 else {
			return false
		}

		AppController.shared.menuController?.memberSendDroppedFiles(files, row: UInt(row))
		return true
	}

	// MARK: - Drawing updates

	public func refreshAllDrawings() {
		refreshAllDrawings(skipOcclusionCheck: false)
	}

	public func refreshAllDrawings(skipOcclusionCheck: Bool) {
		for row in 0 ..< numberOfRows {
			refreshDrawing(forRow: row, skipOcclusionCheck: skipOcclusionCheck)
		}
	}

	public func refreshDrawing(forRow row: Int) {
		refreshDrawing(forRow: row, skipOcclusionCheck: false)
	}

	public func refreshDrawing(forRow row: Int, skipOcclusionCheck: Bool) {
		guard row >= 0 else {
			return
		}
		if skipOcclusionCheck == false, mainWindow?.ceIsOccluded == true {
			return
		}

		view(atColumn: 0, row: row, makeIfNecessary: false)?.needsDisplay = true
		rowView(atRow: row, makeIfNecessary: false)?.needsDisplay = true
	}

	public func refreshDrawing(for member: ChannelUser) {
		let row = row(forItem: member)

		guard row >= 0 else {
			return
		}

		/* A member is a value, so the cell holds a copy: an edit has to be handed
		 over. The identity did not change, so the data source has nothing to
		 diff and would leave the old copy on screen. */
		(view(atColumn: 0, row: row, makeIfNecessary: false) as? MemberListCell)?.objectValue = member

		refreshDrawing(forRow: row)
	}

	public func refreshDrawing(forChangesToPreference preferenceKey: String) {
		guard let badge = UserListModeBadge.badge(forPreferenceKeyNamed: preferenceKey) else {
			return
		}

		let rank: UserRank = switch badge {
		case .ircOperator: .irCopByMode
		case .channelOwner: .channelOwner
		case .superOperator: .superOperator
		case .normalOperator: .normalOperator
		case .halfOperator: .halfOperator
		case .voiced: .voiced
		}

		refreshDrawing(forMembersWithRank: rank, isIRCop: rank == .irCopByMode)
	}

	private func refreshDrawing(forMembersWithRank rank: UserRank, isIRCop: Bool) {
		for (index, member) in members.enumerated() {
			let matchesRank = isIRCop ? member.user.isIRCop : member.ranks.contains(rank)
			if matchesRank {
				refreshDrawing(forRow: rowForMember(at: index))
			}
		}
	}

	override public var allowsVibrancy: Bool {
		true
	}

	public func applicationAppearanceChanged() {
		refreshForAppearanceChange()
	}

	public func systemAppearanceChanged() {
		refreshForAppearanceChange()
	}

	private func refreshForAppearanceChange() {
		invalidateSelectionBackground()
		refreshAllDrawings(skipOcclusionCheck: true)
		needsDisplay = true
	}

	private func windowDidBecomeKey(_ notification: Notification) {
		windowKeyStateChanged(notification)
	}

	private func windowDidResignKey(_ notification: Notification) {
		destroyUserInfoPopoverOnWindowKeyChange()
		windowKeyStateChanged(notification)
	}

	private func windowKeyStateChanged(_: Notification) {
		respondToRequiresRedraw()
	}

	private func windowMainStateChanged(_: Notification) {
		enumerateAvailableRowViews { rowView, _ in
			(rowView as? MemberListRowCell)?.refreshEmphasis()
		}

		respondToRequiresRedraw()
	}

	private func mainWindowRequiresRedraw(_: Notification) {
		respondToRequiresRedraw()
	}

	private func respondToRequiresRedraw() {
		refreshAllDrawings(skipOcclusionCheck: true)
	}

	// MARK: - Events

	override public func menu(for _: NSEvent) -> NSMenu? {
		guard let row = rowBeneathMouse, isGroupRow(row) == false else {
			return nil
		}

		if selectedRowIndexes.contains(row) == false {
			selectItem(at: row)
		}

		return AppController.shared.menuController?.userControlMenu
	}

	override public func keyDown(with event: NSEvent) {
		/* With no delegate the list must still respond to the keyboard, so
		 unhandled keys go to super rather than being swallowed. */
		guard let keyDelegate else {
			super.keyDown(with: event)

			return
		}

		switch KeyCode(rawValue: event.keyCode) {
		case .downArrow, .upArrow:
			super.keyDown(with: event)
		case .leftArrow, .rightArrow, .pageUp, .pageDown:
			break
		default:
			keyDelegate.memberListKeyDown(event)
		}
	}
}
