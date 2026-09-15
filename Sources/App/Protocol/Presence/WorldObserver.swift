/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
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

import Foundation

/** What the world tells its observers about the shape of the connection tree.

 The world owns clients and channels; it does not own the outline view, the
 navigation menu or the selection. It publishes these events instead, and the
 window layer decides what to draw. Every requirement has a default no-op so an
 observer implements only the events it cares about. */
@MainActor
protocol WorldObserver: AnyObject {
	/// A run of add/remove events follows; observers may batch their redraws.
	func worldWillBeginBulkUpdate(_ world: World)
	func worldDidEndBulkUpdate(_ world: World)

	func world(_ world: World, didAddClient client: IRCClient, at index: Int)
	func world(_ world: World, didRemoveClient client: IRCClient)
	func world(_ world: World, didMoveClientFrom oldIndex: Int, to newIndex: Int)

	func world(_ world: World, didAddChannel channel: Channel, on client: IRCClient, at index: Int)
	func world(_ world: World, didRemoveChannel channel: Channel, on client: IRCClient)
	func world(
		_ world: World,
		didMoveChannelOn client: IRCClient,
		from oldIndex: Int,
		to newIndex: Int
	)

	func world(_ world: World, requestsSelectionOf item: TreeItem)
	func world(_ world: World, requestsDeselectionOf item: TreeItem)
	func world(_ world: World, requestsGroupDeselectionOf item: TreeItem)
	func worldRequestsSelectionAdjustment(_ world: World)

	/// The set of clients changed; anything keyed off "are there any clients"
	/// — the loading screen, for one — should refresh.
	func worldClientListDidChange(_ world: World)
	/// The flattened client/channel list a navigation menu is built from changed.
	func worldNavigationListDidChange(_ world: World)
	/// Preferences were applied; observers holding derived state should reload.
	func worldPreferencesDidChange(_ world: World)
}

extension WorldObserver {
	func worldWillBeginBulkUpdate(_: World) {}
	func worldDidEndBulkUpdate(_: World) {}
	func world(_: World, didAddClient _: IRCClient, at _: Int) {}
	func world(_: World, didRemoveClient _: IRCClient) {}
	func world(_: World, didMoveClientFrom _: Int, to _: Int) {}
	func world(_: World, didAddChannel _: Channel, on _: IRCClient, at _: Int) {}
	func world(_: World, didRemoveChannel _: Channel, on _: IRCClient) {}
	func world(_: World, didMoveChannelOn _: IRCClient, from _: Int, to _: Int) {}
	func world(_: World, requestsSelectionOf _: TreeItem) {}
	func world(_: World, requestsDeselectionOf _: TreeItem) {}
	func world(_: World, requestsGroupDeselectionOf _: TreeItem) {}
	func worldRequestsSelectionAdjustment(_: World) {}
	func worldClientListDidChange(_: World) {}
	func worldNavigationListDidChange(_: World) {}
	func worldPreferencesDidChange(_: World) {}
}

/** The observer list. Entries are weak: an observer is a window or a menu
 controller whose lifetime the world has no say in, and a dead entry is dropped
 once an event has been delivered past it.

 Delivery walks a snapshot rather than the list itself. An observer that
 registered another from inside an event was writing to the list while the
 delivery loop still held it for writing — an exclusivity violation — and the
 loop then put back the list it had started with, losing the registration. */
@MainActor
struct WorldObserverList {
	private struct Entry {
		weak var observer: (any WorldObserver)?
	}

	private var entries: [Entry] = []

	mutating func add(_ observer: any WorldObserver) {
		pruneReleased()
		guard entries.contains(where: { $0.observer === observer }) == false else { return }
		entries.append(Entry(observer: observer))
	}

	mutating func remove(_ observer: any WorldObserver) {
		entries.removeAll { $0.observer == nil || $0.observer === observer }
	}

	/// The observers still alive, in the order they registered.
	var liveObservers: [any WorldObserver] {
		entries.compactMap(\.observer)
	}

	/// Forgets the entries whose observer has gone.
	mutating func pruneReleased() {
		entries.removeAll { $0.observer == nil }
	}
}
