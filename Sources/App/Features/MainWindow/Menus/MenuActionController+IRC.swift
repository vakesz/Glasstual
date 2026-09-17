// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2020 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

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
