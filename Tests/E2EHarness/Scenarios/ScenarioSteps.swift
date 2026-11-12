import ApplicationServices
import Foundation

/// Steps several scenarios share. Each finds what it needs by identifier and
/// waits through `until`.
extension ScenarioContext {
	/// The network name the seeded session goes by.
	static let network = "E2E"

	/// Starts the peer for `mode` and launches the application seeded with one
	/// network pointing at it.
	@discardableResult
	func launchAgainstPeer(
		_ mode: FixtureMode,
		passiveDCC: Bool = false,
		keepsState: Bool = false
	) async throws -> LoopbackPeer {
		let peer = try await startPeer(mode, passiveDCC: passiveDCC)
		let seed = try Seed.connection(
			corpora: corpora,
			port: peer.port,
			secured: mode.secured,
			validatesCertificate: mode.saslConsent == nil
		)
		try await launch(seed: seed, keepsState: keepsState)
		return peer
	}

	// MARK: - Main window

	func mainWindow() throws -> AXUIElement? {
		try driver.window(AXID.mainWindow)
	}

	func sidebar() throws -> AXUIElement? {
		guard let window = try mainWindow() else { return nil }
		return try driver.find(AXID.sidebar, in: window)
	}

	/// A sidebar row's state: `connected`, `disconnected`, `joined` or `not-joined`.
	func rowState(_ kind: String, _ name: String) throws -> String? {
		guard let sidebar = try sidebar(), let row = try driver.find(AXID.sidebarRow(kind, name), in: sidebar) else {
			return nil
		}
		return try driver.value(row)
	}

	/// Waits until the server's sidebar row reports `state`.
	func server(_ state: String, network: String = ScenarioContext.network, timeout: Duration = .seconds(20)) async throws {
		try await until("server \(network) is \(state)", timeout: timeout) {
			try rowState("server", network) == state
		}
	}

	/// Selects a sidebar row and waits until it is selected.
	func selectRow(_ kind: String, _ name: String) async throws {
		try await driver.select(AXID.sidebarRow(kind, name)) { try self.sidebar() }
	}

	/// Whether the sidebar row is the selected one.
	func isSelected(_ kind: String, _ name: String) throws -> Bool {
		guard let sidebar = try sidebar(), let row = try driver.row(containing: AXID.sidebarRow(kind, name), in: sidebar)
		else { return false }
		return try driver.bool(row, kAXSelectedAttribute) == true
	}

	/// Waits until the end of the selected conversation's transcript contains
	/// `marker` `occurrences` times. Only the last 30,000 characters are read:
	/// what a scenario waits for has just arrived.
	func transcript(contains marker: String, occurrences: Int = 1, timeout: Duration = .seconds(20)) async throws {
		try await until("transcript shows \(marker)", timeout: timeout) {
			guard let window = try mainWindow(), let transcript = try driver.find(AXID.transcript, in: window),
			      let text = try driver.tail(of: transcript, length: 30000)
			else { return false }
			return text.components(separatedBy: marker).count - 1 >= occurrences
		}
	}

	/// The message editor of the main window.
	func messageInput() throws -> AXUIElement? {
		try mainWindow().flatMap { try driver.find(AXID.messageInput, in: $0) }
	}

	/** Enters `text` in the message editor and sends it with the editor's
	 Confirm action, which is what Return does. Both go through
	 Accessibility, so sending does not depend on which application has the
	 keyboard. */
	func send(_ text: String) async throws {
		try await until("the message editor is empty") {
			guard let input = try messageInput() else { return false }
			guard try driver.value(input)?.isEmpty ?? true else {
				throw HarnessFailure.assertion("The message editor was not empty before entering text")
			}
			return true
		}
		try await driver.fill(AXID.messageInput, with: text) { try self.mainWindow() }
		try await until("message editor confirms") {
			guard let input = try messageInput() else { return false }
			try driver.perform(kAXConfirmAction, on: input)
			return true
		}
		try await until("message editor clears after sending") {
			guard let input = try messageInput() else { return false }
			return try driver.value(input)?.isEmpty ?? true
		}
	}

