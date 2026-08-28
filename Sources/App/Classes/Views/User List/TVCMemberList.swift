/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
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

@objc(TVCMemberListSection)
public final nonisolated class MemberListSection: NSObject {
	public fileprivate(set) var rank: UserRank = .none
	@objc public fileprivate(set) var title = ""
	@objc public fileprivate(set) var memberRange = NSRange(location: 0, length: 0)

	@objc(rank)
	public var objectiveCRankRawValue: UInt {
		rank.rawValue
	}

	override public init() {
		super.init()
	}

	fileprivate init(rank: UserRank, title: String, memberRange: NSRange) {
		self.rank = rank
		self.title = title
		self.memberRange = memberRange
		super.init()
	}

	override public var description: String {
		"<TVCMemberListSection \(title) \(NSStringFromRange(memberRange))>"
	}
}

@objc(TVCMemberList)
public final class MemberList: NSTableView, NSTableViewDataSource, NSTableViewDelegate {
	@objc public var isHiddenByUser = false
	public weak var keyDelegate: (any MemberListKeyEventDelegate)?

	@IBOutlet public private(set) var memberListUserInfoPopover: MemberListUserInfoPopover!
	@IBOutlet public private(set) var contentController: IRCChannelMemberListController!

	private var sections: [MemberListSection] = []
	private var userPopoverTrackingArea: NSTrackingArea?
	private var userPopoverMouseIsInView = false
	private var userPopoverTask: Task<Void, Never>?
	private var userPopoverLastKnownLocalPoint = NSPoint.zero
	private var lastRowShownUserInfoPopover = -1

	private var members: [ChannelUser] {
		contentController?.arrangedObjects as? [ChannelUser] ?? []
	}

	private var isGrouped: Bool {
		sections.count > 1
	}

	/* ISOLATION-EXCEPTION: `NSObject.awakeFromNib()` is declared nonisolated, so the
	 override cannot be main-actor isolated. AppKit decodes nibs on the main thread
	 only, which is what makes the assumption safe. */
	override public nonisolated func awakeFromNib() {
		super.awakeFromNib()

		MainActor.assumeIsolated {
			dataSource = self
			delegate = self
			updateTrackingAreas()
			registerForDraggedTypes([.fileURL])
		}
	}

	override public func viewDidMoveToWindow() {
		super.viewDidMoveToWindow()

		let center = NotificationCenter.default
		center.removeObserver(self, name: NSWindow.didBecomeKeyNotification, object: nil)
		center.removeObserver(self, name: NSWindow.didResignKeyNotification, object: nil)
		center.removeObserver(self, name: NSWindow.didBecomeMainNotification, object: nil)
		center.removeObserver(self, name: NSWindow.didResignMainNotification, object: nil)
		center.removeObserver(self, name: .TVCMainWindowRedrawSubviews, object: nil)
		center.removeObserver(self, name: NSView.boundsDidChangeNotification, object: nil)

		guard let mainWindow else {
			return
		}

		center.addObserver(
			self,
			selector: #selector(windowDidBecomeKey(_:)),
			name: NSWindow.didBecomeKeyNotification,
			object: mainWindow
		)
		center.addObserver(
			self,
			selector: #selector(windowDidResignKey(_:)),
			name: NSWindow.didResignKeyNotification,
			object: mainWindow
		)
		center.addObserver(
			self,
			selector: #selector(windowMainStateChanged(_:)),
			name: NSWindow.didBecomeMainNotification,
			object: mainWindow
		)
		center.addObserver(
			self,
			selector: #selector(windowMainStateChanged(_:)),
			name: NSWindow.didResignMainNotification,
			object: mainWindow
		)
		center.addObserver(
			self,
			selector: #selector(mainWindowRequiresRedraw(_:)),
			name: .TVCMainWindowRedrawSubviews,
			object: mainWindow
		)

		if let contentView = scrollViewContentView {
			center.addObserver(
				self,
				selector: #selector(scrollViewBoundsDidChange(_:)),
				name: NSView.boundsDidChangeNotification,
				object: contentView
			)
		}
	}

	// MARK: - Content

	@objc(assignToChannel:)
	public func assign(to channel: IRCChannel?) {
		contentController.assign(to: channel)
	}

	@objc(itemAtRow:)
	public func item(atRow row: Int) -> Any? {
		precondition(row >= 0)

		let memberIndex = memberIndex(forRow: row)
		guard members.indices.contains(memberIndex) else {
			return nil
		}

		return members[memberIndex]
	}

	@objc(rowForItem:)
	public func row(forItem item: Any?) -> Int {
		guard let item else {
			return -1
		}

		guard let index = members.firstIndex(where: { $0 === item as AnyObject }) else {
			return -1
		}

		return rowForMember(at: index)
	}

	@objc
	public func membersReplaced() {
		rebuildSections()
		reloadData()
	}

