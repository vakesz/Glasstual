import AppKit
import Foundation

/** One end-to-end scenario: a name for `--only` and the output, a time budget
 the watchdog enforces, and the steps. Adding a scenario is a new file under
 `Scenarios/` with a type conforming to this, plus its line in
 ``Registry/scenarios``. */
protocol Scenario {
	var name: String { get }
	var budget: Duration { get }
	func run(_ context: ScenarioContext) async throws
}

/// The only list of scenarios. `run` executes them in this order.
enum Registry {
	static let scenarios: [any Scenario] = [
		LaunchIdleScenario(),
		OnboardingSkipScenario(),
		OnboardingFinishScenario(),
		RejectionRetryScenario(),
		RepeatedRejectionScenario(),
		ChannelMessagingScenario(),
		ChannelDeniedScenario(),
		HistoryRelaunchScenario(),
		SettingsSnapshotScenario(),
		DCCSuccessScenario(),
		DCCCancelScenario(),
		BurstResponsivenessScenario(),
		TLSAcceptScenario(),
		TLSRejectRetryScenario(),
		TLSStallScenario(),
		CredentialConsentDeclineScenario(),
		CredentialConsentSendScenario(),
		BanAccountScenario(),
		ServerPropertiesWindowScenario(),
		PeopleWindowScenario(),
		OnboardingInteractionStyleScenario(),
		InlineCredentialConsentScenario(),
		HelpMenuScenario(),
		ThemePresetPersistsScenario(),
		WebSocketMessagingScenario(),
		WebSocketSecureScenario(),
		DCCSecureScenario(),
		DCCSecureChangedScenario(),
		DCCSecureChatScenario(),
		XDCCRequestScenario(),
		AccountRegistrationScenario(),
		MetadataEditScenario(),
		SASLSignInAgainScenario(),
		ReplyPrivatelyScenario(),
		HistoryGapBannerScenario(),
		ShowOriginalMessageScenario(),
	]
}

/** What a running scenario works with: its sandbox, its launches of the
 application, its loopback peer and its artifact directory.

 The context owns every process and listener the scenario starts, so teardown
 can stop them whatever the scenario got to. */
final class ScenarioContext {
	let name: String
	let app: AppBundle
	let corpora: URL
	let sandbox: RunSandbox
	let artifacts: URL
	private(set) var launches: [AppProcess] = []
	private(set) var peer: LoopbackPeer?
	/// The demo servers of a screenshot scene.
	private(set) var demo: DemoServer?
	/// Lines for `notes.txt` when the scenario fails.
	private(set) var notes: [String] = []

	init(name: String, app: AppBundle, corpora: URL, artifacts: URL) {
		self.name = name
		self.app = app
		self.corpora = corpora
		self.artifacts = artifacts
		sandbox = RunSandbox(scenario: name, app: app)
	}

	/// The current launch of the application.
	var current: AppProcess {
		get throws {
			guard let launch = launches.last else { throw HarnessFailure.setup("The scenario has not launched the application") }
			return launch
		}
	}

	var driver: AXDriver {
		get throws { try current.driver }
	}

	func note(_ line: String) {
		notes.append(line)
	}

	/// Starts the loopback peer for `mode` and returns it.
	func startPeer(_ mode: FixtureMode, passiveDCC: Bool = false) async throws -> LoopbackPeer {
		let peer = try LoopbackPeer(mode: mode, corpora: corpora, passiveDCC: passiveDCC)
		self.peer = peer
		_ = try await peer.start()
		note("peer \(mode.rawValue) on port \(peer.port)")
		return peer
	}

	/// Starts the demo servers the screenshot scenes connect to.
	func startDemo() async throws -> DemoServer {
		let demo = try DemoServer(corpora: corpora)
		self.demo = demo
		try await demo.start()
		note("demo servers on ports \(demo.directPort) and \(demo.bouncerPort)")
		return demo
	}

	/// The peer, which a connection scenario has started.
	var requirePeer: LoopbackPeer {
		get throws {
			guard let peer else { throw HarnessFailure.setup("The scenario has no loopback peer") }
			return peer
		}
	}

