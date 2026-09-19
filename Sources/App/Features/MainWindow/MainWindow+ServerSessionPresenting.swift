// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit

// MARK: - ServerSession output

/** The window-side work the IRC layer asks for. Most of it forwards to a method
 that already existed; the seam is what keeps the caller from knowing that. */
extension MainWindow: ServerSessionPresenting {
	func presentAlertSheet(_ request: AlertRequest, completion: @escaping AlertCompletion) {
		Alerts.alertSheet(request: request, completion: completion)
	}

	func confirm(_ request: AlertRequest) async -> Bool {
		await Alerts.run(request, on: .mainWindow).response == .default
	}

	func closeSheets(for session: ServerSession) {
		let sessionIdentifier = session.uniqueIdentifier
		sheetModel.closeSheets { owner in
			guard let sessionSheet = owner as? SessionScoped else { return false }

			return sessionSheet.sessionId == sessionIdentifier
		}
		/* The access list and the highlight log are windows rather than sheets
		 now, so the main window no longer takes them down with its own; a window
		 about a connection that is going away has nothing left to show. */
		AppServices.channelMaskList.close { $0.sessionId == sessionIdentifier }
		AppServices.highlightLogs.close(for: sessionIdentifier)
	}

	func maskListEntryReceived(
		for session: ServerSession,
		inChannelNamed channelName: String,
		modeSymbol: String,
		mask: String,
		setBy author: String?,
		creationDate date: Date?
	) -> Bool {
		guard let list = maskList(for: session, channelNamed: channelName, modeSymbol: modeSymbol) else {
			return false
		}

		list.receiveEntry(mask: mask, setBy: author, creationDate: date)

		return true
	}

	func maskListFinished(for session: ServerSession, inChannelNamed channelName: String, modeSymbol: String) -> Bool {
		guard let list = maskList(for: session, channelNamed: channelName, modeSymbol: modeSymbol) else {
			return false
		}

		list.finishReceiving()

		return true
	}

	/// The open mask list this reply belongs to, or `nil` when the reply is
	/// from another connection, for another channel, or for another of its lists.
	private func maskList(
		for session: ServerSession,
		channelNamed channelName: String,
		modeSymbol: String
	) -> ChannelMaskListSession? {
		guard let list = AppServices.channelMaskList.current,
		      list.matches(session: session, channelName: channelName, modeSymbol: modeSymbol)
		else {
			return nil
		}

		return list
	}

	func closeSheets(forConversationId conversationId: String) {
		sheetModel.closeSheets { owner in
			guard let channelSheet = owner as? ChannelScoped else { return false }
			return channelSheet.channelId == conversationId
		}
		AppServices.channelMaskList.close { $0.channelId == conversationId }
	}

	func highlightWasLogged(_ entry: HighlightRecord) {
		/* Only a window that is already open: nothing else is showing the log,
		 and building one for every highlight logged would keep a window's worth
		 of state per connection alive for the life of the process. */
		guard let log = AppServices.highlightLogs.visible(for: entry.sessionId) else { return }

		log.addEntry(entry)
	}

	func reloadSidebarItems(for _: ServerSession) {
		guard let sidebar else { return }

		ignoreSidebarSelectionChanges = true
		sidebar.beginUpdates()
		sidebar.setNeedsRefresh()
		sidebar.endUpdates()
		adjustSelection()
		ignoreSidebarSelectionChanges = false
	}

	func refreshMessageCount(for _: ChatItem) {
		sidebar?.setNeedsRefresh()
	}

	/// The conversation a reply belongs in when the connection has nowhere
	/// better to print it: the one the reader is looking at, and only while
	/// that is on this connection.
	func selectedConversation(on session: ServerSession) -> Conversation? {
		selectedSession === session ? selectedConversation : nil
	}

	func updateDrawingForUserInUserList(_ user: User) {
		guard selectedConversation?.findMember(user.nickname) != nil else { return }
		memberList.invalidatePresentation()
	}

	func assignMemberList(to conversation: Conversation) {
		memberList?.assign(to: conversation)
	}

	func clearContents(of item: ChatItem) {
		if let conversation = item as? Conversation {
			clearContents(of: conversation)
		} else if let session = item as? ServerSession {
			clearContents(of: session)
		}
	}

	func destroyInputHistory(for item: ChatItem) {
		inputHistory.destroy(item)
	}

	func notifyAllViewsAppearanceDidChange() {
		for session in chatSession?.sessions ?? [] {
			transcriptControllers.existingController(for: session)?
				.reloadTheme()

			for conversation in session.conversationList {
				transcriptControllers.existingController(for: conversation)?
					.reloadTheme()
			}
		}
	}
}
