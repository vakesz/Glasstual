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
protocol ClientDirectoryObserver: AnyObject {
	/// A run of add/remove events follows; observers may batch their redraws.
	func worldWillBeginBulkUpdate(_ world: ClientDirectory)
	func worldDidEndBulkUpdate(_ world: ClientDirectory)

	func world(_ world: ClientDirectory, didAddClient client: Client, at index: Int)
	func world(_ world: ClientDirectory, didRemoveClient client: Client)
	func world(_ world: ClientDirectory, didMoveClientFrom oldIndex: Int, to newIndex: Int)

	func world(_ world: ClientDirectory, didAddChannel channel: Channel, on client: Client, at index: Int)
	func world(_ world: ClientDirectory, didRemoveChannel channel: Channel, on client: Client)
	func world(
		_ world: ClientDirectory,
		didMoveChannelOn client: Client,
		from oldIndex: Int,
		to newIndex: Int
	)

	func world(_ world: ClientDirectory, requestsSelectionOf item: ChatItem)
	func world(_ world: ClientDirectory, requestsDeselectionOf item: ChatItem)
	func world(_ world: ClientDirectory, requestsGroupDeselectionOf item: ChatItem)
	func worldRequestsSelectionAdjustment(_ world: ClientDirectory)

	/// The set of clients changed; anything keyed off "are there any clients"
	/// — the loading screen, for one — should refresh.
	func worldClientListDidChange(_ world: ClientDirectory)
	/// The flattened client/channel list a navigation menu is built from changed.
	func worldNavigationListDidChange(_ world: ClientDirectory)
	/// Preferences were applied; observers holding derived state should reload.
	func worldPreferencesDidChange(_ world: ClientDirectory)
}

extension ClientDirectoryObserver {
	func worldWillBeginBulkUpdate(_: ClientDirectory) {}
	func worldDidEndBulkUpdate(_: ClientDirectory) {}
	func world(_: ClientDirectory, didAddClient _: Client, at _: Int) {}
	func world(_: ClientDirectory, didRemoveClient _: Client) {}
	func world(_: ClientDirectory, didMoveClientFrom _: Int, to _: Int) {}
	func world(_: ClientDirectory, didAddChannel _: Channel, on _: Client, at _: Int) {}
	func world(_: ClientDirectory, didRemoveChannel _: Channel, on _: Client) {}
	func world(_: ClientDirectory, didMoveChannelOn _: Client, from _: Int, to _: Int) {}
	func world(_: ClientDirectory, requestsSelectionOf _: ChatItem) {}
	func world(_: ClientDirectory, requestsDeselectionOf _: ChatItem) {}
	func world(_: ClientDirectory, requestsGroupDeselectionOf _: ChatItem) {}
	func worldRequestsSelectionAdjustment(_: ClientDirectory) {}
	func worldClientListDidChange(_: ClientDirectory) {}
	func worldNavigationListDidChange(_: ClientDirectory) {}
	func worldPreferencesDidChange(_: ClientDirectory) {}
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
