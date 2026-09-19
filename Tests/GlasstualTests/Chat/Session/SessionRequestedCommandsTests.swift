// Copyright (c) 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

@testable import Glasstual
import Testing

@MainActor
@Suite("Requested command bookkeeping")
struct SessionRequestedCommandsTests {
	@Test("A visible ISON request stays visible until it is closed")
	func visibleRequestIsReportedUntilClosed() {
		let requests = SessionRequestedCommands()

		#expect(requests.visibleIsonRequest == false)

		requests.recordIsonRequestOpenedAsVisible()

		#expect(requests.visibleIsonRequest)

		requests.recordIsonRequestClosed()

		#expect(requests.visibleIsonRequest == false)
	}

	@Test("Closing an ISON request answers with the nicknames that request asked about")
	func closingIsonRequestReturnsItsNicknames() {
		let requests = SessionRequestedCommands()

		requests.recordIsonRequestOpened(askingAbout: ["alice", "bob"])
		requests.recordIsonRequestOpened(askingAbout: ["carol"])

		#expect(requests.recordIsonRequestClosed() == ["alice", "bob"])
		#expect(requests.hasOpenIsonRequest)
		#expect(requests.recordIsonRequestClosed() == ["carol"])
		#expect(requests.hasOpenIsonRequest == false)
		#expect(requests.recordIsonRequestClosed().isEmpty)
	}

	@Test("Requests for the same command are closed in insertion order")
	func requestsWithSameCommandCloseInInsertionOrder() {
		let requests = SessionRequestedCommands()

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
		let requests = SessionRequestedCommands()

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
		let requests = SessionRequestedCommands()

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
