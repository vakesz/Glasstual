// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit

/// The sidebar's native responder, data source and delegate share one owner.
/// AppKit owns the row views; the chat model owns selection and ordering.
final class SidebarOutlineView: NSOutlineView, NSOutlineViewDataSource, NSOutlineViewDelegate {
	private static let columnIdentifier = NSUserInterfaceItemIdentifier("sidebar-title")
	private static let dragType = NSPasteboard.PasteboardType("com.vakesz.glasstual.sidebar-row")
	private static let expandedItemKey = "NSObject"
	let tree = SidebarOutlineTree()
	private let model: Sidebar
	private let redirectTyping: (String) -> Void
	private var snapshot: SidebarOutlineSnapshot?
	private var pendingSnapshot: SidebarOutlineSnapshot?
	private var updateTask: Task<Void, Never>?
	private var isApplyingSnapshot = false
	private var draggedIdentity: SidebarNodeID?
	private var presentedMenu: NSMenu?

	init(model: Sidebar, redirectTyping: @escaping (String) -> Void) {
		self.model = model
		self.redirectTyping = redirectTyping
		super.init(frame: .zero)
		let column = NSTableColumn(identifier: Self.columnIdentifier)
		column.resizingMask = .autoresizingMask
		addTableColumn(column)
		outlineTableColumn = column
		headerView = nil
		style = .sourceList
		rowSizeStyle = .default
		backgroundColor = .clear
		allowsMultipleSelection = false
		allowsEmptySelection = true
		allowsColumnReordering = false
		columnAutoresizingStyle = .uniformColumnAutoresizingStyle
		autosaveExpandedItems = false
		dataSource = self
		delegate = self
		target = self
		doubleAction = #selector(activateClickedRow(_:))
		setAccessibilityIdentifier("sidebar")
		registerForDraggedTypes([Self.dragType])
		setDraggingSourceOperationMask(.move, forLocal: true)
		setDraggingSourceOperationMask([], forLocal: false)
	}

	@available(*, unavailable)
	required init?(coder _: NSCoder) {
		fatalError("SidebarOutlineView is programmatic")
	}

	isolated deinit { updateTask?.cancel() }

	override func setFrameSize(_ newSize: NSSize) {
		let widthChanged = abs(bounds.width - newSize.width) > 0.5
		super.setFrameSize(newSize)
		if widthChanged, newSize.width > 0, !tableColumns.isEmpty {
			sizeLastColumnToFit()
		}
	}

	override func viewDidMoveToWindow() {
		super.viewDidMoveToWindow()
		if window != nil, bounds.width > 0 {
			sizeLastColumnToFit()
		}
	}

	func enqueue(_ next: SidebarOutlineSnapshot) {
		pendingSnapshot = next
		guard updateTask == nil else { return }
		updateTask = Task { [weak self] in
			guard let self, !Task.isCancelled else { return }
			updateTask = nil
			guard let latest = pendingSnapshot else { return }
			pendingSnapshot = nil
			apply(latest)
		}
	}

	func stopUpdates() {
		updateTask?.cancel()
		updateTask = nil
		pendingSnapshot = nil
		presentedMenu?.cancelTracking()
		presentedMenu = nil
	}

	/// Called outside view creation and delegate callbacks. The guard separates
	/// AppKit notifications caused by projection from actual user interactions.
	func apply(_ proposed: SidebarOutlineSnapshot) {
		// A click can change selection while a SwiftUI refresh is queued.
		// Rebuild that stale snapshot before it can reselect the previous row.
		let next = proposed.selectedIdentifier == model.selectedItemIdentifier
			? proposed : SidebarOutlineSnapshot(model: model)
		guard snapshot != next else { return }
		let previousSelection = snapshot?.selectedIdentifier
		let previousNode = node(at: selectedRow)
		let contentChanged = snapshot?.rows != next.rows
			|| snapshot?.favorites != next.favorites
			|| snapshot?.knownIdentifiers != next.knownIdentifiers
			|| snapshot?.isFiltering != next.isFiltering
		let viewport = viewportAnchor()
		isApplyingSnapshot = true
		defer { isApplyingSnapshot = false }
		let structureChanged = contentChanged && tree.apply(next)
		snapshot = next
		if structureChanged {
			reloadData()
		}
		if contentChanged {
			for root in tree.roots {
				guard case let .server(server) = root.content else { continue }
				if server.isExpanded {
					expandItem(root)
				} else {
					collapseItem(root)
				}
			}
		}
		let selected = selectionNode(identifier: next.selectedIdentifier, previous: previousNode)
		let selectedIndex = selected.map { row(forItem: $0) } ?? -1
		let selection = selectedIndex >= 0 ? IndexSet(integer: selectedIndex) : []
		if selectedRowIndexes != selection {
			selectRowIndexes(selection, byExtendingSelection: false)
		}
		if contentChanged {
			refreshVisibleRows()
		}
		if structureChanged, let viewport,
		   let node = tree.nodes[viewport.identity], row(forItem: node) >= 0,
		   let scrollView = enclosingScrollView
		{
			var origin = scrollView.contentView.bounds.origin
			origin.y = rect(ofRow: row(forItem: node)).minY - viewport.offset
			scrollView.contentView.scroll(to: origin)
			scrollView.reflectScrolledClipView(scrollView.contentView)
		}
		if previousSelection != next.selectedIdentifier, selectedIndex >= 0 {
			scrollRowToVisible(selectedIndex)
		}
	}

