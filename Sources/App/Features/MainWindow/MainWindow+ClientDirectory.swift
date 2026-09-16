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

// MARK: - ClientDirectory observer

/** The window draws what the client directory publishes. Nothing here reaches
 back into the IRC layer; every entry point is an event the directory posted. */
extension MainWindow: ClientDirectoryObserver {
	func clientDirectoryWillBeginBulkUpdate(_: ClientDirectory) {
		serverList?.beginUpdates()
	}

	func clientDirectoryDidEndBulkUpdate(_: ClientDirectory) {
		serverList?.endUpdates()
	}

	func clientDirectory(_: ClientDirectory, didAddClient client: Client, at _: Int) {
		/* The views have to exist before the row that shows them does. */
		transcriptControllers.registerTree(of: client)
		serverList?.setNeedsRefresh()
	}

	func clientDirectory(_: ClientDirectory, didRemoveClient client: Client) {
		serverList?.itemWasRemoved(client)
		transcriptControllers.forgetTree(of: client)
	}

	func clientDirectory(_: ClientDirectory, didMoveClientFrom _: Int, to _: Int) {
		serverList?.setNeedsRefresh()
	}

	func clientDirectory(_: ClientDirectory, didAddChannel channel: Channel, on _: Client, at _: Int) {
		transcriptControllers.controller(for: channel)
		serverList?.setNeedsRefresh()
	}

	func clientDirectory(_: ClientDirectory, didRemoveChannel channel: Channel, on _: Client) {
		serverList?.itemWasRemoved(channel)
		transcriptControllers.forget(channel)
	}

	func clientDirectory(_: ClientDirectory, didMoveChannelOn _: Client, from _: Int, to _: Int) {
		serverList?.setNeedsRefresh()
	}

	func clientDirectory(_: ClientDirectory, requestsSelectionOf item: ChatItem) {
		select(item)
	}

	func clientDirectory(_: ClientDirectory, requestsDeselectionOf item: ChatItem) {
		deselect(item)
	}

	func clientDirectory(_: ClientDirectory, requestsGroupDeselectionOf item: ChatItem) {
		deselectGroup(item)
	}

	func clientDirectoryRequestsSelectionAdjustment(_: ClientDirectory) {
		adjustSelection()
	}

	func clientDirectoryClientListDidChange(_: ClientDirectory) {
		reloadLoadingScreen()
	}
}
