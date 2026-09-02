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
import CocoaExtensions
@testable import Glasstual
import Synchronization
import Testing

/// The Objective-C names something outside the compiler depends on. Interface
/// Builder resources are gone, so the only entries left here are the ones that
/// survive for an external reason: an archive on disk, a saved window frame,
/// KVO, and the mIRC palette, whose indices are wire format rather than a
/// design choice.
///
/// Nothing else belongs here. A test that asserts a type conforms to a protocol,
/// responds to a selector it declares, or has the raw value written next to its
/// declaration restates the compiler and fails on every rename.
@Suite("Objective-C runtime names")
@MainActor
struct ObjCRuntimeNameTests {
	/// `NSKeyedArchiver` writes the class name into every blob in the historic
	/// log store, so an installation that upgrades has to keep reading the name
	/// its existing rows were written with.
	@Test("The archived log line keeps the runtime name its blobs were written with")
	func archivedLogLineKeepsItsRuntimeName() {
		#expect(NSStringFromClass(LogLineArchive.self) == "TVCLogLine")
	}

	/// `publisher(for:)` resolves a key path through key-value observing, which
	/// needs the property visible to the Objective-C runtime: a key path to a
	/// property without `@objc` has no KVC string and the observation traps the
	/// first time the view sets it up. Nothing in the compiler checks that, so
	/// the key paths the application observes are pinned here.
	@Test("The key paths the application observes resolve through key-value coding")
	func observedKeyPathsResolve() {
		let observed: [(String, AnyKeyPath)] = [
			("IRCClient.isLoggedIn", \IRCClient.isLoggedIn),
			("IRCTreeItem.nicknameHighlightCount", \IRCTreeItem.nicknameHighlightCount),
			("IRCTreeItem.treeUnreadCount", \IRCTreeItem.treeUnreadCount),
		]

		for (name, keyPath) in observed {
			#expect(keyPath._kvcKeyPathString != nil, "\(name) is no longer observable")
		}
	}

	/// Visible to the runtime is only half of it: an observed property also has
	/// to be dynamically dispatched, or the setter never posts a change and the
	/// observation goes quiet without failing anywhere.
	@Test("An observed property still posts its changes")
	func observedPropertyPostsChanges() {
		let item = IRCTreeItem()

		let received = Mutex<[Int]>([])
		let observation = item.observe(\.treeUnreadCount, options: [.new]) { _, change in
			received.withLock { $0.append(change.newValue ?? -1) }
		}
		defer { observation.invalidate() }

		item.treeUnreadCount = 7

		#expect(received.withLock { $0 } == [7])
	}

	/// mIRC colour codes index this table, so the order is protocol, not
	/// presentation: colour 0 is white and colour 1 is black on every network.
	@Test("The mIRC palette keeps its 99 entries in wire order")
	func formatterPaletteIsPinned() {
		#expect(NSColor.formatterColors.count == 99)
		#expect(NSColor.formatterWhiteColor == NSColor.formatterColors[0])
		#expect(NSColor.formatterBlackColor == NSColor.formatterColors[1])
		#expect(NSColor.formatterLightGrayColor == NSColor.formatterColors[15])
	}
}
