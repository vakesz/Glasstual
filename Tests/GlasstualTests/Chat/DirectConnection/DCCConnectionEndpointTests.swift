// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

/// Dialling refuses what no connection could be made to.
struct DCCConnectionEndpointTests {
	@Test("An empty host is a bad parameter, not a connection attempt")
	func emptyHost() async {
		await #expect(throws: DCCTransferError.badParameter) {
			try await DCCConnectionEndpoint.connect(toHost: "", port: 5000, interfaceName: nil, timeout: .seconds(1))
		}
	}
}
