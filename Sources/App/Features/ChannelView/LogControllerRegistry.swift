/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
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

import AppKit

/** The window's log controllers, keyed by the identifier of the tree item each
 one draws.

 The controllers used to hang off the model objects, which meant the IRC layer
 both built a web view and owned it for the rest of its life. They belong to the
 window that shows them, so the window keeps them here and the tree item holds
 only a weak `presentation` back-reference the registry installs. */
@MainActor
public final class LogControllerRegistry {
	private unowned let window: MainWindow
	private var controllers: [String: LogController] = [:]

	public init(window: MainWindow) {
		self.window = window
	}

	public var allControllers: [LogController] {
		Array(controllers.values)
	}

	public var count: Int {
		controllers.count
	}

	/// The controller drawing `item`, made on first use.
	@discardableResult
	public func controller(for item: IRCTreeItem) -> LogController {
		if let existing = controllers[item.uniqueIdentifier] {
			return existing
		}

		let controller = if let channel = item as? IRCChannel {
			LogController(channel: channel, in: window)
		} else if let client = item as? IRCClient {
			LogController(client: client, in: window)
		} else {
			LogController(client: item.associatedClient, in: window)
		}

		controllers[item.uniqueIdentifier] = controller
		item.presentation = controller
		return controller
	}

	/// The controller drawing `item` if one has already been made.
	public func existingController(for item: IRCTreeItem) -> LogController? {
		controllers[item.uniqueIdentifier]
	}

	public func controller(withIdentifier identifier: String) -> LogController? {
		controllers[identifier]
	}

	/// Makes the controllers for a client and every channel it already has.
	public func registerTree(of client: IRCClient) {
		controller(for: client)

		for channel in client.channelList {
			controller(for: channel)
		}
	}

	/// Forgets the controller for `item`. The caller has already told the
	/// controller to tear itself down.
	public func forget(_ item: IRCTreeItem) {
		if item.presentation === controllers[item.uniqueIdentifier] {
			item.presentation = nil
		}

		controllers.removeValue(forKey: item.uniqueIdentifier)
	}

	/// Forgets a client and every channel it has.
	public func forgetTree(of client: IRCClient) {
		for channel in client.channelList {
			forget(channel)
		}

		forget(client)
	}

	public func forgetAll() {
		controllers.removeAll()
	}
}
