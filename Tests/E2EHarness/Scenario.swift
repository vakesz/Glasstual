import AppKit
import Darwin
import Foundation

@MainActor
enum Scenario {
	private struct Session {
		let app: Process
		let application: NSRunningApplication
		let peer: Process?
	}

	static func run() async throws {
		let kind = try ScenarioKind.current
		let session = try await launch(kind: kind)
		let driver = AccessibilityDriver(application: session.application)
		do {
			if kind.onboarding {
				try await OnboardingScenario.run(
					first: session.app,
					application: session.application,
					kind: kind,
					peer: session.peer
				)
			} else {
				guard let peer = session.peer else { throw HarnessFailure.assertion("Scenario peer missing") }
				try await exercise(
					kind: kind,
					appProcess: session.app,
					application: session.application,
					peer: peer,
					driver: driver
				)
			}
			if kind == .historyRelaunch {
				try await HistoryRelaunchScenario.run(previous: session.app)
			}
		} catch {
			// A failed case must not leave an app, peer or probe alive: the next
			// case refuses to start while an instance of the bundle is running.
			if session.app.isRunning {
				try? driver.saveSnapshot()
			}
			await AppSession.terminateOwned()
			throw error
		}
		try HarnessFiles.write("passed", to: "scenario-passed")
	}

	private static func launch(kind: ScenarioKind) async throws -> Session {
		guard let watchdog = try Int32(String(
			contentsOf: HarnessFiles.runRoot.appendingPathComponent("watchdog.pid"),
			encoding: .utf8
		)
		.trimmingCharacters(in: .whitespacesAndNewlines)),
			watchdog > 1,
			try HarnessFiles.identity(watchdog) == String(
				contentsOf: HarnessFiles.runRoot.appendingPathComponent("watchdog.identity"),
				encoding: .utf8
			)
		else { throw HarnessFailure.setup("Independent script watchdog is not running") }
		let appURL = try URL(fileURLWithPath: HarnessFiles.required("E2E_APP"))
		guard let bundle = Bundle(url: appURL), let bundleID = bundle.bundleIdentifier else {
			throw HarnessFailure.setup("Invalid app bundle")
		}
		guard let executable = bundle.executableURL else { throw HarnessFailure.setup("App executable missing") }
		let binary = try Data(contentsOf: executable, options: .mappedIfSafe)
		guard binary.range(of: Data("GLASSTUAL_UI_REVIEW_SUITE".utf8)) != nil,
		      binary.range(of: Data("GLASSTUAL_UI_REVIEW_DIRECTORY".utf8)) != nil
		else { throw HarnessFailure.setup("Use a Debug app with the existing review suite/directory overrides") }
		guard NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty else {
			throw HarnessFailure.setup("Quit existing instances of this app before E2E; they will not be touched")
		}
		var peer: Process?
		var port = 0
		if kind != .onboardingSkip {
			let process = Process()
			process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
			process.arguments = ["peer"]
			try HarnessFiles.launch(process)
			AppSession.track(process)
			peer = process
			let portDeadline = HarnessFiles.now + 10
			while try !HarnessFiles.exists("port"), HarnessFiles.now < portDeadline, process.isRunning {
				try await Task.sleep(for: .milliseconds(100))
			}
			guard let published = try Int(HarnessFiles.read("port")), (1 ... 65535).contains(published) else {
				throw HarnessFailure.setup("Loopback peer did not publish a port")
			}
			port = published
		}
		let token = "e2e-" + UUID().uuidString.lowercased()
		let suite = "com.vakesz.glasstual." + token
		try seed(bundleID: bundleID, suite: suite, port: port, kind: kind)
		let appProcess = Process()
		appProcess.executableURL = executable
		appProcess.arguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
		// Do not inherit test-runner DYLD/XCTest injection variables into the production executable.
		appProcess.environment = ProcessInfo.processInfo.environment.filter {
			["HOME", "USER", "LOGNAME", "PATH", "TMPDIR"].contains($0.key)
		}.merging(["GLASSTUAL_UI_REVIEW_SUITE": suite, "GLASSTUAL_UI_REVIEW_DIRECTORY": token]) { _, value in value }
		appProcess.standardOutput = FileHandle.nullDevice
		appProcess.standardError = FileHandle.nullDevice
		try HarnessFiles.launch(appProcess)
		AppSession.track(appProcess)
		guard let birth = HarnessFiles.identity(appProcess.processIdentifier) else {
			throw HarnessFailure.assertion("App identity missing")
		}
		try HarnessFiles.write("\(appProcess.processIdentifier) \(birth)", to: "app-process")
		let applicationDeadline = HarnessFiles.now + 10
		var runningApplication: NSRunningApplication?
		while runningApplication == nil, appProcess.isRunning, HarnessFiles.now < applicationDeadline {
			runningApplication = NSRunningApplication(processIdentifier: appProcess.processIdentifier)
			if runningApplication == nil {
				try await Task.sleep(for: .milliseconds(100))
			}
		}
		guard let application = runningApplication
		else { throw HarnessFailure.assertion("Production app failed to launch") }
		return Session(app: appProcess, application: application, peer: peer)
	}

