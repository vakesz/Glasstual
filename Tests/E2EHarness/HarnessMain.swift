import AppKit
import ApplicationServices
import Darwin
import Dispatch
import Foundation

enum HarnessFailure: Error {
	case setup(String)
	case assertion(String)
}

@main
@MainActor
enum HarnessMain {
	static func main() async {
		do {
			let arguments = CommandLine.arguments
			guard arguments.count >= 2
			else {
				throw HarnessFailure
					.setup("Expected supervise, preflight, scenario, peer, probe, fixture-test or list-fixtures")
			}
			switch arguments[1] {
			case "supervise":
				try await HarnessSupervisor.run()
			case "list-fixtures":
				// scripts/e2e-fixtures.sh iterates this instead of repeating the names.
				let modes = ScenarioKind.fixtureModes.joined(separator: "\n") + "\n"
				try FileHandle.standardOutput.write(contentsOf: Data(modes.utf8))
			case "preflight":
				try preflight()
			case "scenario":
				try preflight()
				try await Scenario.run()
			case "peer":
				try await LoopbackPeer(kind: ScenarioKind.current).run()
			case "probe":
				try preflight()
				try await ResponsivenessProbe.run()
			case "fixture-test":
				try await FixtureSelfTests.run()
			default:
				throw HarnessFailure.setup("Unknown helper mode")
			}
		} catch {
			if CommandLine.arguments.dropFirst().first == "scenario" {
				// A failed assertion must not read back as an external watchdog
				// timeout, so disarm every deadline this helper armed. The runner
				// owns scenario-deadline and removes it once the helper exits.
				try? HarnessFiles.removeArmedDeadlines()
			}
			// Errors contain only harness-authored diagnostics, never wire payloads or preferences.
			let message = "E2E: \(error)\n"
			try? FileHandle.standardError.write(contentsOf: Data(message.utf8))
			if case HarnessFailure.setup = error {
				exit(2)
			}
			exit(1)
		}
	}

	static func preflight() throws {
		guard ProcessInfo.processInfo.environment["E2E_DISPOSABLE_USER_CONSENT"] == "YES" else {
			throw HarnessFailure.setup("Set E2E_DISPOSABLE_USER_CONSENT=YES only in a disposable macOS login")
		}
		guard AXIsProcessTrusted() else {
			throw HarnessFailure.setup("Grant Accessibility to the stable GlasstualE2EHarness executable, then rerun")
		}
	}
}

@MainActor
enum HarnessFiles {
	static func required(_ key: String) throws -> String {
		guard let value = ProcessInfo.processInfo.environment[key], !value.isEmpty else {
			throw HarnessFailure.setup("Missing \(key); launch with scripts/e2e.sh")
		}
		return value
	}

	static var root: URL {
		get throws {
			if let scenario = ProcessInfo.processInfo.environment["E2E_SCENARIO_DIRECTORY"] {
				return URL(fileURLWithPath: scenario, isDirectory: true)
			}
			return try runRoot
		}
	}

	static var runRoot: URL {
		get throws { try URL(fileURLWithPath: required("E2E_RUN_DIRECTORY"), isDirectory: true) }
	}

	static func write(_ text: String, to name: String) throws {
		try Data(text.utf8).write(to: root.appendingPathComponent(name), options: .atomic)
	}

	static func read(_ name: String) throws -> String {
		try String(contentsOf: root.appendingPathComponent(name), encoding: .utf8)
	}

	static func exists(_ name: String) throws -> Bool {
		try FileManager.default.fileExists(atPath: root.appendingPathComponent(name).path)
	}

	static var now: Double {
		ProcessInfo.processInfo.systemUptime
	}

	static func check(_ deadline: Double) throws {
		guard now < deadline else { throw HarnessFailure.assertion("Monotonic operation deadline exceeded") }
	}

	/// Clear every deadline marker this helper armed in the scenario directory.
	/// `scenario-deadline` belongs to the Xcode-owned runner and stays.
	static func removeArmedDeadlines() throws {
		for name in try FileManager.default.contentsOfDirectory(atPath: root.path)
			where name.hasSuffix("-deadline") && name != "scenario-deadline"
		{
			try remove(name)
		}
	}

	static func remove(_ name: String) throws {
		if try exists(name) {
			try FileManager.default.removeItem(at: root.appendingPathComponent(name))
		}
	}

	static func identity(_ pid: pid_t) -> String? {
		var info = proc_bsdinfo()
		let size = Int32(MemoryLayout<proc_bsdinfo>.size)
		guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
		return "\(info.pbi_start_tvsec):\(info.pbi_start_tvusec)"
	}

