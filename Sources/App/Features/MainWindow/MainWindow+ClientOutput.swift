/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
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

// MARK: - Client output

/** The window-side work the IRC layer asks for. Most of it forwards to a method
 that already existed; the seam is what keeps the caller from knowing that. */
extension MainWindow: ClientOutput {
	func presentAlertSheet(_ request: AlertRequest, completion: @escaping AlertCompletion) {
		Alerts.alertSheet(request: request, completionBlock: completion)
	}

	func confirm(_ request: AlertRequest) async -> Bool {
		await Alerts.run(request, on: .mainWindow).response == .default
	}

	func closeSheets(for client: Client) {
		let clientIdentifier = client.uniqueIdentifier
		presentationModel.closeSheets { owner in
			guard let clientSheet = owner as? ClientScoped else { return false }

			return clientSheet.clientId == clientIdentifier
		}
		/* The access and highlight lists are windows rather than sheets now, so
		 the main window no longer takes them down with its own; a list of a
		 connection that is going away has nothing left to show. */
		let scenes = AppServices.scenes
		scenes.closeChannelBanList { $0.clientId == clientIdentifier }
		scenes.closeServerHighlightList(for: clientIdentifier)
	}

	func accessListEntryReceived(
		for client: Client,
		inChannelNamed channelName: String,
		modeSymbol: String,
		mask: String,
		setBy author: String?,
		creationDate date: Date?
	) -> Bool {
		guard let session = accessListSession(for: client, channelNamed: channelName, modeSymbol: modeSymbol) else {
			return false
		}

		session.receiveEntry(mask: mask, setBy: author, creationDate: date)

		return true
	}

	func accessListFinished(for client: Client, inChannelNamed channelName: String, modeSymbol: String) -> Bool {
		guard let session = accessListSession(for: client, channelNamed: channelName, modeSymbol: modeSymbol) else {
			return false
		}

		session.finishReceiving()

		return true
	}

	/// The open access list this reply belongs to, or `nil` when the reply is
	/// from another connection, for another channel, or for another of its lists.
	private func accessListSession(
		for client: Client,
		channelNamed channelName: String,
		modeSymbol: String
	) -> ChannelBanListSession? {
		guard let session = AppServices.scenes.currentChannelBanListSession(),
		      session.matches(client: client, channelName: channelName, modeSymbol: modeSymbol)
		else {
			return nil
		}

		return session
	}

	func closeSheets(forChannelId channelId: String) {
		presentationModel.closeSheets { owner in
			guard let channelSheet = owner as? ChannelScoped else { return false }
			return channelSheet.channelId == channelId
		}
		AppServices.scenes.closeChannelBanList { $0.channelId == channelId }
	}

	func highlightWasLogged(_ entry: HighlightLogEntry) {
		/* Only a window that is already open: nothing else is showing the list,
		 and building a session for every highlight logged would keep one per
		 connection alive for the life of the process. */
		guard let session = AppServices.scenes
			.visibleServerHighlightList(for: entry.clientId)
		else { return }

		session.addEntry(entry)
	}

	func reloadServerListItems(for _: Client) {
		guard let serverList else { return }

		ignoreServerListSelectionChanges = true
		serverList.beginUpdates()
		serverList.setNeedsRefresh()
		serverList.endUpdates()
		adjustSelection()
		ignoreServerListSelectionChanges = false
	}

	func refreshMessageCount(for _: ChatItem) {
		serverList?.setNeedsRefresh()
	}

	func assignMemberList(to channel: Channel) {
		memberList?.assign(to: channel)
	}

	func clearContents(of item: ChatItem) {
		if let channel = item as? Channel {
			clearContents(of: channel)
		} else if let client = item as? Client {
			clearContents(of: client)
		}
	}

	func destroyInputHistory(for item: ChatItem) {
		inputHistory.destroy(item)
	}

	func notifyAllViewsAppearanceDidChange() {
		for client in clientDirectory?.clientList ?? [] {
			transcriptControllers.existingController(for: client)?
				.reloadTheme()

			for channel in client.channelList {
				transcriptControllers.existingController(for: channel)?
					.reloadTheme()
			}
		}
	}
}
