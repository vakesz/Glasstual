// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit

/** The window's transcript controllers, keyed by the identifier of the chat item each
 one draws.

 The controllers used to hang off the model objects, which meant the IRC layer
 both built a web view and owned it for the rest of its life. They belong to the
 window that shows them, so the window keeps them here and the tree item holds
 only a weak `presentation` back-reference the registry installs. */
@MainActor
final class TranscriptControllerRegistry {
	private unowned let window: MainWindow
	private var controllers: [String: TranscriptController] = [:]

	init(window: MainWindow) {
		self.window = window
	}

	var allControllers: [TranscriptController] {
		Array(controllers.values)
	}

	var count: Int {
		controllers.count
	}

	/// The controller drawing `item`, made on first use.
	@discardableResult
	func controller(for item: ChatItem) -> TranscriptController {
		if let existing = controllers[item.uniqueIdentifier] {
			return existing
		}

		let controller = if let channel = item as? Channel {
			TranscriptController(channel: channel, in: window)
		} else if let client = item as? Client {
			TranscriptController(client: client, in: window)
		} else {
			TranscriptController(client: item.associatedClient, in: window)
		}

		controllers[item.uniqueIdentifier] = controller
		item.presentation = controller
		return controller
	}

	/// The controller drawing `item` if one has already been made.
	func existingController(for item: ChatItem) -> TranscriptController? {
		controllers[item.uniqueIdentifier]
	}

	func controller(withIdentifier identifier: String) -> TranscriptController? {
		controllers[identifier]
	}

	/// Makes the controllers for a client and every channel it already has.
	func registerTree(of client: Client) {
		controller(for: client)

		for channel in client.channelList {
			controller(for: channel)
		}
	}

	/// Forgets the controller for `item`. The caller has already told the
	/// controller to tear itself down.
	func forget(_ item: ChatItem) {
		if item.presentation === controllers[item.uniqueIdentifier] {
			item.presentation = nil
		}

		controllers.removeValue(forKey: item.uniqueIdentifier)
	}

	/// Forgets a client and every channel it has.
	func forgetTree(of client: Client) {
		for channel in client.channelList {
			forget(channel)
		}

		forget(client)
	}

	func forgetAll() {
		controllers.removeAll()
	}
}

extension ChatItem {
	/** The view this item is drawn into, if a window has made one.

	 This reads the weak seam the registry installed rather than a property the
	 item owns, so it is `nil` for an item no window is showing — a client in a
	 test, or one whose registry entry has already been dropped. */
	var transcriptController: TranscriptController? {
		presentation as? TranscriptController
	}
}
