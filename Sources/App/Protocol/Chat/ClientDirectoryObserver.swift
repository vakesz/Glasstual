// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** What the world tells its observers about the shape of the connection tree.

 The world owns clients and channels; it does not own the outline view, the
 navigation menu or the selection. It publishes these events instead, and the
 window layer decides what to draw. Every requirement has a default no-op so an
 observer implements only the events it cares about. */
@MainActor
protocol ClientDirectoryObserver: AnyObject {
	/// A run of add/remove events follows; observers may batch their redraws.
	func clientDirectoryWillBeginBulkUpdate(_ world: ClientDirectory)
	func clientDirectoryDidEndBulkUpdate(_ world: ClientDirectory)

	func clientDirectory(_ directory: ClientDirectory, didAddClient client: Client, at index: Int)
	func clientDirectory(_ directory: ClientDirectory, didRemoveClient client: Client)
	func clientDirectory(_ directory: ClientDirectory, didMoveClientFrom oldIndex: Int, to newIndex: Int)

	func clientDirectory(_ directory: ClientDirectory, didAddChannel channel: Channel, on client: Client, at index: Int)
	func clientDirectory(_ directory: ClientDirectory, didRemoveChannel channel: Channel, on client: Client)
	func clientDirectory(
		_ directory: ClientDirectory,
		didMoveChannelOn client: Client,
		from oldIndex: Int,
		to newIndex: Int
	)

	func clientDirectory(_ directory: ClientDirectory, requestsSelectionOf item: ChatItem)
	func clientDirectory(_ directory: ClientDirectory, requestsDeselectionOf item: ChatItem)
	func clientDirectory(_ directory: ClientDirectory, requestsGroupDeselectionOf item: ChatItem)
	func clientDirectoryRequestsSelectionAdjustment(_ world: ClientDirectory)

	/// The set of clients changed; anything keyed off "are there any clients"
	/// — the loading screen, for one — should refresh.
	func clientDirectoryClientListDidChange(_ world: ClientDirectory)
	/// The flattened client/channel list a navigation menu is built from changed.
	func clientDirectoryNavigationListDidChange(_ world: ClientDirectory)
	/// Preferences were applied; observers holding derived state should reload.
	func clientDirectoryPreferencesDidChange(_ world: ClientDirectory)
}

extension ClientDirectoryObserver {
	func clientDirectoryWillBeginBulkUpdate(_: ClientDirectory) {}
	func clientDirectoryDidEndBulkUpdate(_: ClientDirectory) {}
	func clientDirectory(_: ClientDirectory, didAddClient _: Client, at _: Int) {}
	func clientDirectory(_: ClientDirectory, didRemoveClient _: Client) {}
	func clientDirectory(_: ClientDirectory, didMoveClientFrom _: Int, to _: Int) {}
	func clientDirectory(_: ClientDirectory, didAddChannel _: Channel, on _: Client, at _: Int) {}
	func clientDirectory(_: ClientDirectory, didRemoveChannel _: Channel, on _: Client) {}
	func clientDirectory(_: ClientDirectory, didMoveChannelOn _: Client, from _: Int, to _: Int) {}
	func clientDirectory(_: ClientDirectory, requestsSelectionOf _: ChatItem) {}
	func clientDirectory(_: ClientDirectory, requestsDeselectionOf _: ChatItem) {}
	func clientDirectory(_: ClientDirectory, requestsGroupDeselectionOf _: ChatItem) {}
	func clientDirectoryRequestsSelectionAdjustment(_: ClientDirectory) {}
	func clientDirectoryClientListDidChange(_: ClientDirectory) {}
	func clientDirectoryNavigationListDidChange(_: ClientDirectory) {}
	func clientDirectoryPreferencesDidChange(_: ClientDirectory) {}
}

/** The observer list. Entries are weak: an observer is a window or a menu
 controller whose lifetime the world has no say in, and a dead entry is dropped
 once an event has been delivered past it.

 Delivery walks a snapshot rather than the list itself. An observer that
 registered another from inside an event was writing to the list while the
 delivery loop still held it for writing — an exclusivity violation — and the
 loop then put back the list it had started with, losing the registration. */
@MainActor
struct ClientDirectoryObserverList {
	private struct Entry {
		weak var observer: (any ClientDirectoryObserver)?
	}

	private var entries: [Entry] = []

	mutating func add(_ observer: any ClientDirectoryObserver) {
		pruneReleased()
		guard entries.contains(where: { $0.observer === observer }) == false else { return }
		entries.append(Entry(observer: observer))
	}

	mutating func remove(_ observer: any ClientDirectoryObserver) {
		entries.removeAll { $0.observer == nil || $0.observer === observer }
	}

	/// The observers still alive, in the order they registered.
	var liveObservers: [any ClientDirectoryObserver] {
		entries.compactMap(\.observer)
	}

	/// Forgets the entries whose observer has gone.
	mutating func pruneReleased() {
		entries.removeAll { $0.observer == nil }
	}
}
