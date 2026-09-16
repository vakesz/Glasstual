/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
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

// MARK: - Channel mode commands

extension MenuActionController {
	@objc func showChannelBanList(_: Any?) {
		showModeList(entryType: .ban, symbol: "+b")
	}

	@objc func showChannelBanExceptionList(_: Any?) {
		showModeList(entryType: .banException, symbol: "+e")
	}

	@objc func showChannelInviteExceptionList(_: Any?) {
		showModeList(entryType: .inviteException, symbol: "+I")
	}

	@objc func showChannelQuietList(_: Any?) {
		showModeList(entryType: .quiet, symbol: "+q")
	}

	/// One ticked item per mode, so the command says which way it is about to
	/// go. It used to be two items — "Moderated" and "Unmoderated" — neither of
	/// which showed which one was in force.
	@objc func toggleChannelModerationMode(_: Any?) {
		sendMode("m", set: channelModeIsSet("m") == false)
	}

	@objc func toggleChannelInviteMode(_: Any?) {
		sendMode("i", set: channelModeIsSet("i") == false)
	}

	/// Whether the selected channel is known to carry `symbol`.
	func channelModeIsSet(_ symbol: String) -> Bool {
		selectedChannel?.modeInfo?.modeInfo(for: symbol)?.modeIsSet == true
	}

	private func showModeList(entryType: ChannelBanListEntryType, symbol: String) {
		guard let client = selectedClient, let channel = selectedChannel,
		      client.isLoggedIn, channel.isChannel
		else { return }
		AppServices.scenes.openChannelBanList(entryType: entryType, in: channel)
		client.sendModes(symbol, withParametersString: nil, inChannelNamed: channel.name)
	}

	private func sendMode(_ symbol: String, set: Bool) {
		guard let client = selectedClient, let channel = selectedChannel,
		      client.isLoggedIn, channel.isChannel
		else { return }
		client.sendModes("\(set ? "+" : "-")\(symbol)", withParametersString: nil, inChannelNamed: channel.name)
	}
}
