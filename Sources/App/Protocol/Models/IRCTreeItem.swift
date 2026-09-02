/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
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

public typealias IRCTreeItem = TreeItem

open class TreeItem: NSObject {
	open var isActive: Bool {
		false
	}

	open var isClient: Bool {
		false
	}

	open var isChannel: Bool {
		false
	}

	open var isPrivateMessage: Bool {
		false
	}

	open var associatedChannel: IRCChannel? {
		nil
	}

	open var label: String {
		""
	}

	open var name: String {
		""
	}

	open var uniqueIdentifier: String {
		""
	}

	open var numberOfChildren: Int {
		0
	}

	public var dockUnreadCount = 0
	/* KVO: the server list and the channel spotlight table redraw one row from
	 `publisher(for:)` on these two, so both stay visible to key-value
	 observing. */
	@objc public dynamic var nicknameHighlightCount = 0
	@objc public dynamic var treeUnreadCount = 0

	/** Weak: the world owns its clients, and an item routinely outlives the
	 client that made it while teardown finishes. */
	open weak var associatedClient: IRCClient! {
		didSet { associatedClientDidChange() }
	}

	/** Weak: the window's log controller registry owns the view this item is
	 drawn into and installs itself here. An item with no window — a client
	 built by a test, an item being torn down — simply has none. */
	weak var presentation: (any TreeItemPresentation)?

	/// The preference snapshot of the client this item belongs to. An item whose
	/// client has already gone reads the declared defaults rather than the store.
	var clientPreferences: ClientPreferences {
		associatedClient?.environment.preferences ?? ClientPreferences()
	}

	public var isUnread: Bool {
		treeUnreadCount > 0
	}

	/// Clears the counts and redraws the badge that showed them. `setUnreadState`
	/// asks for the redraw when it raises a count, so the reset does the same
	/// rather than leaving a stale badge until something else redraws the row.
	public func resetState() {
		dockUnreadCount = 0
		nicknameHighlightCount = 0
		treeUnreadCount = 0
		associatedClient?.output?.refreshMessageCount(for: self)
	}

	open func child(at _: Int) -> TreeItem? {
		nil
	}

	/// Overridden by items whose `description` names the client they belong to.
	func associatedClientDidChange() {}
}