	private func selectionNode(identifier: String?, previous: SidebarOutlineNode?) -> SidebarOutlineNode? {
		guard let identifier else { return nil }
		if let previous, previous.identity.itemIdentifier == identifier, row(forItem: previous) >= 0 {
			return previous
		}
		return [tree.node(withItemIdentifier: identifier), tree.nodes[.favorite(identifier)]]
			.compactMap(\.self).first { row(forItem: $0) >= 0 }
	}

	private func viewportAnchor() -> (identity: SidebarNodeID, offset: CGFloat)? {
		let visible = rows(in: visibleRect)
		guard visible.location != NSNotFound, visible.length > 0,
		      let node = node(at: visible.location) else { return nil }
		return (node.identity, rect(ofRow: visible.location).minY - visibleRect.minY)
	}

	private func refreshVisibleRows() {
		let visible = rows(in: visibleRect)
		guard visible.location != NSNotFound, visible.length > 0 else { return }
		for index in visible.location ..< min(NSMaxRange(visible), numberOfRows) {
			guard let node = node(at: index) else { continue }
			if let cell = view(atColumn: 0, row: index, makeIfNecessary: false) as? SidebarCellView {
				configure(cell, with: node)
			}
		}
	}

	func node(at row: Int) -> SidebarOutlineNode? {
		guard row >= 0, row < numberOfRows else { return nil }
		return item(atRow: row) as? SidebarOutlineNode
	}

	// MARK: - Native rows

	func outlineView(_: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
		(item as? SidebarOutlineNode)?.children.count ?? tree.roots.count
	}

	func outlineView(_: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
		((item as? SidebarOutlineNode)?.children ?? tree.roots)[index]
	}

	func outlineView(_: NSOutlineView, isItemExpandable item: Any) -> Bool {
		(item as? SidebarOutlineNode)?.children.isEmpty == false
	}

	func outlineView(_: NSOutlineView, rowViewForItem _: Any) -> NSTableRowView? {
		let identifier = NSUserInterfaceItemIdentifier("sidebar-row")
		let row = makeView(withIdentifier: identifier, owner: self) as? SidebarRowView
			?? SidebarRowView(frame: .zero)
		row.identifier = identifier
		return row
	}

	func outlineView(_: NSOutlineView, viewFor _: NSTableColumn?, item: Any) -> NSView? {
		guard let node = item as? SidebarOutlineNode else { return nil }
		let cell = makeView(withIdentifier: SidebarCellView.reuseIdentifier, owner: self) as? SidebarCellView
			?? SidebarCellView(frame: .zero)
		configure(cell, with: node)
		return cell
	}

	private func configure(_ cell: SidebarCellView, with node: SidebarOutlineNode) {
		let identity = node.identity
		cell.configure(with: node)
		cell.configureAccessibilityActions(
			with: node,
			canMoveUp: canMove(identity, upward: true),
			canMoveDown: canMove(identity, upward: false)
		)
		cell.showMenu = { [weak self] in self?.showMenu(for: identity) ?? false }
		cell.move = { [weak self] upward in self?.move(identity, upward: upward) ?? false }
	}

	func outlineView(_: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
		guard let node = item as? SidebarOutlineNode else { return rowHeight }
		if case .favorite = node.identity {
			return 40
		}
		return rowHeight
	}

	func outlineView(_: NSOutlineView, shouldSelectItem item: Any) -> Bool {
		(item as? SidebarOutlineNode)?.identity != .favorites
	}

	func outlineView(_: NSOutlineView, selectionIndexesForProposedSelection proposed: IndexSet) -> IndexSet {
		guard !isApplyingSnapshot, proposed.isEmpty else { return proposed }
		return selectedRowIndexes
	}

	func outlineViewSelectionDidChange(_: Notification) {
		guard !isApplyingSnapshot, let node = node(at: selectedRow) else { return }
		model.selectFromView(node.identity.itemIdentifier)
	}

