/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_
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

@MainActor
extension IRCClient: ChannelBanListSheetDelegate, ServerChannelListDialogDelegate {
	private var clientDialogWindowKey: String {
		"TDCServerChannelListDialog -> \(uniqueIdentifier)"
	}

	@objc func createChannelInviteExceptionListSheet() {
		createChannelBanListSheet(entryType: .inviteException)
	}

	@objc func createChannelBanExceptionListSheet() {
		createChannelBanListSheet(entryType: .banException)
	}

	@objc func createChannelBanListSheet() {
		createChannelBanListSheet(entryType: .ban)
	}

	@objc func createChannelQuietListSheet() {
		createChannelBanListSheet(entryType: .quiet)
	}

	@objc(createChannelBanListSheet:)
	func createChannelBanListSheet(entryType: ChannelBanListEntryType) {
		let windowController = SharedApplication.sharedWindowController()
		windowController.popMainWindowSheetIfExists()

		guard let mainWindow = AppController.shared.mainWindow,
		      let channel = mainWindow.selectedChannel,
		      let sheet = ChannelBanListSheet(entryType: entryType, inChannel: channel)
		else { return }

		sheet.delegate = self
		sheet.window = mainWindow
		sheet.start()
		windowController.addWindow(toWindowList: sheet)
	}

	public func channelBanListSheetOnUpdate(_ sender: ChannelBanListSheet) {
		guard let channel = sender.channel else { return }
		sendModes("+\(sender.modeSymbol)", withParametersString: nil, in: channel)
	}

	public func channelBanListSheetWillClose(_ sender: ChannelBanListSheet) {
		guard let channel = sender.channel else { return }

		for change in sender.listOfChanges ?? [] {
			sendModes(change, withParametersString: nil, in: channel)
		}

		SharedApplication.sharedWindowController().removeWindow(fromWindowList: sender)
	}

	@objc func channelListDialogWindowKey() -> String {
		clientDialogWindowKey
	}

	@objc func channelListDialog() -> ServerChannelListDialog? {
		SharedApplication.sharedWindowController().window(fromWindowList: clientDialogWindowKey)
			as? ServerChannelListDialog
	}

	@objc func createChannelListDialog() {
		let windowController = SharedApplication.sharedWindowController()
		guard windowController.maybeBringWindowForward(clientDialogWindowKey) == false else { return }

		let dialog = ServerChannelListDialog(client: self)
		dialog.delegate = self
		dialog.show()
		windowController.addWindow(toWindowList: dialog, withDescription: clientDialogWindowKey)
	}

	public func serverChannelListDialogOnUpdate(_ sender: ServerChannelListDialog) {
		requestChannelList(withArguments: sender.serverSideListArguments)
	}

	public func serverChannelListDialog(_: ServerChannelListDialog, joinChannels channels: [String]) {
		joinUnlistedChannelsAndSelectBestMatch(channels)
	}

	public func serverChannelDialogWillClose(_: ServerChannelListDialog) {
		SharedApplication.sharedWindowController().removeWindow(fromWindowList: clientDialogWindowKey)
	}
}
