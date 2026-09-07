import Darwin
import Foundation
import Testing

@Suite(.serialized)
struct ConnectionLifecycleE2ETests {
	nonisolated static let scenarios = [ // nonisolated: let
		"onboardingSkip", "onboardingFinish", "pluginSmiley", "dccSuccess", "dccCancel", "burstResponsiveness",
		"rejectionRetry",
		"repeatedRejection",
		"channelMessaging",
		"channelDenied",
		"historyRelaunch",
		"settingsSnapshot",
		"tlsAccept",
		"tlsRejectRetry",
		"tlsStall",
	]

	/// The scenarios `ScenarioKind.hasFixtureTest` excludes. This bundle cannot
	/// link the harness, so the supervisor's completion check is what proves the
	/// two lists still agree: it rejects a missing or unexpected case.
	nonisolated static let withoutFixtureTest = ["settingsSnapshot", "onboardingSkip"] // nonisolated: let

	@Test(arguments: scenarios + scenarios.filter { !withoutFixtureTest.contains($0) }.map { "fixture." + $0 })
	func connectionMatrix(kind: String) throws {
		let fixtureOnly = kind.hasPrefix("fixture.")
		let scenario = fixtureOnly ? String(kind.dropFirst("fixture.".count)) : kind
		let environment = ProcessInfo.processInfo.environment
		let helper = try #require(environment["E2E_HELPER"], "Use make e2e; a stable AX-authorized helper is required")
		let directory = try #require(Self.runDirectory(in: environment), "Use make e2e for the independent watchdog")
		let runRoot = URL(fileURLWithPath: directory, isDirectory: true)
		let root = runRoot.appendingPathComponent("scenarios/\(kind)-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(
			at: root,
			withIntermediateDirectories: true,
			attributes: [.posixPermissions: 0o700]
		)
		try Data(kind.utf8).write(to: root.appendingPathComponent("scenario-kind"), options: .atomic)
		var passed = false
		defer {
			if !passed {
				try? Data("failed".utf8).write(
					to: root.appendingPathComponent("scenario-failed"),
					options: .atomic
				)
			}
		}
		// Xcode owns the runner, which remains alive between cases. Retain its identity until process exit.
		_ = try register(ProcessInfo.processInfo.processIdentifier, in: runRoot)
		let logURL = root.appendingPathComponent("helper.log")
		try Data().write(to: logURL)
		let log = try FileHandle(forWritingTo: logURL)
		defer { try? log.close() }
		let process = Process()
		process.executableURL = URL(fileURLWithPath: helper)
		process.arguments = [fixtureOnly ? "fixture-test" : "scenario"]
		process.environment = environment.filter {
			$0.key.hasPrefix("E2E_") || ["HOME", "USER", "LOGNAME", "PATH", "TMPDIR"].contains($0.key)
		}
		process.environment?["E2E_SCENARIO"] = scenario
		process.environment?["E2E_SCENARIO_DIRECTORY"] = root.path
		process.environment?["E2E_RUN_DIRECTORY"] = runRoot.path
		process.standardOutput = log
		process.standardError = log
		let scenarioDeadline = root.appendingPathComponent("scenario-deadline")
		let duration = scenario.hasPrefix("dcc") ? 240.0 : 180.0
		try Data(String(ProcessInfo.processInfo.systemUptime + duration).utf8).write(
			to: scenarioDeadline,
			options: .atomic
		)
		try process.run()
		let helperRecord: URL
		do {
			helperRecord = try register(process.processIdentifier, in: runRoot)
		} catch {
			if process.isRunning {
				process.terminate()
				if process.isRunning {
					kill(process.processIdentifier, SIGKILL)
				}
			}
			throw error
		}
		// The script's supervisor is independent of this runner and the application's main actor.
		process.waitUntilExit()
		try FileManager.default.removeItem(at: helperRecord)
		try FileManager.default.removeItem(at: scenarioDeadline)
		try #require(process.terminationReason == .exit)
		try #require(
			process.terminationStatus == 0,
			"Helper failed. See helper diagnostics and artifacts in the unique E2E run directory"
		)
		if fixtureOnly {
			try #require(try read("fixture-selftests-passed", in: root) ==
				"protocol and local network assertions passed")
			try #require(try read("peer-complete", in: root) == "complete")
			try Data("passed".utf8).write(to: root.appendingPathComponent("scenario-passed"), options: .atomic)
			passed = true
			return
		}
		try checkScenario(scenario, in: root)
		try #require(try read("scenario-passed", in: root) == "passed")
		passed = true
	}

	private func checkScenario(_ scenario: String, in root: URL) throws {
		if scenario.hasPrefix("onboarding") {
			let launches = try JSONDecoder().decode(
				[OnboardingLaunchEvidence].self,
				from: Data(contentsOf: root.appendingPathComponent("onboarding-evidence.json"))
			)
			try #require(launches.count == 2)
			try #require(launches[0].pid > 0 && launches[1].pid > 0 && launches[0].pid != launches[1].pid)
			for launch in launches {
				try #require(launch.exitReason == "exit" && launch.exitStatus == 0 && launch.identityVisible)
				try #require(launch.quitSeconds > 0 && launch.quitSeconds <= 5)
			}
			for prefix in ["", "relaunch-"] {
				try checkProbe(
					read(prefix + "probe-evidence", in: root).split(separator: " "),
					in: root,
					prefix: prefix
				)
			}
			if scenario == "onboardingSkip" {
				try #require(!FileManager.default.fileExists(atPath: root.appendingPathComponent("port").path))
			} else {
				try #require(try read("onboarding-network", in: root) ==
					"custom loopback server registered; manual QUIT observed")
				try #require(try read("registration-1", in: root) ==
					"CAP LS 302; NICK e2euser; USER e2euser 0 * :Synthetic E2E User; CAP END")
				try #require(try read("disconnect-wire", in: root) == "QUIT E2E_QUIT and EOF")
			}
			return
		}
		let evidence = try JSONDecoder().decode(
			Evidence.self,
			from: Data(contentsOf: root.appendingPathComponent("evidence.json"))
		)
		try #require(evidence.scenario == scenario)
		try #require(evidence.originalPID > 0 && evidence.originalPID == evidence.finalPID)
		try #require(evidence.shutdownSeconds > 0 && evidence.shutdownSeconds <= 5)
		try #require(evidence.appExitReason == "exit" && evidence.appExitStatus == 0)
		let rejections = scenario == "repeatedRejection" ? 3 : (scenario == "rejectionRetry" ? 1 : 0)
		try #require(evidence.rejections == rejections)
		try #require(evidence.connectedQuit == !["rejectionRetry", "tlsStall", "settingsSnapshot"].contains(scenario))
		try checkWire(scenario: scenario, rejections: rejections, in: root)
		try checkAdditionalEvidence(scenario: scenario, originalPID: evidence.originalPID, in: root)
		let probe = try read("probe-evidence", in: root).split(separator: " ")
		try checkProbe(probe, in: root)
	}

	private func checkWire(scenario: String, rejections: Int, in root: URL) throws {
		for rejection in 0 ..< rejections {
			try #require(try read("recovery-complete-\(rejection + 1)", in: root) == "disconnected")
		}
		if scenario == "tlsStall" {
			try #require(try read("stall-closed", in: root) == "Stalled TLS closed")
			try #require(!FileManager.default.fileExists(atPath: root.appendingPathComponent("registration-1").path))
		} else {
			let attempts = scenario == "tlsRejectRetry" ? [2] : Array(1 ... rejections + 1)
			for attempt in attempts {
				try #require(try read("registration-\(attempt)", in: root) ==
					"CAP LS 302; NICK e2euser; USER e2euser 0 * :Synthetic E2E User; CAP END")
			}
			try #require(try read("disconnect-wire", in: root) == "QUIT E2E_QUIT and EOF")
		}
		if scenario == "tlsRejectRetry" {
			try #require(try read("tls-rejected", in: root) == "TLS closed without IRC registration")
			try #require(!FileManager.default.fileExists(atPath: root.appendingPathComponent("registration-1").path))
		}
		if ["channelMessaging", "historyRelaunch"].contains(scenario) {
			try #require(try read("join-wire", in: root) == "JOIN #e2e")
			try #require(try read("message-wire", in: root) == "PRIVMSG #e2e :E2E_TYPED_MESSAGE")
			try #require(try read("reply-wire", in: root) == "PRIVMSG #e2e :fixture: E2E_TYPED_REPLY")
		}
		if scenario == "channelDenied" {
			try #require(try read("connection-count", in: root) == "1")
			try #require(try read("denied-join-wire", in: root) == "JOIN #retry denied 477")
			try #require(try read("identify-wire", in: root) == "NickServ IDENTIFY; 900 ACCOUNT MODE +r")
			try #require(try read("retry-join-wire", in: root) == "JOIN #retry after identification")
			try #require(try read("contextual-join-ax", in: root) ==
				"AXShowMenu #retry with #other selected; Join Channel")
		}
	}

	private func checkAdditionalEvidence(scenario: String, originalPID: Int32, in root: URL) throws {
		if scenario ==
			"pluginSmiley"
		{
			try #require(try read("plugin-effect", in: root) == "raw; converted; raw via loaded plugin Settings")
		}
		if scenario == "burstResponsiveness" {
			try #require(try read("burst-complete", in: root) == "10000 names; 5000 messages")
			try #require(try read("burst-batches", in: root) == "100")
			for index in 1 ...
				3
			{
				try #require(try read("burst-ui-switch-\(index)", in: root) == "Settings and channel responded")
			}
		}
		if scenario.hasPrefix("dcc") {
			let expected = scenario == "dccCancel" ? 37003 : 100_003
			let file = try read("dcc-file-evidence", in: root).split(separator: " ")
			try #require(file.count == 2 && Int(file[0]) == expected && file[1].count == 64)
			try #require(try read("dcc-acknowledged", in: root) == String(expected))
			try #require(try read("dcc-peer-complete", in: root) ==
				(scenario == "dccCancel" ? "cancelled after 37003 bytes" : "completed 100003 bytes"))
		}
		if scenario == "settingsSnapshot" {
			try #require(try read("settings-roundtrip", in: root) ==
				"toggle exported; merge restored; recovery preview cancelled")
		}
		if scenario == "historyRelaunch" {
			let evidence = try JSONDecoder().decode(
				RelaunchEvidence.self,
				from: Data(contentsOf: root.appendingPathComponent("relaunch-evidence.json"))
			)
			try #require(evidence.firstPID == originalPID && evidence.relaunchPID > 0 && evidence
				.relaunchPID != originalPID)
			try #require(evidence.historyTranscript && evidence.disconnected)
			try #require(evidence.exitReason == "exit" && evidence.exitStatus == 0)
			try #require(evidence.quitSeconds > 0 && evidence.quitSeconds <= 5)
			try checkProbe(
				read("relaunch-probe-evidence", in: root).split(separator: " "),
				in: root,
				prefix: "relaunch-"
			)
		}
	}

	private func checkProbe(_ probe: [Substring], in root: URL, prefix: String = "") throws {
		try #require(probe.count == 2)
		try #require((Int(probe[0]) ?? 0) >= 3)
		try #require((Double(probe[1]) ?? .infinity) < 2)
		try #require(try read(prefix + "probe-complete", in: root) == "stopped")
	}

	/// The run directory changes on every invocation, so it is never a build
	/// setting: that would change the build description and force a full rebuild
	/// before each run. `scripts/e2e.sh` records it under the stable `E2E_OUTPUT`
	/// the scheme does pass, and the environment still wins when it is set.
	private static func runDirectory(in environment: [String: String]) -> String? {
		if let directory = environment["E2E_RUN_DIRECTORY"], !directory.isEmpty {
			return directory
		}
		guard let output = environment["E2E_OUTPUT"], !output.isEmpty else { return nil }
		let pointer = URL(fileURLWithPath: output, isDirectory: true).appendingPathComponent("current-run")
		guard let recorded = try? String(contentsOf: pointer, encoding: .utf8) else { return nil }
		let directory = recorded.trimmingCharacters(in: .whitespacesAndNewlines)
		return directory.isEmpty ? nil : directory
	}

	private func read(_ name: String, in root: URL) throws -> String {
		try String(contentsOf: root.appendingPathComponent(name), encoding: .utf8)
	}

	private func register(_ pid: pid_t, in root: URL) throws -> URL {
		var info = proc_bsdinfo()
		let size = Int32(MemoryLayout<proc_bsdinfo>.size)
		try #require(
			proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size,
			"Child exited before parent registration"
		)
		let record = root.appendingPathComponent("owned/\(pid)")
		try Data("\(info.pbi_start_tvsec):\(info.pbi_start_tvusec)".utf8).write(to: record, options: .atomic)
		return record
	}
}

private struct Evidence: Decodable {
	let scenario: String
	let originalPID: Int32
	let finalPID: Int32
	let rejections: Int
	let connectedQuit: Bool
	let shutdownSeconds: Double
	let appExitReason: String
	let appExitStatus: Int32
}

private struct RelaunchEvidence: Decodable {
	let firstPID: Int32
	let relaunchPID: Int32
	let historyTranscript: Bool
	let disconnected: Bool
	let exitReason: String
	let exitStatus: Int32
	let quitSeconds: Double
}

private struct OnboardingLaunchEvidence: Decodable {
	let pid: Int32
	let exitReason: String
	let exitStatus: Int32
	let identityVisible: Bool
	let quitSeconds: Double
}