	// MARK: - Connection

	/// Chooses Server > Connect.
	func connect() async throws {
		try await driver.menu("connect")
	}

	/// Answers the certificate trust sheet: Continue or Cancel.
	func answerCertificate(continue accept: Bool) async throws {
		let button = accept ? AXID.alertDefault(AXID.certificateTrust) : AXID.alertAlternate(AXID.certificateTrust)
		try await driver.press("certificate trust sheet, \(accept ? "Continue" : "Cancel")") {
			try (driver.window(AXID.certificateTrust) ?? driver.anywhere(AXID.certificateTrust))
				.flatMap { try driver.find(button, in: $0) }
		}
	}

	/// Waits for registration to finish: the welcome notice in the transcript,
	/// the server row connected and the peer's PING answered.
	func awaitRegistered(network: String = ScenarioContext.network) async throws {
		let peer = try requirePeer
		try await transcript(contains: "E2E_TRANSCRIPT_READY")
		try await server(AXID.RowState.connected, network: network)
		try await until("peer received PONG") { peer.evidence.pongSeen }
	}

	/// Chooses Disconnect and requires the server row to read disconnected and
	/// the peer to see `QUIT` and a clean close within five seconds.
	func disconnect() async throws {
		let peer = try requirePeer
		try await driver.menu("disconnect")
		try await until("Disconnect closes the connection", timeout: .seconds(5)) {
			try rowState("server", ScenarioContext.network) == AXID.RowState.disconnected && peer.evidence.complete
		}
	}

	/// Quits, requiring a clean exit within five seconds and, when `peerSeesQuit`,
	/// the peer's view of `QUIT` and a clean close within the same five seconds.
	func quit(peerSeesQuit: Bool) async throws {
		let launch = try current
		try await launch.quit()
		if peerSeesQuit {
			let peer = try requirePeer
			try await Wait.until("peer saw QUIT and EOF", timeout: .seconds(1)) {
				try peer.check()
				return peer.evidence.complete && peer.evidence.quitSeen
			}
		}
	}

	/// The application is still the one process this scenario launched.
	func requireSameProcess() throws {
		let launch = try current
		guard launches.count == 1, launch.isRunning else {
			throw HarnessFailure.assertion("Reconnecting did not keep the application process (\(launch.exitDescription))")
		}
	}

	/// The registration lines the peer saw on `attempt`, which have to be the
	/// standard four.
	func requireStandardRegistration(attempt: Int) throws {
		let expected = "CAP LS 302; NICK e2euser; USER e2euser 0 * :Synthetic E2E User; CAP END"
		guard try requirePeer.evidence.registrations[attempt] == expected else {
			throw HarnessFailure.assertion("Registration attempt \(attempt) did not send the standard lines")
		}
	}

	// MARK: - Windows

	/// Chooses Settings and returns once the Settings window is up.
	func openSettings() async throws {
		try await driver.menu("settings")
		try await until("Settings window") { try driver.window(AXID.settingsWindow) != nil }
	}

	/// Selects a Settings page, by `SettingsPane` raw value.
	func selectSettingsPage(_ pane: String) async throws {
		try await driver.select(AXID.settingsPage(pane)) {
			try self.driver.element(AXID.settingsSidebar, inWindow: AXID.settingsWindow)
		}
	}

	/// Closes the window identified `identifier` with its close button.
	func close(window identifier: String) async throws {
		try await until("close \(identifier)") {
			guard let window = try driver.window(identifier) else { return true }
			guard let close = try driver.attribute(window, kAXCloseButtonAttribute),
			      CFGetTypeID(close) == AXUIElementGetTypeID()
			else { return false }
			try driver.press(unsafeDowncast(close, to: AXUIElement.self))
			return try driver.window(identifier) == nil
		}
	}
}
