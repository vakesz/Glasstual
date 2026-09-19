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
		fixture.session.isConnected = true
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

	private func checkSelectedCellStyle(in outline: SidebarOutlineView) throws {
		let row = try #require(outline.rowView(atRow: outline.selectedRow, makeIfNecessary: true))
		let cell = try #require(outline.view(atColumn: 0, row: outline.selectedRow, makeIfNecessary: true) as? SidebarCellView)
		let originalEmphasis = row.isEmphasized
		defer { row.isEmphasized = originalEmphasis }
		// The inactive hosted runner de-emphasizes source-list backing layers.
		// Verify native selection styling separately from the geometry capture;
		// forcing only the row's emphasis cannot simulate an active window.
		for emphasized in [true, false] {
			row.isEmphasized = emphasized
			let style: NSView.BackgroundStyle = emphasized ? .emphasized : .normal
			#expect(cell.backgroundStyle == style)
			#expect(cell.titleField.cell?.backgroundStyle == style)
			#expect(cell.leadingImage.cell?.backgroundStyle == style)
			#expect(cell.securityImage.cell?.backgroundStyle == style)
			let foreground = try #require(cell.titleField.attributedStringValue.attribute(
				.foregroundColor,
				at: 0,
				effectiveRange: nil
			) as? NSColor)
			let expected: NSColor = emphasized ? .alternateSelectedControlTextColor : .labelColor
			cell.effectiveAppearance.performAsCurrentDrawingAppearance {
				#expect(foreground.usingColorSpace(.deviceRGB) == expected.usingColorSpace(.deviceRGB))
				if emphasized {
					#expect(foreground.contrastRatio(against: .selectedContentBackgroundColor) > 3)
				}
			}
		}
	}
}
