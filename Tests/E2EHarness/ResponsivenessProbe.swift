import AppKit
import ApplicationServices
import Foundation

@MainActor
enum ResponsivenessProbe {
	static func run() async throws {
		let prefix = ProcessInfo.processInfo.environment["E2E_PROBE_PREFIX"] ?? ""
		guard ["", "relaunch-"].contains(prefix) else { throw HarnessFailure.setup("Invalid probe phase") }
		let record = try HarnessFiles.read(prefix + "app-process").split(separator: " ").map(String.init)
		guard record.count == 2, let pid = Int32(record[0]),
		      HarnessFiles.identity(pid) == record[1], let application = NSRunningApplication(processIdentifier: pid)
		else { throw HarnessFailure.assertion("Probe app identity mismatch") }
		let driver = AccessibilityDriver(application: application)
		var count = 0
		while try !HarnessFiles.exists(prefix + "probe-stop") {
			guard HarnessFiles.identity(pid) == record[1], !application.isTerminated else {
				throw HarnessFailure.assertion("App exited while responsiveness probe was active")
			}
			let start = HarnessFiles.now
			let deadline = start + 2
			try HarnessFiles.write(String(deadline), to: prefix + "probe-deadline")
			var answered = false
			repeat {
				if let windows = try driver.value(
					driver.root,
					kAXWindowsAttribute,
					deadline: deadline
				) as? [AXUIElement],
					let window = windows.first,
					try driver.value(window, kAXTitleAttribute, deadline: deadline) is String
				{
					answered = true
					break
				}
				try await Task.sleep(for: .milliseconds(50))
			} while HarnessFiles.now < deadline
			guard answered else {
				throw HarnessFailure.assertion("Independent AX responsiveness probe failed")
			}
			try HarnessFiles.check(deadline)
			count += 1
			try HarnessFiles.write("\(count) \(HarnessFiles.now - start)", to: prefix + "probe-evidence")
			// Keep a deadline armed even while sleeping or if the probe process dies.
			try HarnessFiles.write(String(HarnessFiles.now + 2), to: prefix + "probe-deadline")
			try await Task.sleep(for: .milliseconds(500))
		}
		try HarnessFiles.remove(prefix + "probe-deadline")
		try HarnessFiles.write("stopped", to: prefix + "probe-complete")
	}
}
