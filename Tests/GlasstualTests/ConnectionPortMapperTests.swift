/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import CocoaExtensions
import dnssd
import Foundation
@testable import Glasstual
import Testing

/** The NAT-PMP mapper's decisions, without a router.

 What a reply means, and what the mapper reports when it has none, are both
 answered from values. The router conversation itself is not something a unit
 test can have, so it is the reading of the answer that is pinned here. */
@MainActor
@Suite("Port mapper state")
struct ConnectionPortMapperTests {
	/** A reply that reports success and a public port of zero is the router
	 saying it mapped nothing, whatever port was asked for. Reading it as
	 success left a transfer advertising port zero to its peer, and the old
	 condition only caught it when a specific public port had been requested —
	 so a mapper that let the router choose took the refusal for a mapping. */
	@Test("Success with no public port is a refusal, whatever was asked for")
	func successWithoutAPublicPortIsARefusal() {
		#expect(
			XRPortMapper.resolvedError(reportedError: 0, publicPort: 0)
				== DNSServiceErrorType(kDNSServiceErr_NATPortMappingUnsupported)
		)
	}

	@Test("A mapped port is reported as success")
	func aMappedPortIsSuccess() {
		#expect(XRPortMapper.resolvedError(reportedError: 0, publicPort: 6000) == 0)
	}

	/// mDNSResponder's own error is more specific than "unsupported" and is
	/// what the caller branches on, so it survives untouched.
	@Test("A reported error is passed through")
	func aReportedErrorIsPassedThrough() {
		let refused = DNSServiceErrorType(kDNSServiceErr_Refused)

		#expect(XRPortMapper.resolvedError(reportedError: refused, publicPort: 0) == refused)
		#expect(XRPortMapper.resolvedError(reportedError: refused, publicPort: 6000) == refused)
	}

	/** An open mapping used to keep its own mapper alive.

	 The `+1` mDNSResponder was handed as its callback context was a reference to
	 the mapper, released only by `close()`, so a mapper whose owner simply let
	 go of it was never deallocated: its `isolated deinit` — the one thing that
	 closes a mapping nobody closed by hand — could not run while a mapping was
	 open. The context is a small box that names the mapper weakly now.

	 The router conversation is not something a unit test can have, so this
	 asserts what holds either way: whether or not mDNSResponder accepted the
	 request, letting go of the mapper deallocates it. */
	@Test("An open mapping does not keep its mapper alive")
	func anOpenMappingDoesNotRetainItsMapper() {
		weak var released: XRPortMapper?

		do {
			let mapper = XRPortMapper(port: 0)
			released = mapper
			/* A refusal is a fine outcome here — it is the retain that is under
			 test, and `open()` takes it before it asks. */
			_ = mapper.open()
			#expect(released != nil)
		}

		#expect(released == nil)
	}

	/// A mapper nobody has opened has nothing to report, and closing one that
	/// was never opened is not an error to show the user.
	@Test("An unopened mapper reports nothing, and closing it is harmless")
	func anUnopenedMapperIsQuiet() {
		let mapper = XRPortMapper(port: 6000)

		#expect(mapper.isMapped == false)
		#expect(mapper.publicAddress == nil)
		#expect(mapper.publicPort == 0)

		mapper.close()
		mapper.close()

		#expect(mapper.error == 0)
		#expect(mapper.isMapped == false)
	}
}
