import AppKit
import Darwin
import Foundation

/// The launch, probe, Quit and relaunch steps every GUI scenario repeats, plus
/// the ownership ledger the failure path has to unwind. A scenario that throws
/// must leave no app, peer or probe behind: the next case refuses to start while
/// another instance of the bundle is running.
@MainActor
enum AppSession {
	private static var owned: [Process] = []

	/// Record a process this helper launched so a failure can tear it down.
	static func track(_ process: Process) {
		owned.append(process)
	}

	/// Stop tracking a process that has already exited and been unregistered.
	static func release(_ process: Process) {
		owned.removeAll { $0 === process }
	}

	/// Terminate and unregister everything still tracked. Only the failure path
	/// calls this; a passing scenario has already unregistered each child.
	static func terminateOwned() async {
		let processes = owned
		owned.removeAll()
		let running = processes.filter(\.isRunning)
		for process in running {
			process.terminate()
		}
		if !running.isEmpty {
			try? await Task.sleep(for: .seconds(2))
			for process in running where process.isRunning {
				kill(process.processIdentifier, SIGKILL)
			}
			try? HarnessFiles.write("Scenario failure terminated owned children", to: "scenario-teardown.txt")
		}
		for process in processes {
			try? HarnessFiles.unregister(process.processIdentifier)
		}
	}

	/// Launch the independent responsiveness probe and wait for its first sample.
	static func startProbe(prefix: String, driver: AccessibilityDriver) async throws -> Process {
		let probe = Process()
		probe.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
		probe.arguments = ["probe"]
		probe.environment = ProcessInfo.processInfo.environment
			.merging(["E2E_PROBE_PREFIX": prefix]) { _, new in new }
		try HarnessFiles.write(String(HarnessFiles.now + 5), to: prefix + "probe-deadline")
		try HarnessFiles.launch(probe)
		track(probe)
		try await driver.wait("independent probe started") { _ in try HarnessFiles.exists(prefix + "probe-evidence") }
		return probe
	}

	/// Ask the probe to stop and require a normal exit with its completion marker.
	static func stopProbe(_ probe: Process, prefix: String, driver: AccessibilityDriver) async throws {
		try HarnessFiles.write("stop", to: prefix + "probe-stop")
		try await driver.wait("probe stops normally", deadline: HarnessFiles.now + 3) { _ in !probe.isRunning }
		guard probe.terminationReason == .exit, probe.terminationStatus == 0,
		      try HarnessFiles.exists(prefix + "probe-complete")
		else { throw HarnessFailure.assertion("Independent probe failed") }
		try HarnessFiles.unregister(probe.processIdentifier)
		release(probe)
	}

	/// Press Quit and require the app's actual `.exit`/zero status within five
	/// seconds. `also` adds the case's own required observation, such as the
	/// peer's exact QUIT and EOF, to the same deadline.
	@discardableResult
	static func quitAndVerify(
		_ app: Process,
		driver: AccessibilityDriver,
		prefix: String,
		also: @escaping () throws -> Bool = { true }
	) async throws -> Double {
		guard app.isRunning else { throw HarnessFailure.assertion("App exited before Quit") }
		let start = try await driver.menu("Quit Glasstual", in: "Glasstual")
		try await driver.wait("Quit exits normally with status zero", deadline: start + 5) { _ in
			try !app.isRunning && also()
		}
		let seconds = HarnessFiles.now - start
		try HarnessFiles.check(start + 5)
		guard app.terminationReason == .exit, app.terminationStatus == 0 else {
			throw HarnessFailure.assertion("Quit crashed or exited with nonzero status")
		}
		try HarnessFiles.remove(prefix + "quit-deadline")
		try HarnessFiles.unregister(app.processIdentifier)
		release(app)
		return seconds
	}

	/// Start the same signed executable again with the same scratch suite and
	/// review directory, without reseeding, and require a distinct owned PID.
	static func relaunch(_ previous: Process) async throws -> (app: Process, application: NSRunningApplication) {
		let app = Process()
		app.executableURL = previous.executableURL
		app.arguments = previous.arguments
		app.environment = previous.environment
		app.standardOutput = FileHandle.nullDevice
		app.standardError = FileHandle.nullDevice
		try HarnessFiles.launch(app)
		track(app)
		guard let birth = HarnessFiles.identity(app.processIdentifier),
		      app.processIdentifier != previous.processIdentifier
		else { throw HarnessFailure.assertion("Relaunch did not create a new owned process") }
		try HarnessFiles.write("\(app.processIdentifier) \(birth)", to: "relaunch-app-process")
		let deadline = HarnessFiles.now + 10
		var running: NSRunningApplication?
		while running == nil, app.isRunning {
			try HarnessFiles.check(deadline)
			running = NSRunningApplication(processIdentifier: app.processIdentifier)
			if running == nil {
				try await Task.sleep(for: .milliseconds(100))
			}
		}
		guard let running else { throw HarnessFailure.assertion("Relaunched app failed to start") }
		return (app, running)
	}
}
