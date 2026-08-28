/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\\_\\__|\\__,_|\\__,_|_|
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
import SwiftUI

@objc(TDCChannelInviteSheetDelegate)
@MainActor
public protocol ChannelInviteSheetDelegate: NSObjectProtocol {
	@objc(channelInviteSheet:onSelectChannel:)
	func channelInviteSheet(_ sender: ChannelInviteSheet, onSelectChannel channelName: String)

	@objc(channelInviteSheetWillClose:)
	func channelInviteSheetWillClose(_ sender: ChannelInviteSheet)
}

@objc(TDCChannelInviteSheet)
@MainActor
public final class ChannelInviteSheet: SheetBase, NSWindowDelegate, TDCClientPrototype {
	private static let contentWidth: CGFloat = 340

	@objc public private(set) var client: IRCClient?
	@objc public private(set) var clientId: String?
	@objc public private(set) var nicknames: [String] = []

	private var availableChannels: [String] = []
	private var selectedChannel = ""

	@objc(initWithNicknames:onClient:)
	public init(nicknames: [String], on client: IRCClient) {
		super.init(window: nil)
		self.nicknames = nicknames
		self.client = client
		clientId = client.uniqueIdentifier
	}

	@objc(startWithChannels:)
	public func start(withChannels channels: [String]) {
		guard channels.isEmpty == false else {
			return
		}

		availableChannels = channels
		selectedChannel = channels[0]
		installSheet(content: ChannelInviteContent(nicknames: nicknames, channels: channels))
		startSheet()
	}

	private func installSheet(content: ChannelInviteContent) {
		let rootView = ChannelInviteView(
			content: content,
			selectedChannel: Binding(
				get: { [weak self] in self?.selectedChannel ?? "" },
				set: { [weak self] in self?.selectedChannel = $0 }
			),
			invite: { [weak self] channel in
				self?.completeInvitation(to: channel)
			},
			cancel: { [weak self] in
				self?.cancel(nil)
			}
		)
		let hostingController = NSHostingController(rootView: rootView)
		let hostedSheet = NSWindow(
			contentRect: NSRect(x: 0, y: 0, width: Self.contentWidth, height: 150),
			styleMask: [.titled, .fullSizeContentView],
			backing: .buffered,
			defer: false
		)

		hostedSheet.contentViewController = hostingController
		hostedSheet.contentMinSize = NSSize(width: Self.contentWidth, height: 130)
		hostedSheet.contentMaxSize = NSSize(width: Self.contentWidth, height: 220)
		hostedSheet.delegate = self
		hostedSheet.isReleasedWhenClosed = false
		hostedSheet.isRestorable = false
		hostedSheet.tabbingMode = .disallowed
		hostedSheet.title = content.windowTitle
		hostedSheet.titleVisibility = .hidden
		hostedSheet.titlebarAppearsTransparent = true
		hostedSheet.titlebarSeparatorStyle = .none
		sheet = hostedSheet
	}

	@IBAction override public func ok(_: Any?) {
		guard availableChannels.contains(selectedChannel) else {
			cancel(nil)
			return
		}

		completeInvitation(to: selectedChannel)
	}

	private func completeInvitation(to channel: String) {
		(delegate as? ChannelInviteSheetDelegate)?.channelInviteSheet(self, onSelectChannel: channel)

		super.ok(nil)
	}

	@objc public func windowWillClose(_: Notification) {
		(delegate as? ChannelInviteSheetDelegate)?.channelInviteSheetWillClose(self)
	}
}
