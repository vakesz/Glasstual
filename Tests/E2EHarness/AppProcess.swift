import AppKit
import Foundation

/** One launch of the application under test, addressed only by its pid.

 Other copies of the application, such as unit-test hosts or the person's own,
 may run at the same time; nothing here looks them up or touches them. The
 application is asked to come forward once, when its first window is up, so a
 person watching sees it. Nothing depends on it staying there: every step is an
 Accessibility request to this pid, which works whichever application has the
 keyboard. */
final class AppProcess {
	let process: Process
	let pid: pid_t
	let driver: AXDriver
	let launchedAt: Date
	/// The files the application's standard output and error go to.
	let standardOutput: URL
	let standardError: URL

	private init(process: Process, standardOutput: URL, standardError: URL) {
		self.process = process
		pid = process.processIdentifier
		launchedAt = Date()
		self.standardOutput = standardOutput
		self.standardError = standardError
		driver = AXDriver(pid: process.processIdentifier, isAlive: { process.isRunning })
	}

	var isRunning: Bool {
		process.isRunning
	}

	/// `exit 0`, `exit 3` or `signal 9`, once the process has exited.
	var exitDescription: String {
		guard process.isRunning == false else { return "running" }
		return switch process.terminationReason {
		case .exit: "exit \(process.terminationStatus)"
		case .uncaughtSignal: "signal \(process.terminationStatus)"
		@unknown default: "unknown \(process.terminationStatus)"
		}
	}

	var exitedCleanly: Bool {
		process.isRunning == false && process.terminationReason == .exit && process.terminationStatus == 0
	}

	/** Starts the application in end-to-end mode against `sandbox` and waits
	 for its first window. `seed` is the settings a first launch starts from;
	 a relaunch passes none and reads what the previous launch kept. */
	static func launch(
		_ app: AppBundle,
		sandbox: RunSandbox,
		seed: Data?,
		keepsState: Bool,
		logs: URL,
		label: String
	) async throws -> AppProcess {
		let standardOutput = logs.appendingPathComponent("\(label)-stdout.txt")
		let standardError = logs.appendingPathComponent("\(label)-stderr.txt")
		for file in [standardOutput, standardError] {
			guard FileManager.default.createFile(atPath: file.path, contents: nil) else {
				throw HarnessFailure.setup("Cannot create \(file.path)")
			}
		}
		let process = Process()
		process.executableURL = app.executable
		process.arguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-ApplePersistenceIgnoreState", "YES"]
		process.environment = sandbox.environment(seed: seed, keepsState: keepsState)
		process.standardOutput = try FileHandle(forWritingTo: standardOutput)
		process.standardError = try FileHandle(forWritingTo: standardError)
		process.standardInput = FileHandle.nullDevice
		do {
			try process.run()
		} catch {
			throw HarnessFailure.setup("Cannot start \(app.executable.path): \(error.localizedDescription)")
		}
		let launched = AppProcess(process: process, standardOutput: standardOutput, standardError: standardError)
		try await launched.becomeReady()
		return launched
	}

	/// Waits for the first window, asks the application to come forward once
	/// and starts measuring responsiveness.
	private func becomeReady() async throws {
		driver.observeChanges()
		let running = try await driver.until("application registers with the window server", timeout: .seconds(30)) {
			NSRunningApplication(processIdentifier: pid).flatMap { $0.isFinishedLaunching ? $0 : nil }
		}
		try await driver.until("first window", timeout: .seconds(30)) { try driver.windows().isEmpty == false }
		running.activate()
		driver.armResponsiveness()
	}

	/// Chooses Quit and requires the process to exit with status zero within
	/// five seconds. Returns how long that took.
	@discardableResult
	func quit() async throws -> Duration {
		guard isRunning else { throw HarnessFailure.assertion("The application exited before Quit (\(exitDescription))") }
		let pressed = try await driver.menu("quit")
		driver.currentStep = "Quit exits the application"
		try await Wait.until(driver.currentStep, timeout: .seconds(5), signal: driver.signal) {
			process.isRunning == false
		}
		driver.stopObserving()
		guard exitedCleanly else {
			throw HarnessFailure.assertion("Quit ended the application with \(exitDescription)")
		}
		return ContinuousClock.now - pressed
	}

	/// Teardown for a launch a scenario left running: Quit, then SIGTERM, then
	/// SIGKILL, each by pid and each bounded.
	func stop() async {
		driver.stopObserving()
		guard isRunning else { return }
		if let item = try? driver.menuItem("quit"), (try? driver.press(item)) != nil {
			_ = try? await Wait.until("Quit during teardown", timeout: .seconds(5)) { process.isRunning == false }
		}
		for (signal, grace) in [(SIGTERM, Duration.seconds(3)), (SIGKILL, Duration.seconds(3))] where isRunning {
			kill(pid, signal)
			_ = try? await Wait.until("exit after signal \(signal)", timeout: grace) { process.isRunning == false }
		}
	}
}
