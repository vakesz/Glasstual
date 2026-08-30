/*  *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 *    Copyright (c) 2018 Codeux Software, LLC & respective contributors.
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

@testable import Glasstual
import Testing

@MainActor
@Suite("Requested command bookkeeping")
struct IRCClientRequestedCommandsTests {
	@Test("A visible ISON request stays visible until it is closed")
	func visibleRequestIsReportedUntilClosed() {
		let requests = ClientRequestedCommands()

		#expect(requests.visibleIsonRequest == false)

		requests.recordIsonRequestOpenedAsVisible()

		#expect(requests.visibleIsonRequest)

		requests.recordIsonRequestClosed()

		#expect(requests.visibleIsonRequest == false)
	}

	@Test("Requests for the same command are closed in insertion order")
	func requestsWithSameCommandCloseInInsertionOrder() {
		let requests = ClientRequestedCommands()

		requests.recordWhoRequestOpened()
		requests.recordWhoRequestOpenedAsVisible()

		#expect(requests.visibleWhoRequest == false)

		requests.recordWhoRequestClosed()

		#expect(requests.visibleWhoRequest)

		requests.recordWhoRequestClosed()

		#expect(requests.visibleWhoRequest == false)
	}

	@Test("ISON and WHO requests are tracked independently")
	func isonAndWhoRequestsAreIndependent() {
		let requests = ClientRequestedCommands()

		requests.recordIsonRequestOpenedAsVisible()
		requests.recordWhoRequestOpened()

		#expect(requests.visibleIsonRequest)
		#expect(requests.visibleWhoRequest == false)

		requests.recordIsonRequestClosed()

		#expect(requests.visibleIsonRequest == false)
		#expect(requests.visibleWhoRequest == false)
	}

	@Test("Removing the commands clears every request and closing again is a no-op")
	func removeCommandsClearsEveryRequest() {
		let requests = ClientRequestedCommands()

		requests.recordIsonRequestOpenedAsVisible()
		requests.recordWhoRequestOpenedAsVisible()
		requests.removeCommands()

		#expect(requests.visibleIsonRequest == false)
		#expect(requests.visibleWhoRequest == false)

		/* Closing a command that is not open remains a no-op. */
		requests.recordIsonRequestClosed()
		requests.recordWhoRequestClosed()

		#expect(requests.visibleIsonRequest == false)
		#expect(requests.visibleWhoRequest == false)
	}
}