	static func register(_ pid: pid_t) throws {
		guard let birth = identity(pid) else {
			throw HarnessFailure.assertion("Owned process exited before registration")
		}
		try Data(birth.utf8).write(to: runRoot.appendingPathComponent("owned/\(pid)"), options: .atomic)
	}

	static func launch(_ process: Process) throws {
		try process.run()
		do {
			try register(process.processIdentifier)
		} catch {
			// A short command may already be reaped; its Process still holds the real exit status.
			if identity(process.processIdentifier) == nil, !process.isRunning {
				return
			}
			// If the ledger cannot be written, the launching parent still owns this exact child.
			if process.isRunning {
				process.terminate()
				if process.isRunning {
					kill(process.processIdentifier, SIGKILL)
				}
				try? write("Child registration failed; parent forced cleanup", to: "cleanup-failure.txt")
			}
			throw error
		}
	}

	static func unregister(_ pid: pid_t) throws {
		let record = try runRoot.appendingPathComponent("owned/\(pid)")
		if FileManager.default.fileExists(atPath: record.path) {
			try FileManager.default.removeItem(at: record)
		}
	}
}

/// e2e.sh execs this supervisor. It never calls AX or blocks waiting for a child.
@MainActor
enum HarnessSupervisor {
	private static var interrupted = false