	/** Launches the application against this scenario's sandbox. `keepsState`
	 marks a launch the scenario will relaunch; the last launch leaves it off so
	 the application removes the run's state as it quits. */
	@discardableResult
	func launch(seed: Data?, keepsState: Bool = false) async throws -> AppProcess {
		let launch = try await AppProcess.launch(
			app,
			sandbox: sandbox,
			seed: seed,
			keepsState: keepsState,
			logs: artifacts,
			label: "app-\(launches.count + 1)"
		)
		launches.append(launch)
		note("launch \(launches.count): pid \(launch.pid)")
		return launch
	}

	/// `until` on the current launch's driver, failing at once if the peer
	/// recorded a protocol violation.
	func until<Value>(
		_ description: String,
		timeout: Duration = .seconds(20),
		_ probe: () throws -> Value?
	) async throws -> Value {
		try await driver.until(description, timeout: timeout) {
			try peer?.check()
			return try probe()
		}
	}

	func until(_ description: String, timeout: Duration = .seconds(20), _ condition: () throws -> Bool) async throws {
		_ = try await until(description, timeout: timeout) { try condition() ? true : nil }
	}

	/// Every launch's slowest Accessibility round trip was within the limit.
	func assertResponsive() throws {
		for launch in launches {
			try launch.driver.assertResponsive()
		}
	}

	/// Stops every launch still running and the peer.
	func stopAll() async {
		for launch in launches {
			await launch.stop()
		}
		peer?.stop()
		demo?.stop()
	}
}

/// How one scenario ended.
struct ScenarioResult {
	let name: String
	let duration: Duration
	let failure: String?
	let artifacts: URL?
}

/** Runs scenarios one after another, each in its own sandbox and under its
 own budget. A failure never stops the run: every selected scenario runs, and
 the summary says which passed. */
struct Runner {
	let app: AppBundle
	let corpora: URL
	let runDirectory: URL
	let keepArtifacts: Bool

	/** Runs `scenarios` in order. A screen that locks stops the run: nothing
	 can be driven on a locked screen, so the scenario that was running when it
	 locked is reported as interrupted and the rest are not started. Returns
	 the results and whether the run stopped for the lock. */
	func run(_ scenarios: [any Scenario]) async -> (results: [ScenarioResult], screenLocked: Bool) {
		var results: [ScenarioResult] = []
		for scenario in scenarios {
			guard Preflight.screenIsLocked == false else { return (results, true) }
			var result = await run(scenario)
			let locked = result.failure != nil && Preflight.screenIsLocked
			if locked {
				result = ScenarioResult(name: result.name, duration: result.duration,
				                        failure: "Interrupted: the screen locked during the scenario",
				                        artifacts: result.artifacts)
			}
			results.append(result)
			let seconds = String(format: "%.1fs", result.duration.inSeconds)
			if let failure = result.failure {
				let artifacts = result.artifacts.map { " (artifacts: \($0.path))" } ?? ""
				print("FAIL \(result.name) \(seconds): \(failure)\(artifacts)")
			} else {
				print("PASS \(result.name) \(seconds)")
			}
			if locked {
				return (results, true)
			}
		}
		return (results, false)
	}

