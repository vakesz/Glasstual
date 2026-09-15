import AppKit
import Foundation

enum HistoryRelaunchScenario {
	static func run(previous: Process) async throws {
		guard !previous.isRunning, previous.terminationReason == .exit, previous.terminationStatus == 0 else {
			throw HarnessFailure.assertion("History relaunch requires a clean first Quit")
		}
		let (app, application) = try await AppSession.relaunch(previous)
		let driver = AccessibilityDriver(application: application, artifactPrefix: "relaunch-")
		defer {
			if app.isRunning {
				try? driver.saveSnapshot()
			}
		}
		try await driver.wait("relaunch main window") { deadline in
			try driver.identified("main-window", from: driver.root, deadline: deadline) != nil
		}
		let probe = try await AppSession.startProbe(driver: driver)
		try await driver.selectChannel("#e2e", joined: false)
		try await driver.waitForConnectionStatus(connected: false, channel: "#e2e")
		for marker in ["E2E_TYPED_MESSAGE", "E2E_SERVER_REPLY", "E2E_REPLY_ACK"] {
			try await driver.waitForTranscript(marker)
		}
		try await AppSession.awaitProbeSamples(3, driver: driver)
		try await AppSession.stopProbe(probe, driver: driver)
		let quitSeconds = try await AppSession.quitAndVerify(app, driver: driver)
		let evidence: [String: Any] = ["firstPID": previous.processIdentifier, "relaunchPID": app.processIdentifier,
		                               "exitReason": app.terminationReason.evidenceName,
		                               "exitStatus": app.terminationStatus, "quitSeconds": quitSeconds]
		try JSONSerialization.data(withJSONObject: evidence, options: [.prettyPrinted, .sortedKeys])
			.write(to: HarnessFiles.root.appendingPathComponent("relaunch-evidence.json"), options: .atomic)
	}
}
