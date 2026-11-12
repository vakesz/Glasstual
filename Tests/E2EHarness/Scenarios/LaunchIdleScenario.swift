import Foundation

/** A seeded launch left idle for half a minute, sampled through
 Accessibility the whole time, then quit. It replaces the old smoke run: the
 application has to answer every sample within the responsiveness limit, and
 quit cleanly with no state left behind. */
struct LaunchIdleScenario: Scenario {
	let name = "launchIdle"
	let budget = Duration.seconds(90)
	private let idle = Duration.seconds(30)

	func run(_ context: ScenarioContext) async throws {
		let peer = try await context.launchAgainstPeer(.registration)
		try await context.server(AXID.RowState.disconnected)
		let end = Deadline(after: idle)
		var samples = 0
		while end.hasPassed == false {
			try await context.until("idle sample \(samples + 1)") {
				try context.mainWindow() != nil && context.rowState("server", ScenarioContext.network) != nil
			}
			samples += 1
			try await Task.sleep(for: .milliseconds(500))
		}
		try context.note("idle samples: \(samples), slowest round trip \(context.driver.slowestRoundTrip.inSeconds)s")
		guard samples >= 20 else {
			throw HarnessFailure.assertion("Only \(samples) idle samples in \(idle.inSeconds)s")
		}
		try await context.quit(peerSeesQuit: false)
		guard peer.evidence.connections == 0 else {
			throw HarnessFailure.assertion("The idle launch connected without being asked")
		}
	}
}
