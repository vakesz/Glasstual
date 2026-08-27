/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
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
import ObjectiveC

public typealias IRCTreeItem = TreeItem

private nonisolated(unsafe) var dockUnreadCountKey: UInt8 = 0
private nonisolated(unsafe) var nicknameHighlightCountKey: UInt8 = 0
private nonisolated(unsafe) var treeUnreadCountKey: UInt8 = 0
private nonisolated(unsafe) var associatedClientKey: UInt8 = 0
private nonisolated(unsafe) var viewControllerKey: UInt8 = 0

private final class WeakObjectBox: NSObject {
	weak var value: AnyObject?

	init(_ value: AnyObject?) {
		self.value = value
	}
}

@objc(IRCTreeItem)
open class TreeItem: NSObject {
	@objc open var isActive: Bool {
		false
	}

	@objc open var isClient: Bool {
		false
	}

	@objc open var isChannel: Bool {
		false
	}

	@objc open var isPrivateMessage: Bool {
		false
	}

	@objc open var associatedChannel: IRCChannel? {
		nil
	}

	@objc open var label: String {
		""
	}

	@objc open var name: String {
		""
	}

	@objc open var uniqueIdentifier: String {
		""
	}

	@objc open var numberOfChildren: Int {
		0
	}

	@objc public var dockUnreadCount: Int {
		get { integer(forKey: &dockUnreadCountKey) }
		set { setInteger(newValue, forKey: &dockUnreadCountKey) }
	}

	@objc public dynamic var nicknameHighlightCount: Int {
		get { integer(forKey: &nicknameHighlightCountKey) }
		set { setInteger(newValue, forKey: &nicknameHighlightCountKey) }
	}

	@objc public dynamic var treeUnreadCount: Int {
		get { integer(forKey: &treeUnreadCountKey) }
		set { setInteger(newValue, forKey: &treeUnreadCountKey) }
	}

	@objc open var associatedClient: IRCClient! {
		get { (objc_getAssociatedObject(self, &associatedClientKey) as? WeakObjectBox)?.value as? IRCClient }
		set {
			objc_setAssociatedObject(
				self,
				&associatedClientKey,
				WeakObjectBox(newValue),
				.OBJC_ASSOCIATION_RETAIN_NONATOMIC
			)
		}
	}

	@objc public var viewController: LogController! {
		get { objc_getAssociatedObject(self, &viewControllerKey) as? LogController }
		set { objc_setAssociatedObject(self, &viewControllerKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
	}

	@objc public var isUnread: Bool {
		integer(forKey: &treeUnreadCountKey) > 0
	}

	@objc public func resetState() {
		setInteger(0, forKey: &dockUnreadCountKey)
		setInteger(0, forKey: &nicknameHighlightCountKey)
		setInteger(0, forKey: &treeUnreadCountKey)
	}

	@objc(childAtIndex:) open func child(at _: Int) -> TreeItem? {
		nil
	}

	private func integer(forKey key: UnsafeRawPointer) -> Int {
		(objc_getAssociatedObject(self, key) as? NSNumber)?.intValue ?? 0
	}

	private func setInteger(_ value: Int, forKey key: UnsafeRawPointer) {
		objc_setAssociatedObject(self, key, NSNumber(value: value), .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
	}
}
