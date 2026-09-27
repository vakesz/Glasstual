// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

@testable import Glasstual
import Testing

@Suite("Network reachability")
struct NetworkReachabilityTests {
	@Test("The first path establishes the initial state", arguments: [true, false])
	func firstPathProducesNoChange(isReachable: Bool) {
		var reachability = NetworkReachability()
		#expect(reachability.update(isReachable: isReachable) == nil)
	}

	@Test("Repeated paths report nothing", arguments: [true, false])
	func unchangedPathProducesNoChange(isReachable: Bool) {
		var reachability = NetworkReachability()
		_ = reachability.update(isReachable: isReachable)
		#expect(reachability.update(isReachable: isReachable) == nil)
	}

	@Test("Path changes report once in each direction", arguments: [true, false])
	func changesSurviveMonitorRestarts(initiallyReachable: Bool) {
		var reachability = NetworkReachability()
		_ = reachability.update(isReachable: initiallyReachable)
		// The delegate retains this value when it replaces the monitor after sleep.
		#expect(reachability.update(isReachable: !initiallyReachable) == !initiallyReachable)
		#expect(reachability.update(isReachable: !initiallyReachable) == nil)
		#expect(reachability.update(isReachable: initiallyReachable) == initiallyReachable)
	}
}
