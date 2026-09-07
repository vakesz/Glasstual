import AppKit
import ApplicationServices
import Foundation

enum OnboardingScenario {
	static func run(first: Process, application: NSRunningApplication, kind: ScenarioKind,
	                peer: Process?) async throws
	{
		var app = first
		var application = application
		var evidence: [[String: Any]] = []
		for launch in 0 ..< 2 {
			let prefix = launch == 0 ? "" : "relaunch-"
			let driver = AccessibilityDriver(application: application, artifactPrefix: prefix)
			if launch == 0 {
				_ = try await driver.window(titled: "Welcome to Glasstual")
			} else {
				try await driver.wait("relaunch main window ready") { deadline in try driver.identified(
					"main-window",
					from: driver.root,
					deadline: deadline
				) != nil }
			}
			let probe = try await AppSession.startProbe(prefix: prefix, driver: driver)
			if launch == 0 {
				try await complete(kind: kind, driver: driver)
			}
			try await driver.wait("onboarding dismissal completes") { deadline in
				try !welcomePresented(driver, deadline: deadline)
			}
			try await driver.wait("main window after onboarding") { deadline in try driver.identified(
				"main-window",
				from: driver.root,
				deadline: deadline
			) != nil }
			if kind == .onboardingFinish {
				if launch == 0 {
					guard let peer else { throw HarnessFailure.assertion("Onboarding network fixture missing") }
					try await exerciseConnection(driver, peer: peer)
				} else {
					try await driver.wait("persisted local server remains disconnected on relaunch") { deadline in
						guard let window = try driver.identified("main-window", from: driver.root, deadline: deadline)
						else { return false }
						return try driver.text(window, kAXTitleAttribute, deadline: deadline) == "127.0.0.1, Disconnected \u{00B7} e2euser"
					}
				}
			}
			try await verifyCompletedIdentity(driver)
			try await AppSession.stopProbe(probe, prefix: prefix, driver: driver)
			let quitSeconds = try await AppSession.quitAndVerify(app, driver: driver, prefix: prefix)
			evidence.append(["pid": app.processIdentifier, "exitReason": "exit", "exitStatus": app.terminationStatus,
			                 "identityVisible": true, "quitSeconds": quitSeconds])
			if launch == 0 {
				(app, application) = try await AppSession.relaunch(first)
			}
		}
		try JSONSerialization.data(withJSONObject: evidence, options: [.prettyPrinted, .sortedKeys])
			.write(to: HarnessFiles.root.appendingPathComponent("onboarding-evidence.json"), options: .atomic)
	}

	private static func complete(kind: ScenarioKind, driver: AccessibilityDriver) async throws {
		let window = try await driver.window(titled: "Welcome to Glasstual")
		try await driver.fill("onboarding-nickname", with: "e2euser", from: window)
		try await driver.fill("onboarding-real-name", with: "Synthetic E2E User", from: window)
		try await driver.fill("onboarding-alternate-nickname", with: "e2ealternate", from: window)
		try await driver.button("Continue", from: window)
		try await driver.wait("appearance step") { deadline in try driver.named(
			"Look and Feel",
			role: kAXStaticTextRole,
			from: window,
			deadline: deadline
		) != nil }
		if kind == .onboardingSkip {
			try await driver.button("Skip", from: window)
			return
		}
		try await driver.button("Continue", from: window)
		try await driver.wait("Notifications pre-denied by disposable-login operator") { deadline in
			try driver.named(
				"Notifications are turned off for Glasstual in System Settings.",
				role: kAXStaticTextRole,
				from: window,
				deadline: deadline
			) != nil
		}
		try await driver.button("Continue", from: window)
		try await driver.wait("network step has no external selection") { deadline in
			try driver.named(
				"Choose a network or enter a server address.",
				role: kAXStaticTextRole,
				from: window,
				deadline: deadline
			) != nil
		}
		try await driver.wait("filter public network picker to synthetic custom server") { deadline in
			guard let search = try driver.find(from: window, deadline: deadline, matching: {
				try driver.text($0, kAXRoleAttribute, deadline: deadline) == kAXTextFieldRole &&
					driver.text($0, kAXPlaceholderValueAttribute, deadline: deadline) == "Search networks"
			}) else { return false }
			try driver.set(
				search,
				attribute: kAXValueAttribute,
				value: "e2e-loopback-only" as CFString,
				deadline: deadline
			)
			return true
		}
		try await driver.selectRow("Custom Server\u{2026}", from: window)
		try await driver.fill("network-address", with: "127.0.0.1", from: window)
		try await driver.fill("network-port", with: HarnessFiles.read("port"), from: window)
		try await driver.toggle("Use SSL/TLS", to: false, from: window)
		try await driver.toggle("Sign in with SASL", to: false, from: window)
		try await driver.toggle("Connect when finished", to: false, from: window)
		try await driver.button("Finish", from: window)
	}

	private static func exerciseConnection(_ driver: AccessibilityDriver, peer: Process) async throws {
		try await driver.menu("Connect", in: "Server")
		try await driver.waitForTranscript("E2E_TRANSCRIPT_READY")
		try await driver.waitForConnectionStatus(connected: true)
		try await driver
			.wait("newly onboarded identity registered through XPC") { _ in try HarnessFiles.exists("pong-wire") }
		try await driver.typeAndSend("/quit E2E_QUIT")
		try await driver
			.wait("new server closes exact QUIT and EOF") { _ in
				try HarnessFiles.exists("peer-complete") && !peer.isRunning
			}
		guard peer.terminationReason == .exit,
		      peer.terminationStatus == 0 else { throw HarnessFailure.assertion("Onboarding IRC peer failed") }
		try HarnessFiles.unregister(peer.processIdentifier)
		try HarnessFiles.write("custom loopback server registered; manual QUIT observed", to: "onboarding-network")
	}

	private static func welcomePresented(_ driver: AccessibilityDriver, deadline: Double) throws -> Bool {
		let windows = try driver.value(driver.root, kAXWindowsAttribute, deadline: deadline) as? [AXUIElement] ?? []
		return try windows.contains {
			try driver.text($0, kAXTitleAttribute, deadline: deadline) == "Welcome to Glasstual"
		}
	}

	private static func verifyCompletedIdentity(_ driver: AccessibilityDriver) async throws {
		let end = HarnessFiles.now + 3
		repeat {
			try await driver.wait("completed onboarding stays dismissed") { deadline in
				guard try !welcomePresented(driver, deadline: deadline) else {
					throw HarnessFailure.assertion("Completed onboarding was presented again")
				}
				return true
			}
			try await Task.sleep(for: .milliseconds(150))
		} while HarnessFiles.now < end
		let settings = try await driver.settingsWindow()
		try await driver.selectRow("Advanced", from: settings)
		try await driver.selectPreferencePage("Identity", in: settings)
		try await driver.wait("synthetic onboarding identity persisted in Settings") { deadline in
			guard let nickname = try driver.named(
				"Nickname:",
				role: kAXTextFieldRole,
				from: settings,
				deadline: deadline
			),
				let realName = try driver.named(
					"Real name:",
					role: kAXTextFieldRole,
					from: settings,
					deadline: deadline
				) else { return false }
			return try driver.text(nickname, kAXValueAttribute, deadline: deadline) == "e2euser" &&
				driver.text(realName, kAXValueAttribute, deadline: deadline) == "Synthetic E2E User"
		}
		try await driver.closeWindow(settings)
	}
}