	@objc(memberInsertedAtIndex:)
	public func memberInserted(at memberIndex: UInt) {
		let memberIndex = Int(memberIndex)
		guard members.indices.contains(memberIndex) else {
			membersReplaced()
			return
		}

		let rank = Self.sectionRank(for: members[memberIndex])
		let wasGrouped = isGrouped
		var absorbingSectionIndex: Int?
		var insertionIndex = sections.endIndex

		for (index, section) in sections.enumerated() {
			if memberIndex < section.memberRange.location {
				insertionIndex = index
				break
			}

			if memberIndex <= NSMaxRange(section.memberRange) {
				if section.rank == rank {
					absorbingSectionIndex = index
					break
				}

				if memberIndex < NSMaxRange(section.memberRange) {
					membersReplaced()
					return
				}

				insertionIndex = index + 1
			}
		}

		if let sectionIndex = absorbingSectionIndex {
			let section = sections[sectionIndex]
			section.memberRange.length += 1
			shiftSections(after: sectionIndex, by: 1)
			insertRows(at: IndexSet(integer: rowForMember(at: memberIndex)), withAnimation: [])
			return
		}

		let section = Self.makeSection(rank: rank, memberRange: NSRange(location: memberIndex, length: 1))
		sections.insert(section, at: insertionIndex)
		shiftSections(after: insertionIndex, by: 1)

		var rows = IndexSet(integer: rowForMember(at: memberIndex))

		if isGrouped {
			if wasGrouped {
				rows.insert(headerRow(forSectionAt: insertionIndex))
			} else {
				for sectionIndex in sections.indices {
					rows.insert(headerRow(forSectionAt: sectionIndex))
				}
			}
		}

		insertRows(at: rows, withAnimation: [])
	}

	@objc(memberRemovedAtIndex:)
	public func memberRemoved(at memberIndex: UInt) {
		let memberIndex = Int(memberIndex)
		guard let sectionIndex = sectionIndex(containingMemberAt: memberIndex) else {
			membersReplaced()
			return
		}

		let section = sections[sectionIndex]
		let wasGrouped = isGrouped
		var rows = IndexSet(integer: rowForMember(at: memberIndex))

		if section.memberRange.length == 1 {
			if wasGrouped {
				rows.insert(headerRow(forSectionAt: sectionIndex))

				if sections.count == 2 {
					let survivingSection = sectionIndex == 0 ? 1 : 0
					rows.insert(headerRow(forSectionAt: survivingSection))
				}
			}

			sections.remove(at: sectionIndex)
			shiftSections(after: sectionIndex - 1, by: -1)
		} else {
			section.memberRange.length -= 1
			shiftSections(after: sectionIndex, by: -1)
		}

		removeRows(at: rows, withAnimation: [])
	}

	// MARK: - Sections and row geometry

	private static func sectionRank(for member: ChannelUser) -> UserRank {
		if member.user.isIRCop, TextualPreferences.memberListSortFavorsServerStaff() {
			return .irCopByMode
		}

		return member.rank
	}

	private static func title(forSectionRank rank: UserRank) -> String {
		MainWindowStrings.MemberList.sectionTitle(for: rank)
	}

	private static func makeSection(rank: UserRank, memberRange: NSRange) -> MemberListSection {
		MemberListSection(rank: rank, title: title(forSectionRank: rank), memberRange: memberRange)
	}

	private func rebuildSections() {
		var rebuilt: [MemberListSection] = []

		for (index, member) in members.enumerated() {
			let rank = Self.sectionRank(for: member)

			if let current = rebuilt.last, current.rank == rank {
				current.memberRange.length += 1
			} else {
				rebuilt.append(
					Self.makeSection(rank: rank, memberRange: NSRange(location: index, length: 1))
				)
			}
		}

		sections = rebuilt
	}

	private func shiftSections(after sectionIndex: Int, by delta: Int) {
		let firstShiftedIndex = sectionIndex + 1
		guard sections.indices.contains(firstShiftedIndex) else {
			return
		}

		for index in firstShiftedIndex ..< sections.endIndex {
			sections[index].memberRange.location += delta
		}
	}

	private func sectionIndex(containingMemberAt memberIndex: Int) -> Int? {
		sections.firstIndex { NSLocationInRange(memberIndex, $0.memberRange) }
	}

	@objc(isGroupRow:)
	public func isGroupRow(_ row: Int) -> Bool {
		sectionIndex(forHeaderRow: row) != nil
	}

	private func headerRow(forSectionAt sectionIndex: Int) -> Int {
		guard isGrouped else {
			return -1
		}

		return sections[sectionIndex].memberRange.location + sectionIndex
	}

	private func sectionIndex(forHeaderRow row: Int) -> Int? {
		guard isGrouped, row >= 0 else {
			return nil
		}

		for (index, section) in sections.enumerated() {
			let headerRow = section.memberRange.location + index
			if headerRow == row {
				return index
			}
			if headerRow > row {
				break
			}
		}

		return nil
	}

	@objc(rowForMemberAtIndex:)
	public func rowForMember(at memberIndex: Int) -> Int {
		guard memberIndex >= 0 else {
			return -1
		}

		guard isGrouped else {
			return memberIndex
		}

		let precedingHeaderCount = sections.prefix { $0.memberRange.location <= memberIndex }.count
		return memberIndex + precedingHeaderCount
	}