	private static func exercise(kind: ScenarioKind, appProcess: Process, application: NSRunningApplication,
	                             peer: Process, driver: AccessibilityDriver) async throws
	{
		let originalPID = application.processIdentifier
		try await driver.waitForConnectionStatus(connected: false)
		let probe = try await AppSession.startProbe(prefix: "", driver: driver)
		for rejection in 0 ..< kind.rejectionCount {
			let recoveryDeadline = HarnessFiles.now + 30
			try HarnessFiles.write(String(rejection + 1), to: "recovery-iteration")
			try HarnessFiles.write(String(recoveryDeadline), to: "recovery-deadline")
			try await driver.menu("Connect", in: "Server")
			try await driver.waitForTranscript("E2E_REGISTRATION_REJECTED", occurrences: rejection + 1)
			try await driver.waitForConnectionStatus(connected: false)
			try await Task.sleep(for: .seconds(1))
			try HarnessFiles.check(recoveryDeadline)
			try HarnessFiles.write("disconnected", to: "recovery-complete-\(rejection + 1)")
			try HarnessFiles.remove("recovery-deadline")
		}
		try await driver.menu("Connect", in: "Server")
		if kind == .tlsRejectRetry {
			try await driver.certificate(answer: nil)
			try await Task.sleep(for: .seconds(3))
			try await driver.certificate(answer: false)
			try await driver.waitForConnectionStatus(connected: false)
			try await driver.wait("TLS rejected without IRC") { _ in try HarnessFiles.exists("tls-rejected") }
			try await driver.menu("Connect", in: "Server")
		}
		if kind.secured, kind != .tlsStall {
			try await driver.certificate(answer: nil)
			try await Task.sleep(for: .seconds(3))
			try await driver.certificate(answer: true)
		}
		if kind == .tlsStall {
			try await driver.wait("TLS ClientHello held unanswered") { _ in try HarnessFiles.exists("tls-stalled") }
			try await Task.sleep(for: .seconds(4))
		} else {
			try await driver.waitForTranscript("E2E_TRANSCRIPT_READY")
			try await driver.waitForConnectionStatus(connected: true)
			try await driver.wait("peer observed fixture PONG") { _ in try HarnessFiles.exists("pong-wire") }
		}
		guard appProcess.isRunning, !application.isTerminated, application.processIdentifier == originalPID else {
			throw HarnessFailure.assertion("Retry did not preserve the app process")
		}
		try await channelActions(kind: kind, driver: driver)
		try await Task.sleep(for: .seconds(2))
		var shutdownSeconds = 0.0
		if !kind.connectedQuit {
			let start = try await driver.menu("Disconnect", in: "Server")
			try await driver.waitForConnectionStatus(connected: false, deadline: start + 5)
			try await driver.wait("peer closed after Disconnect", deadline: start + 5) { _ in
				try HarnessFiles.exists("peer-complete") && !peer.isRunning
			}
			shutdownSeconds = HarnessFiles.now - start
			try HarnessFiles.check(start + 5)
			try HarnessFiles.remove("disconnect-deadline")
		}
		if kind == .settingsSnapshot {
			try await SettingsSnapshotScenario.run(driver: driver)
		}
		try driver.saveSnapshot()
		try await AppSession.stopProbe(probe, prefix: "", driver: driver)
		if kind.connectedQuit {
			try await driver.waitForConnectionStatus(connected: true, channel: kind.finalChannel)
		}
		let quitSeconds = try await AppSession.quitAndVerify(appProcess, driver: driver, prefix: "") {
			try !peer.isRunning && HarnessFiles.exists("peer-complete")
		}
		if kind.connectedQuit {
			shutdownSeconds = quitSeconds
		}
		guard peer.terminationReason == .exit,
		      peer.terminationStatus == 0 else { throw HarnessFailure.assertion("Peer failed") }
		try HarnessFiles.unregister(peer.processIdentifier)
		AppSession.release(peer)
		try saveEvidence(kind: kind, originalPID: originalPID, finalPID: application.processIdentifier,
		                 shutdownSeconds: shutdownSeconds, appExitStatus: appProcess.terminationStatus)
	}

