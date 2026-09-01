/*  *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

@testable import Glasstual
import Testing

@MainActor
@Suite("Reachability")
struct ReachabilityTests {
	@Test("A fresh notifier starts out unreachable")
	func factoryCreatesNotifier() {
		let reachability = Reachability.reachabilityForInternetConnection()

		#expect(reachability.reachable == false)
	}

	@Test("The first path seeds the state without reporting a change")
	func firstPathSeedsWithoutEvent() {
		var currentlyReachable = false
		var receivedInitialPath = false
		let event = Reachability.evaluatePathChange(
			reachable: true,
			currentlyReachable: &currentlyReachable,
			receivedInitialPath: &receivedInitialPath
		)

		#expect(event == .none)
		#expect(currentlyReachable)
		#expect(receivedInitialPath)
	}

	@Test("A path that repeats the current state reports nothing")
	func unchangedPathProducesNoEvent() {
		var currentlyReachable = true
		var receivedInitialPath = true
		let event = Reachability.evaluatePathChange(
			reachable: true,
			currentlyReachable: &currentlyReachable,
			receivedInitialPath: &receivedInitialPath
		)

		#expect(event == .none)
		#expect(currentlyReachable)
	}

	@Test("Losing and regaining the path reports one event each way")
	func reachabilityTransitionsEmitExpectedEvents() {
		var currentlyReachable = true
		var receivedInitialPath = true
		let becameUnreachable = Reachability.evaluatePathChange(
			reachable: false,
			currentlyReachable: &currentlyReachable,
			receivedInitialPath: &receivedInitialPath
		)

		#expect(becameUnreachable == .becameUnreachable)
		#expect(currentlyReachable == false)

		let becameReachable = Reachability.evaluatePathChange(
			reachable: true,
			currentlyReachable: &currentlyReachable,
			receivedInitialPath: &receivedInitialPath
		)

		#expect(becameReachable == .becameReachable)
		#expect(currentlyReachable)
	}

	/// A path monitor is single use, so a restarted notifier has to build a new one.
	@Test("A notifier can be started again after it has been stopped")
	func startAndStopNotifierRoundTrip() {
		let reachability = Reachability.reachabilityForInternetConnection()

		#expect(reachability.startNotifier())

		reachability.stopNotifier()

		#expect(reachability.startNotifier())

		reachability.stopNotifier()
	}
}
