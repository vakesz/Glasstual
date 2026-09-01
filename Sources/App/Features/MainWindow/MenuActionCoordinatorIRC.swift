/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2020 Codeux Software, LLC & respective contributors.
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

enum MenuChannelModePolicy {
	static let removeModeratedTag = 6_090_001
	static let removeInviteOnlyTag = 6_090_003

	static func moderationMode(for tag: Int) -> String {
		tag == removeModeratedTag ? "-m" : "+m"
	}

	static func inviteMode(for tag: Int) -> String {
		tag == removeInviteOnlyTag ? "-i" : "+i"
	}
}

@MainActor
public extension MenuActionCoordinator {
	func performIRCAction(_ action: MenuIRCAction, sender: Any?) {
		switch action {
		case .showBanList: showModeList(symbol: "+b", presentation: { $0.createChannelBanListSheet() })
		case .showBanExceptionList:
			showModeList(symbol: "+e", presentation: { $0.createChannelBanExceptionListSheet() })
		case .showInviteExceptionList:
			showModeList(symbol: "+I", presentation: { $0.createChannelInviteExceptionListSheet() })
		case .showQuietList: showModeList(symbol: "+q", presentation: { $0.createChannelQuietListSheet() })
		case .toggleModerationMode:
			sendMode(MenuChannelModePolicy.moderationMode(for: senderTag(sender)))
		case .toggleInviteMode:
			sendMode(MenuChannelModePolicy.inviteMode(for: senderTag(sender)))
		@unknown default: break
		}
	}

	private func showModeList(symbol: String, presentation: (IRCClient) -> Void) {
		guard let client = selectedClient, let channel = selectedChannel,
		      client.isLoggedIn, channel.isChannel
		else { return }
		presentation(client)
		client.sendModes(symbol, withParametersString: nil, in: channel)
	}

	private func sendMode(_ symbol: String) {
		guard let client = selectedClient, let channel = selectedChannel,
		      client.isLoggedIn, channel.isChannel
		else { return }
		client.sendModes(symbol, withParametersString: nil, in: channel)
	}

	private func senderTag(_ sender: Any?) -> Int {
		(sender as? NSMenuItem)?.command?.rawValue ?? (sender as? NSControl)?.tag ?? 0
	}
}