	static func run() async throws {
		guard try HarnessFiles.required("E2E_DISPOSABLE_USER_CONSENT") == "YES" else {
			throw HarnessFailure.setup("Disposable-account consent is required")
		}
		// Keep the inode for the entire lifecycle, including diagnostics and cleanup.
		let guardPath = "/private/tmp/glasstual-e2e-\(getuid()).lock"
		let guardFD = open(guardPath, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
		guard guardFD >= 0 else { throw HarnessFailure.setup("Cannot open per-login E2E lifecycle guard") }
		defer { close(guardFD) }
		var guardInfo = stat()
		guard fstat(guardFD, &guardInfo) == 0, guardInfo.st_uid == getuid(),
		      guardInfo.st_nlink == 1, guardInfo.st_mode & 0o777 == 0o600,
		      guardInfo.st_mode & S_IFMT == S_IFREG, flock(guardFD, LOCK_EX | LOCK_NB) == 0
		else {
			throw HarnessFailure.setup("Another E2E lifecycle owns this login, or guard is unsafe")
		}
		let signals = [SIGINT, SIGTERM].map { number in
			signal(number, SIG_IGN)
			let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
			source.setEventHandler { Task { @MainActor in interrupted = true } }
			source.resume()
			return source
		}
		defer { signals.forEach { $0.cancel() } }
		try HarnessFiles.write(String(ProcessInfo.processInfo.processIdentifier), to: "watchdog.pid")
		guard let birth = HarnessFiles.identity(ProcessInfo.processInfo.processIdentifier) else {
			throw HarnessFailure.assertion("Supervisor identity unavailable")
		}
		try HarnessFiles.write(birth, to: "watchdog.identity")
		let deadline = HarnessFiles.now + 3000
		do {
			try await commands(deadline: deadline)
			let scenarios = try scenarioDirectories()
			var completed: [String] = []
			for scenario in scenarios {
				guard try String(contentsOf: scenario.appendingPathComponent("scenario-passed"), encoding: .utf8) ==
					"passed"
				else {
					throw HarnessFailure.assertion("Scenario did not complete")
				}
				try completed.append(String(
					contentsOf: scenario.appendingPathComponent("scenario-kind"),
					encoding: .utf8
				))
			}
			let expected = ScenarioKind.allCases
				.flatMap { $0.hasFixtureTest ? [$0.rawValue, "fixture.\($0.rawValue)"] : [$0.rawValue] }
			guard completed.sorted() == expected.sorted() else {
				throw HarnessFailure.assertion("Matrix completion missing, duplicated, or unexpected")
			}
			await sampleOwnedApp()
			if try await cleanup() {
				throw HarnessFailure.assertion("Owned processes required cleanup")
			}
			try HarnessFiles.write("0", to: "exit-status")
		} catch {
			await sampleOwnedApp()
			let cleanupRequired = await (try? cleanup()) ?? true
			if cleanupRequired {
				try? HarnessFiles.write("1", to: "exit-status")
				throw HarnessFailure.assertion("Run failed and owned processes required cleanup")
			}
			let status = if case HarnessFailure.setup = error {
				"2"
			} else {
				"1"
			}
			try? HarnessFiles.write(status, to: "exit-status")
			throw error
		}
	}

	private static func commands(deadline: Double) async throws {
		let repo = try HarnessFiles.required("E2E_REPO_ROOT")
		let app = try HarnessFiles.required("E2E_APP")
		let helper = try HarnessFiles.required("E2E_HELPER")
		var arguments = try [
			"-project", repo + "/Glasstual.xcodeproj", "-scheme", "GlasstualE2E",
			"-configuration", "Debug", "-destination", "platform=macOS,arch=arm64",
			"-derivedDataPath", HarnessFiles.required("E2E_DERIVED_DATA"), "-parallel-testing-enabled", "NO",
		]
		// Only values that are identical on every run may become build settings:
		// a per-run value changes the build description and forces a full rebuild.
		// The test bundle reads the run directory from $E2E_OUTPUT/current-run.
		for key in ["E2E_APP", "E2E_HELPER", "E2E_FIXTURE", "E2E_OUTPUT", "E2E_DISPOSABLE_USER_CONSENT"] {
			try arguments.append("\(key)=\(HarnessFiles.required(key))")
		}
		try await command(
			"/usr/bin/xcrun",
			["xcodebuild"] + arguments + ["build-for-testing"],
			log: "build",
			deadline: min(deadline, HarnessFiles.now + 600)
		)
		try await command(
			"/usr/bin/codesign",
			["--verify", "--deep", "--strict", app],
			log: "app-signature",
			deadline: min(deadline, HarnessFiles.now + 15)
		)
		try await command(
			"/usr/bin/codesign",
			["--verify", "--strict", helper],
			log: "helper-signature",
			deadline: min(deadline, HarnessFiles.now + 15)
		)
		guard FileManager.default.fileExists(atPath: app + "/Contents/XPCServices/IRC Connection Host.xpc") else {
			throw HarnessFailure.setup("Embedded IRC XPC service missing")
		}
		try await command(
			"/usr/bin/codesign",
			["-d", "--entitlements", ":-", app],
			log: "entitlements",
			deadline: min(deadline, HarnessFiles.now + 15)
		)
		let entitlements = try Data(contentsOf: HarnessFiles.root.appendingPathComponent("entitlements.log"))
		guard let plist = try PropertyListSerialization.propertyList(from: entitlements, format: nil) as? [String: Any],
		      plist["com.apple.security.app-sandbox"] as? Bool == true
		else { throw HarnessFailure.setup("App sandbox entitlement missing") }
		try await command(helper, ["preflight"], log: "preflight", deadline: min(deadline, HarnessFiles.now + 10))
		try await command("/usr/bin/xcrun", ["xcodebuild"] + arguments + [
			"-resultBundlePath", HarnessFiles.root.appendingPathComponent("GlasstualE2E.xcresult").path,
			"test-without-building",
		], log: "test", deadline: min(deadline, HarnessFiles.now + 2340))
	}

	private static func command(
		_ executable: String,
		_ arguments: [String],
		log: String,
		deadline: Double
	) async throws {
		let process = Process()
		process.executableURL = URL(fileURLWithPath: executable)
		process.arguments = arguments
		try HarnessFiles.write("", to: log + ".log")
		try HarnessFiles.write("", to: log + ".stderr.log")
		let output = try FileHandle(forWritingTo: HarnessFiles.root.appendingPathComponent(log + ".log"))
		let errors = try FileHandle(forWritingTo: HarnessFiles.root.appendingPathComponent(log + ".stderr.log"))
		defer { try? output.close(); try? errors.close() }
		process.standardOutput = output
		process.standardError = errors
		try HarnessFiles.launch(process)
		while process.isRunning {
			try checkDeadlines(deadline)
			try await Task.sleep(for: .milliseconds(100))
		}
		try HarnessFiles.unregister(process.processIdentifier)
		try checkDeadlines(deadline)
		guard process.terminationReason == .exit, process.terminationStatus == 0 else {
			if log == "preflight",
			   process.terminationStatus == 2
			{
				throw HarnessFailure.setup("AX preflight failed; see preflight logs")
			}
			throw HarnessFailure.assertion("Child command failed: \(log)")
		}
	}

	private static func checkDeadlines(_ deadline: Double) throws {
		guard !interrupted else { throw HarnessFailure.assertion("Supervisor interrupted") }
		var expired = HarnessFiles.now >= deadline
		for scenario in try scenarioDirectories() {
			if FileManager.default.fileExists(atPath: scenario.appendingPathComponent("scenario-failed").path) {
				throw HarnessFailure.assertion("A matrix scenario failed")
			}
			for name in [
				"scenario-deadline",
				"recovery-deadline",
				"ax-deadline",
				"disconnect-deadline",
				"quit-deadline",
				"probe-deadline",
				"relaunch-ax-deadline",
				"relaunch-probe-deadline",
				"relaunch-quit-deadline",
			] {
				let content: String
				do {
					content = try String(contentsOf: scenario.appendingPathComponent(name), encoding: .utf8)
				} catch let error as CocoaError where error.code == .fileReadNoSuchFile {
					continue
				}
				guard let end = Double(content), end.isFinite else {
					throw HarnessFailure.assertion("Invalid child deadline")
				}
				// Reporting/cleanup tolerance only. The driver still requires completion within the exact deadline.
				expired = expired || HarnessFiles.now > end + 0.25
			}
		}
		if expired {
			try HarnessFiles.write("External monotonic deadline exceeded", to: "timeout.txt")
			throw HarnessFailure.assertion("External watchdog timeout")
		}
	}

	private static func scenarioDirectories() throws -> [URL] {
		let directories = try FileManager.default.contentsOfDirectory(
			at: HarnessFiles.runRoot.appendingPathComponent("scenarios"), includingPropertiesForKeys: nil
		)
		guard directories.count <= 32 else { throw HarnessFailure.assertion("Too many scenario directories") }
		return directories
	}

	private static func sampleOwnedApp() async {
		for directory in (try? scenarioDirectories()) ?? [] {
			for prefix in ["", "relaunch-"] {
				guard let record = try? String(
					contentsOf: directory.appendingPathComponent(prefix + "app-process"),
					encoding: .utf8
				),
					let pidText = record.split(separator: " ").first, let pid = Int32(pidText), pid > 1,
					let birth = HarnessFiles.identity(pid), record == "\(pid) \(birth)",
					birth == (try? HarnessFiles.read("owned/\(pid)")) else { continue }
				let sampler = Process()
				sampler.executableURL = URL(fileURLWithPath: "/usr/bin/sample")
				sampler.arguments = [String(pid), "1", "10", "-file", "/dev/stdout"]
				let pipe = Pipe()
				sampler.standardOutput = pipe
				sampler.standardError = FileHandle.nullDevice
				let fd = pipe.fileHandleForReading.fileDescriptor
				_ = fcntl(fd, F_SETFL, O_NONBLOCK)
				do {
					try HarnessFiles.launch(sampler)
					try pipe.fileHandleForWriting.close()
					let deadline = HarnessFiles.now + 3
					var captured = Data()
					while HarnessFiles.now < deadline {
						var buffer = [UInt8](repeating: 0, count: 4096)
						let count = Darwin.read(fd, &buffer, buffer.count)
						if count > 0, captured.count < 131_072 {
							captured.append(contentsOf: buffer.prefix(min(count, 131_072 - captured.count)))
						}
						if count == 0, !sampler.isRunning {
							break
						}
						try await Task.sleep(for: .milliseconds(25))
					}
					if sampler.isRunning {
						sampler.terminate()
					}
					if sampler.isRunning {
						kill(sampler.processIdentifier, SIGKILL)
					}
					let status = sampler.isRunning ? "sampler cleanup pending" : "sampler status \(sampler.terminationStatus)"
					try Data((status + "\n" + ProcessDiagnostics.summary(captured)).utf8)
						.write(to: directory.appendingPathComponent(prefix + "process-sample.txt"), options: .atomic)
					if !sampler.isRunning {
						try HarnessFiles.unregister(sampler.processIdentifier)
					}
				} catch {
					try? Data("Bounded sample unavailable".utf8)
						.write(to: directory.appendingPathComponent(prefix + "process-sample.txt"))
				}
				try? pipe.fileHandleForReading.close()
				return
			}
		}
	}

	private static func cleanup() async throws -> Bool {
		var required = false
		for signalNumber in [SIGTERM, SIGKILL] {
			let records = try FileManager.default.contentsOfDirectory(
				at: HarnessFiles.root.appendingPathComponent("owned"),
				includingPropertiesForKeys: nil
			)
			for record in records {
				guard let pid = Int32(record.lastPathComponent), pid > 1,
				      let identity = HarnessFiles.identity(pid),
				      identity == (try? String(contentsOf: record, encoding: .utf8))
				else { continue }
				required = true
				try HarnessFiles.write(
					"Owned process required termination; signal \(signalNumber)",
					to: "cleanup-failure.txt"
				)
				kill(pid, signalNumber)
			}
			if signalNumber == SIGTERM, required {
				try await Task.sleep(for: .seconds(2))
			}
		}
		return required
	}
}
