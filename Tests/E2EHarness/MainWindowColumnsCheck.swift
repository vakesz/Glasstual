import CoreGraphics
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

	static func run(_ context: ScenarioContext) async throws {
		try await expect("member list opens inside the window", context) { columns in
			guard let list = columns.memberList else { return false }
			return abs(columns.sidebar.width - sidebarWidth) < tolerance
				&& abs(list.width - memberListWidth) < tolerance
				&& columns.sidebar.minX >= columns.window.minX - tolerance
				&& list.maxX <= columns.window.maxX + tolerance
				&& columns.transcript.minX >= columns.sidebar.maxX - tolerance
				&& columns.transcript.maxX <= list.minX + tolerance
				&& columns.transcript.width >= conversationMinimumWidth
		}
		try await context.driver.menu("toggleMemberList")
		try await expect("transcript takes the member list's width back", context) { columns in
			columns.memberList == nil
				&& abs(columns.transcript.maxX - columns.window.maxX) < tolerance
				&& columns.transcript.minX >= columns.sidebar.maxX - tolerance
		}
		try await context.driver.menu("toggleMemberList")
		try await expect("member list opens again at its width", context) { columns in
			guard let list = columns.memberList else { return false }
			return abs(list.width - memberListWidth) < tolerance
				&& list.maxX <= columns.window.maxX + tolerance
				&& columns.transcript.maxX <= list.minX + tolerance
		}
	}

	/// Waits for the columns to satisfy `condition`, keeping the last
	/// measurement as evidence for a failure.
	private static func expect(
		_ description: String,
		_ context: ScenarioContext,
		_ condition: (Columns) -> Bool
	) async throws {
		var last = "not measured"
		do {
			try await context.until(description) {
				guard let columns = try measure(context.driver) else { return false }
				last = columns.description
				return condition(columns)
			}
		} catch {
			context.note("main window columns: \(last)")
			throw error
		}
	}

	private static func measure(_ driver: AXDriver) throws -> Columns? {
		guard let window = try driver.window(AXID.mainWindow),
		      let windowFrame = try driver.frame(window),
		      let sidebar = try driver.find(AXID.sidebar, in: window),
		      let sidebarFrame = try driver.frame(sidebar),
		      let transcript = try driver.find(AXID.transcript, in: window),
		      let transcriptFrame = try driver.frame(transcript)
		else { return nil }
		let memberList = try driver.find(AXID.memberList, in: window)
		let memberListFrame = try memberList.flatMap { try driver.frame($0) }
		return Columns(
			window: windowFrame,
			sidebar: sidebarFrame,
			transcript: transcriptFrame,
			memberList: memberListFrame.flatMap { $0.width > 0 ? $0 : nil }
		)
	}
}