	func outlineView(_: NSOutlineView, shouldCollapseItem _: Any) -> Bool {
		isApplyingSnapshot || snapshot?.isFiltering != true
	}

	func outlineViewItemDidExpand(_ notification: Notification) {
		expansionChanged(notification, expanded: true)
	}

	func outlineViewItemDidCollapse(_ notification: Notification) {
		expansionChanged(notification, expanded: false)
	}

	private func expansionChanged(_ notification: Notification, expanded: Bool) {
		guard !isApplyingSnapshot,
		      let node = notification.userInfo?[Self.expandedItemKey] as? SidebarOutlineNode else { return }
		switch node.identity {
		case let .server(identifier): model.setExpanded(expanded, forServerID: identifier)
		case .favorites: model.favoritesExpanded = expanded
		case .conversation, .favorite: break
		}
	}

	@objc private func activateClickedRow(_: Any?) {
		guard let node = node(at: clickedRow), node.identity != .favorites else { return }
		model.selectFromView(node.identity.itemIdentifier)
		model.mainWindow?.sidebarItemDoubleClicked()
	}

	override func keyDown(with event: NSEvent) {
		let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
		if modifiers == .shift, event.charactersIgnoringModifiers?.unicodeScalars.first?.value == UInt32(NSF10FunctionKey) {
			showContextMenuForSelection(nil)
			return
		}
		if let text = TypingRedirect.text(for: event.characters ?? "",
		                                  commandIsPressed: modifiers.contains(.command), controlIsPressed: modifiers.contains(.control))
		{
			if let window = model.mainWindow {
				window.redirectKeyDown(event)
			} else {
				redirectTyping(text)
			}
			return
		}
		super.keyDown(with: event)
	}

	// MARK: - Context menus

	override func showContextMenuForSelection(_: Any?) {
		guard let menu = selectionContextMenu() else { return }
		let anchor = selectedRow >= 0 ? rect(ofRow: selectedRow) : visibleRect
		menu.popUp(positioning: nil, at: NSPoint(x: anchor.midX, y: anchor.maxY), in: self)
	}

	func selectionContextMenu() -> NSMenu? {
		contextMenu(for: node(at: selectedRow)?.identity)
	}

	override func menu(for event: NSEvent) -> NSMenu? {
		let point = convert(event.locationInWindow, from: nil)
		return contextMenu(for: node(at: row(at: point))?.identity)
	}