	private func run(_ scenario: any Scenario) async -> ScenarioResult {
		let artifacts = runDirectory.appendingPathComponent(scenario.name, isDirectory: true)
		do {
			try FileManager.default.createDirectory(at: artifacts, withIntermediateDirectories: true)
		} catch {
			return ScenarioResult(name: scenario.name, duration: .zero, failure: "Cannot create \(artifacts.path)",
			                      artifacts: nil)
		}
		let context = ScenarioContext(name: scenario.name, app: app, corpora: corpora, artifacts: artifacts)
		let start = ContinuousClock.now
		let work = Task { try await scenario.run(context) }
		let watchdog = Task {
			try await Task.sleep(for: scenario.budget)
			work.cancel()
		}
		var failure: String?
		do {
			try await work.value
			try context.assertResponsive()
		} catch is CancellationError {
			let step = (try? context.driver.currentStep) ?? "start"
			failure = String(format: "Budget of %.0fs exceeded while waiting for: %@", scenario.budget.inSeconds, step)
		} catch {
			failure = String(describing: error)
		}
		watchdog.cancel()
		let duration = ContinuousClock.now - start
		if let failure {
			context.note("failure: \(failure)")
			for launch in context.launches {
				context.note(String(
					format: "launch pid %d: %@, %d AX round trips, slowest %.2fs at %@",
					launch.pid, launch.exitDescription, launch.driver.roundTrips,
					launch.driver.slowestRoundTrip.inSeconds, launch.driver.slowestStep
				))
			}
			if let peer = context.peer {
				context.note("peer evidence: \(peer.evidence)")
			}
			if let launch = context.launches.last, launch.isRunning,
			   let window = try? launch.driver.window(AXID.mainWindow),
			   let transcript = try? launch.driver.find(AXID.transcript, in: window),
			   let tail = try? launch.driver.tail(of: transcript, length: 1500)
			{
				context.note("selected transcript ends:\n\(tail)")
			}
			await Diagnostics.collect(for: context.launches, app: app, notes: context.notes, into: artifacts)
		}
		await context.stopAll()
		let leftovers = await context.sandbox.leftovers()
		await context.sandbox.removeLeftovers()
		var result = failure
		if result == nil, leftovers.isEmpty == false {
			result = "The application left run state behind: \(leftovers.joined(separator: ", "))"
		}
		if result == nil, keepArtifacts == false {
			try? FileManager.default.removeItem(at: artifacts)
		}
		return ScenarioResult(
			name: scenario.name,
			duration: duration,
			failure: result,
			artifacts: result == nil && keepArtifacts == false ? nil : artifacts
		)
	}

	/// The table printed after every scenario has run.
	static func summary(_ results: [ScenarioResult]) -> String {
		let width = max(8, results.map(\.name.count).max() ?? 0)
		var lines = ["", "Scenario".padding(toLength: width, withPad: " ", startingAt: 0) + "  Result  Time"]
		for result in results {
			lines.append(
				result.name.padding(toLength: width, withPad: " ", startingAt: 0)
					+ "  " + (result.failure == nil ? "PASS  " : "FAIL  ")
					+ String(format: "  %6.1fs", result.duration.inSeconds)
			)
		}
		let failed = results.count(where: { $0.failure != nil })
		lines.append("\(results.count - failed) passed, \(failed) failed")
		return lines.joined(separator: "\n")
	}
}

/// The checks `run` makes before it launches anything. Each failure says
/// what to do about it.
enum Preflight {
	static func check() throws {
		guard AXIsProcessTrusted() else {
			throw HarnessFailure.setup(
				"Grant Accessibility to the app running this command in System Settings > Privacy & Security > Accessibility, then rerun."
			)
		}
		let session = CGSessionCopyCurrentDictionary() as? [String: Any] ?? [:]
		if screenIsLocked {
			throw HarnessFailure.setup("The screen is locked. Unlock this login's screen, then rerun.")
		}
		if session[kCGSessionOnConsoleKey as String] as? Bool == false {
			throw HarnessFailure.setup("This login is not the one on the display. Switch to it, then rerun.")
		}
	}

	/// Whether this login's screen is locked now.
	static var screenIsLocked: Bool {
		let session = CGSessionCopyCurrentDictionary() as? [String: Any] ?? [:]
		return session["CGSSessionScreenIsLocked"] as? Bool == true
	}

	/** Takes the per-login lock that keeps two GUI runs from driving the same
	 screen. The descriptor stays open, and the lock held, until the process exits. */
	static func lock() throws -> Int32 {
		let path = "/private/tmp/glasstual-e2e-\(getuid()).lock"
		let descriptor = open(path, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
		guard descriptor >= 0 else { throw HarnessFailure.setup("Cannot open the GUI run lock \(path).") }
		var info = stat()
		guard fstat(descriptor, &info) == 0, info.st_uid == getuid(), info.st_nlink == 1,
		      info.st_mode & 0o777 == 0o600, info.st_mode & S_IFMT == S_IFREG
		else {
			close(descriptor)
			throw HarnessFailure.setup("The GUI run lock \(path) is not a private file of this login. Remove it, then rerun.")
		}
		guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
			close(descriptor)
			throw HarnessFailure.setup("Another glasstual-e2e run is driving this login. Wait for it to finish, then rerun.")
		}
		return descriptor
	}
}