	private static func channelActions(kind: ScenarioKind, driver: AccessibilityDriver) async throws {
		if kind == .pluginSmiley || kind == .burstResponsiveness {
			try await PluginAndBurstScenarios.run(kind: kind, driver: driver)
		} else if kind.dcc {
			try await DCCScenario.run(kind: kind, driver: driver)
		} else if kind.messaging {
			try await driver.typeAndSend("/join #e2e")
			try await driver.waitForTranscript("E2E_CHANNEL_READY")
			try await driver.typeAndSend("E2E_TYPED_MESSAGE")
			try await driver.waitForTranscript("E2E_SERVER_REPLY")
			try await driver.typeAndSend("fixture: E2E_TYPED_REPLY")
			try await driver.waitForTranscript("E2E_REPLY_ACK")
		} else if kind == .channelDenied {
			try await driver.typeAndSend("/join #other")
			try await driver.waitForTranscript("E2E_OTHER_READY")
			try await driver.typeAndSend("/join #retry")
			try await driver.wait("peer denied JOIN with 477") { _ in try HarnessFiles.exists("denied-join-wire") }
			try await driver.selectChannel("#retry", joined: false)
			try await driver.waitForTranscript("E2E_JOIN_DENIED")
			try await driver.selectChannel("#other", joined: true)
			try await driver.waitForConnectionStatus(connected: true, channel: "#other")
			try await driver.typeAndSend("/msg NickServ IDENTIFY E2E_SYNTHETIC")
			// /msg can select a query; explicitly restore the unrelated active channel before right-clicking.
			try await driver.selectChannel("#other", joined: true)
			try await driver.waitForTranscript("E2E_IDENTIFIED_READY")
			try await driver.waitForConnectionStatus(connected: true, channel: "#other")
			try await driver.contextualJoin("#retry", whileSelected: "#other")
			try await driver.waitForConnectionStatus(connected: true, channel: "#retry")
			try await driver.waitForTranscript("E2E_RETRY_JOINED")
		}
	}

	private static func saveEvidence(kind: ScenarioKind, originalPID: pid_t, finalPID: pid_t,
	                                 shutdownSeconds: Double, appExitStatus: Int32) throws
	{
		let evidence: [String: Any] = [
			"scenario": kind.rawValue, "originalPID": originalPID, "finalPID": finalPID,
			"rejections": kind.rejectionCount, "connectedQuit": kind.connectedQuit,
			"shutdownSeconds": shutdownSeconds, "appExitReason": "exit", "appExitStatus": appExitStatus,
		]
		try JSONSerialization.data(withJSONObject: evidence, options: [.prettyPrinted, .sortedKeys])
			.write(to: HarnessFiles.root.appendingPathComponent("evidence.json"), options: .atomic)
	}

	private static func seed(bundleID: String, suite: String, port: Int, kind: ScenarioKind) throws {
		let preferences = FileManager.default.homeDirectoryForCurrentUser
			.appendingPathComponent("Library/Containers/\(bundleID)/Data/Library/Preferences", isDirectory: true)
		guard FileManager.default.fileExists(atPath: preferences.path) else {
			throw HarnessFailure
				.setup("App sandbox container missing; provision the Debug app in the disposable login first")
		}
		let fixtureURL = try URL(fileURLWithPath: HarnessFiles.required("E2E_FIXTURE"))
		let data = try Data(contentsOf: fixtureURL)
		guard var fixture = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
		      var clients = fixture["World Controller Client Configurations"] as? [[String: Any]], clients.count == 1
		else { throw HarnessFailure.setup("Malformed synthetic startup fixture") }
		clients[0]["uniqueIdentifier"] = UUID().uuidString
		clients[0]["serverList"] = [[
			"uniqueIdentifier": UUID().uuidString,
			"serverAddress": "127.0.0.1", "serverPort": port, "prefersSecuredConnection": kind.secured,
		]]
		fixture["World Controller Client Configurations"] = kind.onboarding ? [] : clients
		if kind.onboarding {
			fixture["Onboarding -> Completed"] = false
			fixture["DefaultIdentity -> Nickname"] = ""
			fixture["DefaultIdentity -> Realname"] = ""
			fixture["DefaultIdentity -> Username"] = "e2euser"
		}
		let encoded = try PropertyListSerialization.data(fromPropertyList: fixture, format: .xml, options: 0)
		try encoded.write(to: preferences.appendingPathComponent(suite + ".plist"), options: .atomic)
		try HarnessFiles.write(suite, to: "scratch-suite.txt")
	}
}
