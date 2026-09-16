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

/** A transcript controller is the view a chat item is drawn into. Every
 requirement already existed on the class; the protocol is what lets the IRC
 layer hold one without depending on the concrete `TranscriptController`. */
extension TranscriptController: ChatItemPresentation {
	var presentationIdentifier: String {
		uniqueIdentifier
	}

	func lastRenderedLineDate() -> Date? {
		backingView?.displayedLines.filter {
			ChatHistoryPolicy.marksReadPosition(lineType: $0.lineType, messageIdentifier: $0.messageIdentifier)
		}.map(\.receivedAt).max()
	}

	/** Both conversation seams answer from the union of what the view is showing
	 and what it has been handed but not applied yet. A line moves from the second
	 to the first synchronously on the main actor, so neither holds it twice.

	 Lines loaded from storage are in neither list, which is why `Client`
	 combines this with the historic log's index: history seeding fills that index
	 synchronously, so it already accounts for the scrollback. */
	func newestConversationLineDate() -> Date? {
		let displayed = backingView?.displayedLines.filter(\.lineType.isConversation).map(\.receivedAt) ?? []
		let awaiting = linesAwaitingRender.filter(\.lineType.isConversation).map(\.receivedAt)

		return (displayed + awaiting).max()
	}

	func conversationLineCount(after date: Date) -> Int {
		let displayed = backingView?.displayedLines
			.count { $0.lineType.isConversation && $0.receivedAt > date } ?? 0

		return displayed + linesAwaitingRender.count { $0.lineType.isConversation && $0.receivedAt > date }
	}

	func lastPrintedLine() -> LogLine? {
		lastLine()
	}
}
