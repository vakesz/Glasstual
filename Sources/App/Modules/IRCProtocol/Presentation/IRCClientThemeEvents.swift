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

import Foundation

private enum ThemeEventMainActorBridge {
	static func sync(_ operation: @escaping @MainActor @Sendable () -> Void) {
		if Thread.isMainThread {
			MainActor.assumeIsolated(operation)
		} else {
			DispatchQueue.main.sync {
				MainActor.assumeIsolated(operation)
			}
		}
	}
}

/// The caller stays blocked during this handoff, and the item is dereferenced
/// only by the main-actor operation.
private struct ThemeEventItemReference: @unchecked Sendable {
	let value: AnyObject
}

public extension IRCClient {
	@objc(postEventToViewController:)
	func postEvent(toViewController eventToken: String) {
		ThemeEventMainActorBridge.sync { [self, eventToken] in
			guard themePostsHandleEventNotifications else { return }
			postThemeEvent(eventToken, to: self)
			for channel in channelList {
				postThemeEvent(eventToken, to: channel)
			}
		}
	}

	@objc(postEventToViewController:forChannel:)
	func postEvent(toViewController eventToken: String, for channel: IRCChannel) {
		ThemeEventMainActorBridge.sync { [self, eventToken, channel] in
			guard themePostsHandleEventNotifications else { return }
			postThemeEvent(eventToken, to: channel)
		}
	}

	@objc(postEventToViewController:forItem:)
	func postEvent(toViewController eventToken: String, forItem item: AnyObject) {
		let itemReference = ThemeEventItemReference(value: item)
		ThemeEventMainActorBridge.sync { [self, eventToken, itemReference] in
			postThemeEvent(eventToken, to: itemReference.value)
		}
	}

	@MainActor
	private var themePostsHandleEventNotifications: Bool {
		SharedApplication.sharedThemeController().settings.postsHandleEventNotifications
	}

	@MainActor
	private func postThemeEvent(_ eventToken: String, to item: AnyObject) {
		guard !isTerminating else { return }
		let viewController: LogController? = if let channel = item as? IRCChannel {
			channel.viewController
		} else if let treeItem = item as? IRCTreeItem {
			(treeItem.viewController as AnyObject?) as? LogController
		} else {
			nil
		}
		viewController?.evaluateFunction("Glasstual.handleEvent", withArguments: [eventToken], onQueue: false)
	}
}
