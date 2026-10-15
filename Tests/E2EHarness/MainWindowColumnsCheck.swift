import ApplicationServices
import Foundation

/** The main window's three columns, measured in the running app.

 The sidebar and the member list open at their stored widths, and all three
 columns stay inside the window, with the transcript between the other two.
 Closing the member list gives its width back to the transcript. A unit
 test's window presents the inspector differently, so this is the check
 for where the columns actually sit. */
enum MainWindowColumnsCheck {
	/** The defaults of `SettingsKeys.MainWindow.sidebarWidth` and
	 `memberListWidth`. The harness drives the shipped binary rather than
	 linking the application, so it holds the literals; the scratch suite
	 stores no width, so the columns open at these. */
	private static let sidebarWidth: CGFloat = 220
	private static let memberListWidth: CGFloat = 200
	/// `MainWindowConstants.conversationMinimumWidth`.
	private static let conversationMinimumWidth: CGFloat = 360
	private static let tolerance: CGFloat = 1

	private struct Columns: CustomStringConvertible {
		let window: CGRect
		let sidebar: CGRect
		let transcript: CGRect
		let memberList: CGRect?

		var description: String {
			"window \(window) sidebar \(sidebar) transcript \(transcript) member list \(memberList.map { "\($0)" } ?? "closed")"
		}
	}

	static func run(driver: AccessibilityDriver) async throws {
		try await expect("member list opens inside the window", driver: driver) { columns in
			guard let list = columns.memberList else { return false }
			return abs(columns.sidebar.width - sidebarWidth) < tolerance
				&& abs(list.width - memberListWidth) < tolerance
				&& columns.sidebar.minX >= columns.window.minX - tolerance
				&& list.maxX <= columns.window.maxX + tolerance
				&& columns.transcript.minX >= columns.sidebar.maxX - tolerance
				&& columns.transcript.maxX <= list.minX + tolerance
				&& columns.transcript.width >= conversationMinimumWidth
		}
		try await driver.menu("Hide Member List", in: "View")
		try await expect("transcript takes the member list's width back", driver: driver) { columns in
			columns.memberList == nil
				&& abs(columns.transcript.maxX - columns.window.maxX) < tolerance
				&& columns.transcript.minX >= columns.sidebar.maxX - tolerance
		}
		try await driver.menu("Show Member List", in: "View")
		try await expect("member list opens again at its width", driver: driver) { columns in
			guard let list = columns.memberList else { return false }
			return abs(list.width - memberListWidth) < tolerance
				&& list.maxX <= columns.window.maxX + tolerance
				&& columns.transcript.maxX <= list.minX + tolerance
		}
	}

	/// Waits for the columns to satisfy `condition`, keeping the last
	/// measurement as evidence for a failure.
	private static func expect(_ description: String, driver: AccessibilityDriver,
	                           _ condition: (Columns) -> Bool) async throws
	{
		try await driver.wait(description) { deadline in
			guard let columns = try measure(driver: driver, deadline: deadline) else { return false }
			try HarnessFiles.write(columns.description, to: "main-window-columns.txt")
			return condition(columns)
		}
	}

	private static func measure(driver: AccessibilityDriver, deadline: Double) throws -> Columns? {
		guard let window = try driver.identified("main-window", from: driver.root, deadline: deadline),
		      let windowFrame = try driver.frame(window, deadline: deadline),
		      let sidebar = try driver.identified("sidebar", from: window, deadline: deadline),
		      let sidebarFrame = try driver.frame(sidebar, deadline: deadline),
		      let transcript = try driver.identified("channel-transcript", from: window, deadline: deadline),
		      let transcriptFrame = try driver.frame(transcript, deadline: deadline)
		else { return nil }
		let memberList = try driver.identified("member-list", from: window, deadline: deadline)
		let memberListFrame = try memberList.flatMap { try driver.frame($0, deadline: deadline) }
		return Columns(
			window: windowFrame,
			sidebar: sidebarFrame,
			transcript: transcriptFrame,
			memberList: memberListFrame.flatMap { $0.width > 0 ? $0 : nil }
		)
	}
}
