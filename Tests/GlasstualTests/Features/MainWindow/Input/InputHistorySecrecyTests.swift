// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

/// A line that carries a password or a code never reaches input history.
@MainActor
@Suite("Input history secrecy")
struct InputHistorySecrecyTests {
	@Test(
		"Secret-carrying commands are recognised in any case and among other lines",
		arguments: ["/register * * pw", "/REGISTER ada a@b.c pw", "/verify 1234", "/pass hunter2", "  /verify ada 1", "hi\n/pass x"]
	)
	func secretLines(_ text: String) {
		#expect(LocalCommand.inputCarriesSecret(text))
	}

	@Test("Ordinary lines and escaped slashes are kept", arguments: ["/msg ada hi", "hello", "//register x y z", "register"])
	func ordinaryLines(_ text: String) {
		#expect(LocalCommand.inputCarriesSecret(text) == false)
	}
}