	private func memberIndex(forRow row: Int) -> Int {
		guard row >= 0 else {
			return -1
		}

		guard isGrouped else {
			return row
		}

		for (index, section) in sections.enumerated() {
			let headerRow = section.memberRange.location + index
			if row == headerRow {
				return -1
			}
			if row <= headerRow + section.memberRange.length {
				return row - index - 1
			}
		}

		return -1
	}

	// MARK: - NSTableViewDataSource

	public func numberOfRows(in _: NSTableView) -> Int {
		members.count + (isGrouped ? sections.count : 0)
	}

	public func tableView(_: NSTableView, objectValueFor _: NSTableColumn?, row: Int) -> Any? {
		if let sectionIndex = sectionIndex(forHeaderRow: row) {
			return sections[sectionIndex]
		}

		return item(atRow: row)
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

	public func tableView(_: NSTableView, viewFor _: NSTableColumn?, row: Int) -> NSView? {
		let identifier = isGroupRow(row) ? sectionHeaderViewIdentifier : memberViewIdentifier
		return makeView(withIdentifier: identifier, owner: self)
	}

	public func tableView(_: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
		guard isGroupRow(row) == false else {
			return nil
		}

		return MemberListRowCell(memberList: self)
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

	@objc
	private func destroyUserInfoPopoverOnWindowKeyChange() {
		destroyUserInfoPopover()
	}

	@objc
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

	@objc
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

	@objc
	private func scrollViewBoundsDidChange(_ notification: Notification) {
		guard TextualPreferences.memberListUpdatesUserInfoPopoverOnScroll() else {
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

	@objc
	public func refreshAllDrawings() {
		refreshAllDrawings(skipOcclusionCheck: false)
	}

	@objc(refreshAllDrawings:)
	public func refreshAllDrawings(skipOcclusionCheck: Bool) {
		for row in 0 ..< numberOfRows {
			refreshDrawing(forRow: row, skipOcclusionCheck: skipOcclusionCheck)
		}
	}

	@objc(refreshDrawingForRow:)
	public func refreshDrawing(forRow row: Int) {
		refreshDrawing(forRow: row, skipOcclusionCheck: false)
	}

	@objc(refreshDrawingForRow:skipOcclusionCheck:)
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

	@objc(refreshDrawingForMember:)
	public func refreshDrawing(for member: ChannelUser) {
		refreshDrawing(forRow: row(forItem: member))
	}

	@objc(refreshDrawingForChangesToPreference:)
	public func refreshDrawing(forChangesToPreference preferenceKey: String) {
		let preferenceRanks: [String: UserRank] = [
			"User List Mode Badge Colors -> +y": .irCopByMode,
			"User List Mode Badge Colors -> +q": .channelOwner,
			"User List Mode Badge Colors -> +a": .superOperator,
			"User List Mode Badge Colors -> +o": .normalOperator,
			"User List Mode Badge Colors -> +h": .halfOperator,
			"User List Mode Badge Colors -> +v": .voiced,
		]

		guard let rank = preferenceRanks[preferenceKey] else {
			return
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

	@objc(drawContextMenuHighlightForRow:)
	public func drawContextMenuHighlight(forRow _: Int32) {}

	override public var allowsVibrancy: Bool {
		true
	}

	@objc
	override public func applicationAppearanceChanged() {
		refreshForAppearanceChange()
	}

	@objc
	override public func systemAppearanceChanged() {
		refreshForAppearanceChange()
	}

	private func refreshForAppearanceChange() {
		invalidateSelectionBackground()
		refreshAllDrawings(skipOcclusionCheck: true)
		needsDisplay = true
	}

	@objc
	private func windowDidBecomeKey(_ notification: Notification) {
		windowKeyStateChanged(notification)
	}

	@objc
	private func windowDidResignKey(_ notification: Notification) {
		destroyUserInfoPopoverOnWindowKeyChange()
		windowKeyStateChanged(notification)
	}

	private func windowKeyStateChanged(_: Notification) {
		respondToRequiresRedraw()
	}

	@objc
	private func windowMainStateChanged(_: Notification) {
		enumerateAvailableRowViews { rowView, _ in
			(rowView as? MemberListRowCell)?.refreshEmphasis()
		}

		respondToRequiresRedraw()
	}

	@objc
	private func mainWindowRequiresRedraw(_: Notification) {
		respondToRequiresRedraw()
	}

	private func respondToRequiresRedraw() {
		refreshAllDrawings(skipOcclusionCheck: true)
	}

	// MARK: - Events

	override public func menu(for _: NSEvent) -> NSMenu? {
		let row = rowBeneathMouse
		guard row >= 0, isGroupRow(row) == false else {
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

		switch event.keyCode {
		case 125, 126: // down / up arrow
			super.keyDown(with: event)
		case 123, 124, 116, 121: // left / right / page up / page down
			break
		default:
			keyDelegate.memberListKeyDown(event)
		}
	}
}