	func contextMenu(for identity: SidebarNodeID?) -> NSMenu? {
		guard let commands = model.mainWindow?.menuController else { return nil }
		let item = identity.flatMap { model.item(withID: $0.itemIdentifier) }
		guard identity == nil || item != nil, let source = commands.contextMenu(for: item) else { return nil }
		let menu = MenuContentView.nativeMenu(menu: source.menu, context: source.context) { [weak model] in
			guard let identifier = identity?.itemIdentifier, model?.item(withID: identifier) != nil else { return }
			model?.selectFromView(identifier)
		}
		if let identity, identity.isReorderable {
			menu.addItem(.separator())
			for upward in [true, false] {
				let item = NSMenuItem(title: String(localized: upward ? .MainWindow.sidebarMoveUp : .MainWindow.sidebarMoveDown),
				                      action: #selector(moveMenuItem(_:)), keyEquivalent: "")
				item.target = self
				item.representedObject = SidebarMenuMove(identity: identity, upward: upward)
				item.isEnabled = canMove(identity, upward: upward)
				menu.addItem(item)
			}
		}
		presentedMenu = menu
		return menu
	}

	private func showMenu(for identity: SidebarNodeID) -> Bool {
		guard let node = tree.nodes[identity], row(forItem: node) >= 0,
		      let menu = contextMenu(for: identity) else { return false }
		let row = rect(ofRow: row(forItem: node))
		return menu.popUp(positioning: nil, at: NSPoint(x: row.midX, y: row.maxY), in: self)
	}

	@objc private func moveMenuItem(_ sender: NSMenuItem) {
		guard let request = sender.representedObject as? SidebarMenuMove else { return }
		_ = move(request.identity, upward: request.upward)
	}

	// MARK: - Reordering

	private func adjacentMove(_ identity: SidebarNodeID, upward: Bool) -> SidebarOutlineMove? {
		guard !model.isFiltering, identity.isReorderable, let node = tree.nodes[identity] else { return nil }
		let siblings = node.parentIdentifier.flatMap { tree.nodes[.server($0)]?.children } ?? tree.roots
			.filter { $0.identity != .favorites }
		guard let index = siblings.firstIndex(where: { $0.identity == identity }) else { return nil }
		let destination = upward ? index - 1 : index + 2
		return proposedMove(identity: identity, parent: node.parentIdentifier, childIndex: destination)
	}

	func canMove(_ identity: SidebarNodeID, upward: Bool) -> Bool {
		adjacentMove(identity, upward: upward) != nil
	}

	@discardableResult
	func move(_ identity: SidebarNodeID, upward: Bool) -> Bool {
		guard let move = adjacentMove(identity, upward: upward) else { return false }
		return perform(move)
	}

	func proposedMove(identity: SidebarNodeID, parent: String?, childIndex: Int) -> SidebarOutlineMove? {
		guard !model.isFiltering, identity.isReorderable, childIndex >= 0, let node = tree.nodes[identity],
		      node.parentIdentifier == parent else { return nil }
		let siblings = parent.flatMap { tree.nodes[.server($0)]?.children } ?? tree.roots.filter { $0.identity != .favorites }
		guard childIndex <= siblings.count, let from = siblings.firstIndex(where: { $0.identity == identity }),
		      let move = SidebarReorderPolicy.move(fromOffsets: IndexSet(integer: from), toOffset: childIndex),
		      siblings.indices.contains(move.to) else { return nil }
		if case let .conversation(source) = node.content,
		   case let .conversation(destination) = siblings[move.to].content,
		   !SidebarReorderPolicy.permitsMove(draggedIsChannel: source.kind == .channel, destinationIsChannel: destination.kind == .channel)
		{
			return nil
		}
		return SidebarOutlineMove(identity: identity, parent: parent,
		                          before: childIndex < siblings.count ? siblings[childIndex].identity.itemIdentifier : nil)
	}

	private func perform(_ move: SidebarOutlineMove) -> Bool {
		guard !model.isFiltering else { return false }
		let items: [ChatItem]
		if let parent = move.parent {
			guard let session = model.sessions.first(where: { $0.uniqueIdentifier == parent }) else { return false }
			items = session.conversationList
		} else {
			items = model.sessions
		}
		guard let from = items.firstIndex(where: { $0.uniqueIdentifier == move.identity.itemIdentifier }) else { return false }
		let insertion: Int
		if let before = move.before {
			guard let index = items.firstIndex(where: { $0.uniqueIdentifier == before }) else { return false }
			insertion = index
		} else {
			insertion = items.count
		}
		if let parent = move.parent {
			return model.moveConversations(onServerWithID: parent, fromOffsets: IndexSet(integer: from), toOffset: insertion)
		}
		return model.moveServers(fromOffsets: IndexSet(integer: from), toOffset: insertion)
	}

	func outlineView(_: NSOutlineView, pasteboardWriterForItem item: Any) -> (any NSPasteboardWriting)? {
		guard !model.isFiltering, let node = item as? SidebarOutlineNode, node.identity.isReorderable else { return nil }
		draggedIdentity = node.identity
		let writer = NSPasteboardItem()
		writer.setData(Data(), forType: Self.dragType)
		return writer
	}

	func outlineView(_: NSOutlineView, draggingSession _: NSDraggingSession, endedAt _: NSPoint, operation _: NSDragOperation) {
		draggedIdentity = nil
	}

	func outlineView(_: NSOutlineView, validateDrop info: any NSDraggingInfo, proposedItem item: Any?, proposedChildIndex index: Int)
		-> NSDragOperation
	{
		dropMove(info, item: item, index: index) == nil ? [] : .move
	}

	func outlineView(_: NSOutlineView, acceptDrop info: any NSDraggingInfo, item: Any?, childIndex index: Int) -> Bool {
		guard let move = dropMove(info, item: item, index: index) else { return false }
		return perform(move)
	}

	private func dropMove(_ info: any NSDraggingInfo, item: Any?, index: Int) -> SidebarOutlineMove? {
		guard info.draggingSource as? NSOutlineView === self, let identity = draggedIdentity else { return nil }
		let parent = item as? SidebarOutlineNode
		if let parent, case .server = parent.identity {} else if parent != nil {
			return nil
		}
		let favoriteOffset = parent == nil && tree.roots.first?.identity == .favorites ? 1 : 0
		return proposedMove(identity: identity, parent: parent?.identity.itemIdentifier, childIndex: index - favoriteOffset)
	}
}

struct SidebarOutlineMove: Equatable {
	let identity: SidebarNodeID
	let parent: String?
	let before: String?
}

private struct SidebarMenuMove {
	let identity: SidebarNodeID
	let upward: Bool
}

/// Keep native selection grey while focus moves between the sidebar and input.
/// AppKit still owns selection drawing, accessibility and keyboard focus.
private final class SidebarRowView: NSTableRowView {
	override var isEmphasized: Bool {
		get { false }
		set {
			guard newValue || super.isEmphasized else { return }
			super.isEmphasized = false
		}
	}
}
