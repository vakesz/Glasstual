// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
@testable import Glasstual
import Testing

@MainActor
@Suite("Native sidebar outline", .serialized)
struct SidebarOutlineViewTests {
	private final class Fixture {
		let model = Sidebar()
		let session = TestServerSession()
		let other = TestServerSession()
		let chat = ChatSession()
		let channels: [Conversation]
		let outline: SidebarOutlineView
		let window: NSWindow

		init(channelNames: [String] = ["#python", "#linux", "#security", "#programming", "#c", "#fedora", "#git"]) {
			session.config.connectionName = "Libera Chat"
			other.config.connectionName = "DumaNet"
			session.sidebarItemIsExpanded = true
			other.sidebarItemIsExpanded = true
			channels = channelNames.map {
				Conversation(config: ConversationConfig(name: $0))
			}
			for channel in channels {
				channel.associatedSession = session
			}
			session.conversationList = channels
			chat.sessions = [session, other]
			let chat = chat
			model.chatSessionSource = { chat }
			model.filterText = ""
			outline = SidebarOutlineView(model: model, redirectTyping: { _ in })
			let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 220, height: 420))
			outline.frame = scroll.bounds
			outline.autoresizingMask = [.width]
			scroll.documentView = outline
			window = NSWindow(contentRect: scroll.frame, styleMask: .borderless, backing: .buffered, defer: false)
			window.isReleasedWhenClosed = false
			window.contentView = scroll
			apply()
		}

		func apply() {
			outline.apply(SidebarOutlineSnapshot(model: model))
			window.contentView?.layoutSubtreeIfNeeded()
		}

		func close() {
			outline.stopUpdates()
			window.close()
		}
	}

	@Test("Repeated refreshes retain one selected row and one correctly configured cell per item")
	func refreshesDoNotLeaveGhostRows() throws {
		let fixture = Fixture()
		defer { fixture.close() }
		let identity = SidebarNodeID.conversation(fixture.channels[0].uniqueIdentifier)
		let original = try #require(fixture.outline.tree.nodes[identity])
		#expect(fixture.window.makeFirstResponder(fixture.outline))
		for iteration in 0 ..< 24 {
			let selected = fixture.channels[iteration % fixture.channels.count]
			fixture.channels[3].unreadCount = iteration
			fixture.model.filterText = ""
			fixture.model.select(selected)
			fixture.apply()
			#expect(fixture.outline.tree.nodes[identity] === original)
			#expect(fixture.outline.selectedRowIndexes.count == 1)
			#expect(fixture.outline.node(at: fixture.outline.selectedRow)?.identity.itemIdentifier == selected.uniqueIdentifier)
			var selectedViews = 0
			for index in 0 ..< fixture.outline.numberOfRows {
				let node = try #require(fixture.outline.node(at: index))
				let cell = try #require(fixture.outline.view(atColumn: 0, row: index, makeIfNecessary: true) as? SidebarCellView)
				let title = switch node.content {
				case let .server(server): server.title
				case let .conversation(conversation): conversation.title
				}
				#expect(cell.titleField.stringValue == title)
				if let row = fixture.outline.rowView(atRow: index, makeIfNecessary: true), row.isSelected {
					selectedViews += 1
				}
			}
			#expect(selectedViews == 1)
			#expect(fixture.window.firstResponder === fixture.outline)
		}
	}

	@Test("Native focus changes keep both departing and selected rows neutral", arguments: [false, true])
	func selectionStaysNeutralDuringFocusChanges(dark: Bool) throws {
		let fixture = Fixture()
		defer { fixture.close() }
		fixture.window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
		fixture.model.select(fixture.channels[0])
		fixture.apply()
		let previousIndex = fixture.outline.selectedRow
		let previous = try #require(fixture.outline.rowView(atRow: previousIndex, makeIfNecessary: true))
		#expect(fixture.window.makeFirstResponder(fixture.outline))
		// AppKit emphasizes the old selection when the sidebar takes focus,
		// before it moves selection to the clicked row.
		previous.isEmphasized = true
		#expect(previous.isSelected)
		#expect(!previous.isEmphasized)
		let next = try #require(fixture.outline.tree.node(withItemIdentifier: fixture.channels[1].uniqueIdentifier))
		let nextIndex = fixture.outline.row(forItem: next)
		fixture.outline.selectRowIndexes(IndexSet(integer: nextIndex), byExtendingSelection: false)
		let selected = try #require(fixture.outline.rowView(atRow: nextIndex, makeIfNecessary: true))
		selected.isEmphasized = true
		#expect(!previous.isSelected)
		#expect(!previous.isEmphasized)
		#expect(selected.isSelected)
		#expect(!selected.isEmphasized)
		#expect(fixture.model.selectedItem === fixture.channels[1])
		#expect(fixture.window.firstResponder === fixture.outline)
		try checkSelectedCellStyle(in: fixture.outline, foreground: .secondaryLabelColor)
	}

	@Test("An older refresh cannot reselect the previous channel after native selection changes")
	func staleRefreshKeepsCurrentSelection() throws {
		let fixture = Fixture()
		defer { fixture.close() }
		fixture.model.select(fixture.channels[0])
		fixture.apply()
		fixture.channels[3].unreadCount = 1
		fixture.model.filterText = ""
		let pending = SidebarOutlineSnapshot(model: fixture.model)
		let next = try #require(fixture.outline.tree.node(withItemIdentifier: fixture.channels[1].uniqueIdentifier))
		let nextIndex = fixture.outline.row(forItem: next)
		fixture.outline.selectRowIndexes(IndexSet(integer: nextIndex), byExtendingSelection: false)
		#expect(fixture.model.selectedItem === fixture.channels[1])

		// Deliver the refresh captured before the click, as the deferred renderer does.
		fixture.outline.apply(pending)
		#expect(fixture.outline.selectedRow == nextIndex)
		#expect(fixture.outline.rowView(atRow: nextIndex, makeIfNecessary: true)?.isSelected == true)
		let previous = try #require(fixture.outline.tree.node(withItemIdentifier: fixture.channels[0].uniqueIdentifier))
		#expect(fixture.outline.rowView(atRow: fixture.outline.row(forItem: previous), makeIfNecessary: true)?.isSelected == false)
	}

	@Test("Filtering hides the selected row without changing the conversation or discarding its identity")
	func filterKeepsSelectionAndIdentity() throws {
		let fixture = Fixture()
		defer { fixture.close() }
		let selected = fixture.channels[0]
		fixture.model.select(selected)
		fixture.apply()
		let node = try #require(fixture.outline.tree.node(withItemIdentifier: selected.uniqueIdentifier))
		fixture.model.filterText = "linux"
		fixture.apply()
		#expect(fixture.outline.selectedRowIndexes.isEmpty)
		#expect(fixture.model.selectedItem === selected)
		#expect(fixture.outline.tree.node(withItemIdentifier: selected.uniqueIdentifier) === node)
		fixture.model.filterText = ""
		fixture.apply()
		#expect(fixture.outline.node(at: fixture.outline.selectedRow) === node)
		fixture.session.conversationList.removeAll { $0 === selected }
		fixture.model.itemWasRemoved(selected)
		fixture.model.filterText = ""
		fixture.apply()
		#expect(fixture.outline.tree.node(withItemIdentifier: selected.uniqueIdentifier) == nil)
	}

	@Test("Native collapse selects the parent and a filter refuses collapse without changing saved disclosure")
	func disclosurePreservesModelPolicy() throws {
		let fixture = Fixture()
		defer { fixture.close() }
		fixture.model.select(fixture.channels[0])
		fixture.apply()
		let parent = try #require(fixture.outline.tree.nodes[.server(fixture.session.uniqueIdentifier)])
		fixture.outline.collapseItem(parent)
		#expect(fixture.model.selectedItem === fixture.session)
		#expect(!fixture.session.sidebarItemIsExpanded)
		fixture.apply()
		fixture.model.filterText = "linux"
		fixture.apply()
		#expect(fixture.outline.isItemExpanded(parent))
		fixture.outline.collapseItem(parent)
		#expect(fixture.outline.isItemExpanded(parent))
		#expect(!fixture.session.sidebarItemIsExpanded)
		fixture.model.filterText = ""
		fixture.apply()
		#expect(!fixture.outline.isItemExpanded(parent))
	}

	@Test("Reused cells clear failed-join icons, badges and security state")
	func reusedCellsResetPresentation() throws {
		let fixture = Fixture()
		defer { fixture.close() }
		fixture.channels[0].errorOnLastJoinAttempt = true
		fixture.channels[0].unreadCount = 13
		fixture.model.filterText = ""
		fixture.apply()
		let failed = try #require(fixture.outline.tree.node(withItemIdentifier: fixture.channels[0].uniqueIdentifier))
		let normal = try #require(fixture.outline.tree.node(withItemIdentifier: fixture.channels[1].uniqueIdentifier))
		let cell = SidebarCellView(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
		cell.configure(with: failed)
		#expect(!cell.leadingImage.isHidden)
		#expect(!cell.badge.isHidden)
		#expect(failed.accessibilityDescription.contains(String(localized: .MainWindow.sidebarJoinFailed)))
		cell.configure(with: normal)
		#expect(cell.leadingImage.isHidden)
		#expect(cell.leadingImage.image == nil)
		#expect(cell.leadingImage.toolTip == nil)
		#expect(cell.badge.isHidden)
		#expect(cell.badge.toolTip == nil)
		#expect(cell.securityImage.isHidden)
		#expect(cell.titleField.stringValue == "#linux")
	}

	@Test("Drop boundaries reject background indices and foreign parents while retaining endpoint moves")
	func dropBoundaries() throws {
		let fixture = Fixture()
		defer { fixture.close() }
		let identity = SidebarNodeID.conversation(fixture.channels[0].uniqueIdentifier)
		let parent = fixture.session.uniqueIdentifier
		#expect(fixture.outline.node(at: -1) == nil)
		#expect(fixture.outline.node(at: fixture.outline.numberOfRows) == nil)
		#expect(fixture.outline.proposedMove(identity: identity, parent: parent, childIndex: -1) == nil)
		#expect(fixture.outline.proposedMove(identity: identity, parent: nil, childIndex: 0) == nil)
		#expect(fixture.outline.proposedMove(identity: identity, parent: fixture.other.uniqueIdentifier, childIndex: 0) == nil)
		let last = try #require(fixture.outline.proposedMove(identity: identity, parent: parent, childIndex: fixture.channels.count))
		#expect(last.before == nil)
		#expect(!fixture.outline.canMove(identity, upward: true))
		#expect(fixture.outline.move(identity, upward: false))
		#expect(fixture.session.conversationList[1] === fixture.channels[0])
		fixture.model.filterText = "python"
		fixture.apply()
		#expect(!fixture.outline.canMove(identity, upward: false))
		#expect(fixture.outline.proposedMove(identity: identity, parent: parent, childIndex: 0) == nil)
	}

	@Test("Exported sidebar cells expose reorder actions without duplicate text or changing native selection")
	func exportedSidebarAccessibility() throws {
		let fixture = Fixture(channelNames: ["#first", "#second", "#third"])
		defer { fixture.close() }
		fixture.model.select(fixture.channels[1])
		fixture.apply()
		fixture.window.setFrameOrigin(NSPoint(x: -4000, y: -4000))
		fixture.window.order(.below, relativeTo: 0)
		fixture.outline.layoutSubtreeIfNeeded()
		fixture.window.displayIfNeeded()
		let rows = NativeTableAccessibility.rows(in: fixture.outline)
		try #require(rows.count == fixture.outline.numberOfRows)
		let entries = NativeTableAccessibility.descendants(of: rows[2]).filter { $0.accessibilityRole() == .staticText }
		try #require(entries.count == 1)
		let entry = try #require(entries.first)
		let identity = SidebarNodeID.conversation(fixture.channels[1].uniqueIdentifier)
		let node = try #require(fixture.outline.tree.nodes[identity])
		#expect(entry.accessibilityLabel() == node.accessibilityDescription)
		#expect(entry.accessibilityChildren()?.isEmpty != false)
		let actions = try #require(entry.accessibilityCustomActions())
		#expect(actions.map(\.name) == [String(localized: .MainWindow.sidebarMoveUp), String(localized: .MainWindow.sidebarMoveDown)])
		let action = try #require(actions.first)
		#expect(try NSApp.sendAction(#require(action.selector), to: action.target, from: nil))
		#expect(fixture.session.conversationList.first === fixture.channels[1])
		#expect(fixture.model.selectedItem === fixture.channels[1])
		// This fixture has no MainWindow chat observer to publish the move.
		fixture.model.filterText = ""
		fixture.apply()
		let reorderedRows = NativeTableAccessibility.rows(in: fixture.outline)
		#expect(fixture.outline.selectedRow == 1)
		#expect(NativeTableAccessibility.isSelected(reorderedRows[1]))
		let reorderedEntry = try #require(NativeTableAccessibility.descendants(of: reorderedRows[1]).first {
			$0.accessibilityRole() == .staticText
		})
		#expect(reorderedEntry.accessibilityCustomActions()?.map(\.name) == [String(localized: .MainWindow.sidebarMoveDown)])
		fixture.model.filterText = "second"
		fixture.apply()
		let filteredRows = NativeTableAccessibility.rows(in: fixture.outline)
		let filteredEntry = try #require(NativeTableAccessibility.descendants(of: filteredRows[1]).first {
			$0.accessibilityRole() == .staticText
		})
		#expect(filteredEntry.accessibilityCustomActions()?.isEmpty == true)
	}

	@Test("Either the app preference or Reduce Transparency makes the entire sidebar opaque")
	func opaqueSidebarPolicy() {
		#expect(!SidebarAppearance.usesOpaqueBackground(translucencyDisabled: false, reducesTransparency: false))
		#expect(SidebarAppearance.usesOpaqueBackground(translucencyDisabled: true, reducesTransparency: false))
		#expect(SidebarAppearance.usesOpaqueBackground(translucencyDisabled: false, reducesTransparency: true))
		#expect(SidebarAppearance.usesOpaqueBackground(translucencyDisabled: true, reducesTransparency: true))
	}

	@Test(
		"Long labels, failed joins and unread counts stay within native rows in both appearances",
		arguments: [false, true],
		["en", "de", "hu"]
	)
	func renderedSidebarFixture(dark: Bool, language: String) throws {
		let longTitle = switch language {
		case "de": "Gemeinschaft für Programmiersprachen und Betriebssysteme"
		case "hu": "Programozási nyelvek és operációs rendszerek közössége"
		default: "Programming languages and operating systems community"
		}
		let fixture = Fixture(channelNames: ["#python", "#linux", "#\(longTitle)", "#security", "#programming", "#fedora", "#git"])
		defer { fixture.close() }
		fixture.window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
		fixture.session.config.connectionName = longTitle
		fixture.session.config.sidebarIdentity = ServerIdentityStyle(color: .teal, icon: .code)
		fixture.other.config.sidebarIdentity = ServerIdentityStyle(color: .purple, icon: .people)
		fixture.model.toggleFavorite(fixture.channels[0])
		fixture.model.toggleFavorite(fixture.channels[2])
		fixture.session.setConnectionTransportForTesting(.connected)
		for channel in fixture.channels.prefix(3) {
			channel.activate()
		}
		fixture.channels[2].unreadCount = 1367
		fixture.channels[3].errorOnLastJoinAttempt = true
		fixture.channels[4].unreadCount = 52
		fixture.model.filterText = ""
		fixture.model.select(fixture.channels[1])
		fixture.apply()
		// Realize the native rows without covering or focusing another window.
		fixture.window.setFrameOrigin(NSPoint(x: -4000, y: -4000))
		fixture.window.animationBehavior = .none
		fixture.window.order(.below, relativeTo: 0)
		fixture.window.contentView?.layoutSubtreeIfNeeded()
		fixture.outline.layoutSubtreeIfNeeded()
		fixture.outline.scrollRowToVisible(0)
		for index in 0 ..< fixture.outline.numberOfRows {
			let cell = try #require(fixture.outline.view(atColumn: 0, row: index, makeIfNecessary: true) as? SidebarCellView)
			cell.layoutSubtreeIfNeeded()
			#expect(cell.bounds.width > fixture.outline.bounds.width - 70)
			// NSTextField's frame extends beyond its alignment rect to leave
			// room for drawing insets; measure the aligned label content.
			let title = cell.convert(cell.titleField.alignmentRect(forFrame: cell.titleField.frame), from: cell.titleField.superview)
			#expect(title.minX >= -0.5)
			#expect(title.maxX <= cell.bounds.maxX + 0.5)
			if !cell.badge.isHidden {
				let badge = cell.badge.convert(cell.badge.bounds, to: cell)
				#expect(title.maxX < badge.minX)
			}
		}
		fixture.window.displayIfNeeded()
		try checkSelectedCellStyle(in: fixture.outline)
		let view = try #require(fixture.window.contentView)
		let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
		view.effectiveAppearance.performAsCurrentDrawingAppearance {
			view.cacheDisplay(in: view.bounds, to: bitmap)
		}
		let png = try #require(bitmap.representation(using: .png, properties: [:]))
		#expect(png.count > 2000)
		let output = try #require(ApplicationPaths.applicationSupportURL)
			.appending(path: "review-fixtures", directoryHint: .isDirectory)
		try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
		try png.write(to: output.appending(path: "sidebar-\(language)-\(dark ? "dark" : "light").png"))
	}

	@Test("Favorite rows share conversation selection while keeping native identities distinct")
	func favoritesRetainSelectionAndNativeIdentity() throws {
		let fixture = Fixture()
		defer { fixture.close() }
		let conversation = fixture.channels[0]
		fixture.model.toggleFavorite(conversation)
		fixture.apply()
		let favorite = try #require(fixture.outline.tree.nodes[.favorite(conversation.uniqueIdentifier)])
		let ordinary = try #require(fixture.outline.tree.nodes[.conversation(conversation.uniqueIdentifier)])
		let group = try #require(fixture.outline.tree.nodes[.favorites])
		#expect(favorite !== ordinary)
		#expect(fixture.outline.tree.roots.first === group)
		#expect(!fixture.outline.outlineView(fixture.outline, shouldSelectItem: group))
		#expect(favorite.accessibilityDescription.contains("Libera Chat"))
		let favoriteIndex = fixture.outline.row(forItem: favorite)
		fixture.outline.selectRowIndexes(IndexSet(integer: favoriteIndex), byExtendingSelection: false)
		#expect(fixture.model.selectedItem === conversation)
		conversation.unreadCount = 4
		fixture.model.filterText = ""
		fixture.apply()
		#expect(fixture.outline.node(at: fixture.outline.selectedRow) === favorite)
		#expect(fixture.outline.selectedRowIndexes.count == 1)
		let favoriteCell = try #require(fixture.outline.view(atColumn: 0, row: favoriteIndex, makeIfNecessary: true) as? SidebarCellView)
		#expect(favoriteCell.subtitleField.stringValue == "Libera Chat")
		#expect(favoriteCell.networkImage.isHidden == false)
		#expect(favoriteCell.accessibilityIdentifier() == "sidebar-favorite-" + conversation.uniqueIdentifier)
		fixture.model.toggleFavorite(conversation)
		fixture.apply()
		#expect(fixture.outline.node(at: fixture.outline.selectedRow) === ordinary)
		#expect(fixture.model.selectedItem === conversation)
		#expect(fixture.outline.tree.nodes[.favorite(conversation.uniqueIdentifier)] == nil)
	}

	@Test("Favorites do not shift network reorder destinations or allow dragging shortcut rows")
	func favoritesPreserveNetworkReordering() throws {
		let fixture = Fixture()
		defer { fixture.close() }
		let conversation = fixture.channels[0]
		fixture.model.toggleFavorite(conversation)
		fixture.apply()
		let favorite = try #require(fixture.outline.tree.nodes[.favorite(conversation.uniqueIdentifier)])
		#expect(fixture.outline.outlineView(fixture.outline, pasteboardWriterForItem: favorite) == nil)
		#expect(!fixture.outline.canMove(favorite.identity, upward: false))
		#expect(fixture.outline.proposedMove(identity: .server(fixture.session.uniqueIdentifier), parent: nil, childIndex: 2)?
			.before == nil)
		#expect(fixture.outline.move(.server(fixture.session.uniqueIdentifier), upward: false))
		#expect(fixture.chat.sessions.map(\.uniqueIdentifier) == [fixture.other, fixture.session].map(\.uniqueIdentifier))
	}

	@Test("Reading a filtered favorite keeps the transcript selected and restores its native row")
	func attentionFilterRetainsFavoriteIdentity() throws {
		let fixture = Fixture()
		defer { fixture.close() }
		let conversation = fixture.channels[0]
		fixture.model.toggleFavorite(conversation)
		conversation.unreadCount = 1
		fixture.model.filter = .unread
		fixture.model.select(conversation)
		fixture.apply()
		let favorite = try #require(fixture.outline.tree.nodes[.favorite(conversation.uniqueIdentifier)])
		conversation.unreadCount = 0
		fixture.model.filterText = ""
		fixture.apply()
		#expect(fixture.outline.numberOfRows == 0)
		#expect(fixture.model.selectedItem === conversation)
		#expect(fixture.outline.tree.nodes[.favorite(conversation.uniqueIdentifier)] === favorite)
		fixture.model.filter = .all
		fixture.apply()
		#expect(fixture.outline.row(forItem: favorite) >= 0)
		#expect(fixture.outline.selectedRowIndexes.count == 1)
	}

	@Test("Server identity styling reaches headers and favorite subtitles without changing error colors")
	func serverIdentityColorsRemainSeparateFromSemanticState() throws {
		let fixture = Fixture()
		defer { fixture.close() }
		let style = ServerIdentityStyle(color: .purple, icon: .star)
		fixture.session.config.sidebarIdentity = style
		fixture.channels[0].errorOnLastJoinAttempt = true
		fixture.model.toggleFavorite(fixture.channels[0])
		fixture.apply()
		let server = try #require(fixture.outline.tree.nodes[.server(fixture.session.uniqueIdentifier)])
		let favorite = try #require(fixture.outline.tree.nodes[.favorite(fixture.channels[0].uniqueIdentifier)])
		let ordinary = try #require(fixture.outline.tree.nodes[.conversation(fixture.channels[1].uniqueIdentifier)])
		let cell = SidebarCellView(frame: NSRect(x: 0, y: 0, width: 200, height: 40))
		cell.configure(with: server)
		#expect(cell.leadingImage.contentTintColor == style.color.nsColor)
		#expect(cell.leadingImage.image != nil)
		#expect(cell.leadingImage.alphaValue < 1)
		cell.configure(with: favorite)
		#expect(cell.leadingImage.contentTintColor == .systemRed)
		#expect(cell.networkImage.contentTintColor == style.color.nsColor)
		#expect(cell.networkImage.image != nil)
		#expect(cell.subtitleField.stringValue == fixture.session.label)
		cell.backgroundStyle = .emphasized
		#expect(cell.networkImage.contentTintColor == .labelColor)
		#expect(cell.subtitleField.cell?.backgroundStyle == .emphasized)
		cell.backgroundStyle = .normal
		cell.configure(with: ordinary)
		#expect(cell.networkImage.isHidden)
		#expect(cell.networkImage.image == nil)
		#expect(cell.subtitleField.stringValue.isEmpty)
		#expect(cell.leadingImage.alphaValue == 1)
	}

	private func checkSelectedCellStyle(in outline: SidebarOutlineView, foreground expected: NSColor = .labelColor) throws {
		let row = try #require(outline.rowView(atRow: outline.selectedRow, makeIfNecessary: true))
		let cell = try #require(outline.view(atColumn: 0, row: outline.selectedRow, makeIfNecessary: true) as? SidebarCellView)
		// Exercise the emphasis requests AppKit sends when focus changes.
		// The native row and every nested control must keep the neutral style.
		for emphasized in [true, false] {
			row.isEmphasized = emphasized
			let style: NSView.BackgroundStyle = .normal
			#expect(!row.isEmphasized)
			#expect(cell.backgroundStyle == style)
			#expect(cell.titleField.cell?.backgroundStyle == style)
			#expect(cell.leadingImage.cell?.backgroundStyle == style)
			#expect(cell.securityImage.cell?.backgroundStyle == style)
			let foreground = try #require(cell.titleField.attributedStringValue.attribute(
				.foregroundColor,
				at: 0,
				effectiveRange: nil
			) as? NSColor)
			cell.effectiveAppearance.performAsCurrentDrawingAppearance {
				#expect(foreground.usingColorSpace(.deviceRGB) == expected.usingColorSpace(.deviceRGB))
			}
		}
	}
}
