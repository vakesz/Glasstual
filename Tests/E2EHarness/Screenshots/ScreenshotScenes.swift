import AppKit
import ApplicationServices
import Foundation

/// The appearance a scene is taken in: the application's own Preferred
/// Appearance setting in the run's suite. The system appearance is not touched.
enum ScreenshotAppearance: String, CaseIterable {
	case light
	case dark

	/// The stored `PreferredAppearance`.
	var setting: Int {
		self == .light ? 1 : 2
	}
}

/** One launch of the application against the demo, and the pictures taken of
 it. A group is a ``Scenario``, so ``Runner`` gives it the sandbox, the budget,
 the diagnostics of a failure and the teardown every end-to-end scenario has. */
struct ScreenshotScenario: Scenario {
	enum Group: String, CaseIterable {
		/// The main window and the windows opened from it, in the dialog style.
		case windows
		/// A question in the conversation, in the conversation style.
		case prompt
		/// The welcome window on its "How Glasstual Asks" step.
		case welcome
	}

	let group: Group
	let appearance: ScreenshotAppearance
	let output: URL

	var name: String {
		"screenshots-\(group.rawValue)-\(appearance.rawValue)"
	}

	let budget = Duration.seconds(240)

	func run(_ context: ScenarioContext) async throws {
		let shots = ScreenshotSession(context: context, appearance: appearance, output: output)
		switch group {
		case .windows: try await shots.windows()
		case .prompt: try await shots.prompt()
		case .welcome: try await shots.welcome()
		}
		try await context.quit(peerSeesQuit: false)
	}
}

/// The settings a screenshot launch starts from.
enum DemoSeed {
	static func connected(
		corpora: URL,
		server: DemoServer,
		appearance: ScreenshotAppearance,
		conversationStyle: Bool
	) throws -> Data {
		var settings = try base(corpora: corpora, appearance: appearance)
		var sessions = [session(
			DemoScript.example.name,
			port: server.directPort,
			conversations: DemoScript.example.channels.map(\.name),
			extra: [
				"saslMechanismPreference": "SCRAM-SHA-256",
				"ignoreList": [
					["entryType": 0, "hostmask": DemoScript.ignoredHostmask, "ignorePublicMessages": true,
					 "ignorePrivateMessages": true, "ignoreNoticeMessages": true],
					["entryType": 1, "hostmask": DemoScript.trackedNickname, "trackUserActivity": true],
				],
			]
		)]
		if conversationStyle {
			settings[SettingsKey.interactionStyle] = 1
		} else {
			sessions.append(session(
				DemoScript.bouncerAccountName,
				port: server.bouncerPort,
				conversations: [],
				extra: ["bouncerDiscoversNetworks": true]
			))
		}
		settings[SettingsKey.serverSessions] = sessions
		return try Seed.encode(settings)
	}

	static func onboarding(corpora: URL, appearance: ScreenshotAppearance) throws -> Data {
		var settings = try base(corpora: corpora, appearance: appearance)
		settings[SettingsKey.serverSessions] = [[String: Any]]()
		settings[SettingsKey.onboardingCompleted] = false
		settings[SettingsKey.nickname] = ""
		settings[SettingsKey.realName] = ""
		return try Seed.encode(settings)
	}

	/// The end-to-end startup settings with the demo's identity: no dock
	/// badge and no notifications for the scripted mentions.
	private static func base(corpora: URL, appearance: ScreenshotAppearance) throws -> [String: Any] {
		var settings = try Seed.startup(corpora: corpora)
		settings[SettingsKey.onboardingCompleted] = true
		settings[SettingsKey.nickname] = DemoScript.nickname
		settings[SettingsKey.username] = DemoScript.nickname
		settings[SettingsKey.realName] = DemoScript.realName
		settings[SettingsKey.preferredAppearance] = appearance.setting
		settings[SettingsKey.notifyAboutMentions] = false
		settings[SettingsKey.displayDockBadge] = false
		return settings
	}

	private static func session(
		_ name: String,
		port: UInt16,
		conversations: [String],
		extra: [String: Any]
	) -> [String: Any] {
		var session: [String: Any] = [
			"dictionaryVersion": 1,
			"uniqueIdentifier": UUID().uuidString,
			"connectionName": name,
			"nickname": DemoScript.nickname,
			"username": DemoScript.nickname,
			"realName": DemoScript.realName,
			"proxyType": 0,
			"autoConnect": false,
			"autoReconnect": false,
			"validateServerCertificateChain": true,
			"setInvisibleModeOnConnect": false,
			"performPongTimer": false,
			"performDisconnectOnReachabilityChange": false,
			"sidebarItemExpanded": true,
			"normalLeavingComment": "Goodbye",
			"serverList": [[
				"uniqueIdentifier": UUID().uuidString,
				"serverAddress": "127.0.0.1", "serverPort": Int(port), "prefersSecuredConnection": false,
			]],
			"conversationList": conversations.map {
				["uniqueIdentifier": UUID().uuidString, "name": $0, "type": 0, "ignoreGeneralEventMessages": true]
			},
		]
		session.merge(extra) { _, new in new }
		return session
	}
}

/// The steps of the screenshot scenes. Like every scenario, each finds what
/// it needs by identifier and waits on a condition.
struct ScreenshotSession {
	let context: ScenarioContext
	let appearance: ScreenshotAppearance
	let output: URL

	private static let mainWindowSize = CGSize(width: 1440, height: 760)
	/// The size a Server Properties window opens at. Stated, because a window
	/// reopens at the size it was last left at on this Mac.
	private static let serverPropertiesSize = CGSize(width: 860, height: 620)
	/// Where a resized window is put: clear of the menu bar.
	private static let windowOrigin = CGPoint(x: 40, y: 50)

	private var driver: AXDriver {
		get throws { try context.driver }
	}

	// MARK: - Scenes

	func windows() async throws {
		let server = try await context.startDemo()
		try await context.launch(seed: DemoSeed.connected(
			corpora: context.corpora, server: server, appearance: appearance, conversationStyle: false
		))
		try await connect(DemoScript.example.name)
		try await connect(DemoScript.bouncerAccountName)
		for (_, network) in DemoScript.bouncerNetworks {
			try await connect(network.name)
		}
		for network in [DemoScript.example] + DemoScript.bouncerNetworks.map(\.1) {
			for channel in network.channels {
				try await context.until("\(channel.name) is joined") {
					try context.rowState("channel", channel.name) == AXID.RowState.joined
				}
			}
		}

		/* The reader reads #swift, looks at #macdev, and #swift goes on
		 without them: what it says then is unread, and the boundary is drawn
		 above the first of it. #macdev's own late line is said after those,
		 on the same connection, so seeing it says they have arrived. */
		try await show(DemoScript.swift, through: DemoScript.swift.seenLines)
		try await show(DemoScript.macdev, through: DemoScript.macdev.seenLines)
		server.sendUnseenLines(for: DemoScript.swift.name)
		server.sendUnseenLines(for: DemoScript.macdev.name)
		try await show(DemoScript.macdev)
		try await show(DemoScript.swift)
		server.sendReactions(for: DemoScript.swift.name)
		try await capture("main-window", window: AXID.mainWindow, size: Self.mainWindowSize)

		if let nested = DemoScript.bouncerNetworks.first?.1.channels.first {
			try await show(nested)
			try await capture("networks", window: AXID.mainWindow, size: Self.mainWindowSize)
		}

		try await show(DemoScript.swift)
		try await search(for: DemoScript.searchQuery)
		try await capture("search", window: AXID.scrollbackSearchWindow, size: CGSize(width: 900, height: 600))
		try await context.close(window: AXID.scrollbackSearchWindow)

		try await context.openSettings()
		try await context.selectSettingsPage("style")
		try await context.until("the theme preset menu") {
			try driver.element(AXID.settingsThemePreset, inWindow: AXID.settingsWindow) != nil
		}
		try await capture("settings", window: AXID.settingsWindow)
		try await context.close(window: AXID.settingsWindow)

		try await context.selectRow("server", DemoScript.example.name)
		try await context.openServerProperties()
		try await driver.select(AXID.serverPropertiesPane("identity")) {
			try driver.window(AXID.serverProperties)
		}
		try await context.until("the SASL mechanism menu") {
			try driver.element(AXID.serverSASLMechanism, inWindow: AXID.serverProperties) != nil
		}
		try await capture("server-properties", window: AXID.serverProperties, size: Self.serverPropertiesSize)
		try await context.close(window: AXID.serverProperties)

		try await driver.menu("addressBook")
		try await context.until("People lists both entries") {
			guard let list = try driver.element(AXID.addressBookList, inWindow: AXID.addressBookWindow) else { return false }
			return try [DemoScript.ignoredHostmask, DemoScript.trackedNickname].allSatisfy {
				try driver.find(AXID.addressBookEntry($0), in: list) != nil
			}
		}
		try await capture("people", window: AXID.addressBookWindow)
		try await context.close(window: AXID.addressBookWindow)

		try await secureTransfer(from: server)
	}

	func prompt() async throws {
		let server = try await context.startDemo()
		try await context.launch(seed: DemoSeed.connected(
			corpora: context.corpora, server: server, appearance: appearance, conversationStyle: true
		))
		try await connect(DemoScript.example.name)
		try await context.selectRow("server", DemoScript.example.name)
		if let last = DemoScript.example.messageOfTheDay.last {
			try await context.transcript(contains: last)
		}

		/* `/register` with an account and an email asks for the password in a
		 secure field rather than on the command line. In the conversation
		 style that question is a card above the message field of the network
		 it was typed to, and names the `/answer` command that answers it.
		 Nothing in a transcript is pressed: a link there is another
		 application's to open. */
		try await context.send("/register * \(DemoScript.email)")
		try await context.until("the password question is a card that names its /answer command") {
			try promptHint()?.contains("/answer 1") == true
		}
		try await context.until("the window is \(Int(Self.mainWindowSize.width)) wide and the connection lines have scrolled away") {
			guard let window = try context.mainWindow(), let transcript = try driver.find(AXID.transcript, in: window),
			      let text = try driver.value(transcript), let visible = try driver.visibleRange(in: transcript)
			else { return false }
			try driver.setFrame(window, to: CGRect(origin: Self.windowOrigin, size: Self.mainWindowSize))
			/* The lines about the loopback connection come before the
			 message of the day, which is long enough to scroll them away. */
			let connection = (text as NSString).range(of: DemoScript.endOfConnectionLines)
			return connection.location != NSNotFound && visible.location > connection.location
		}
		/* A card's buttons count only once it has been still for a moment, and
		 are drawn disabled until then. */
		try await context.until("the card's buttons count") {
			guard let card = try context.mainWindow().flatMap({ try driver.find(AXID.promptCard(1), in: $0) }),
			      let cancel = try driver.find(AXID.promptButton(1, "cancel"), in: card) else { return false }
			return try driver.isEnabled(cancel)
		}
		try await capture("inline-prompt", window: AXID.mainWindow, size: Self.mainWindowSize)

		try await context.send("/no")
		try await context.until("the card goes") { try promptHint() == nil }
	}

	/// What the first question's card says answers it.
	private func promptHint() throws -> String? {
		try context.mainWindow().flatMap { try driver.find(AXID.promptCard(1), in: $0) }
			.flatMap { try driver.find(AXID.promptCardHint(1), in: $0) }
			.flatMap { try driver.value($0) }
	}

	/// `marlow` offers a file over TLS; accepting it asks about the
	/// certificate, and trusting that lets the file through.
	private func secureTransfer(from server: DemoServer) async throws {
		server.offerSecureTransfer()
		try await driver.menu("fileTransfers")
		_ = try await context.startOfferedTransfer(knowing: [])
		try await context.answerAlert(AXID.dccCertificateFirstUse, with: AXID.alertDefault(AXID.dccCertificateFirstUse))
		try await context.requireDownload(of: DemoScript.transferFilename, from: server.transferPeer)
		try await context.until("the transfer is listed as finished and secure") {
			guard let window = try driver.window(AXID.fileTransfersWindow),
			      let stop = try driver.find(AXID.fileTransfersStop, in: window) else { return false }
			return try driver.all(withPrefix: AXID.fileTransferSecurityPrefix, in: window).count == 1
				&& driver.isEnabled(stop) == false
		}
		try await capture("secure-dcc", window: AXID.fileTransfersWindow, size: CGSize(width: 820, height: 440))
		try await context.close(window: AXID.fileTransfersWindow)
	}

	func welcome() async throws {
		try await context.launch(seed: DemoSeed.onboarding(corpora: context.corpora, appearance: appearance))
		try await context.onboardingStep("identity")
		try await driver.fill(AXID.onboardingNickname, inWindow: AXID.onboardingWindow, with: DemoScript.nickname)
		try await driver.fill(AXID.onboardingRealName, inWindow: AXID.onboardingWindow, with: DemoScript.realName)
		try await driver.button(AXID.onboardingContinue, inWindow: AXID.onboardingWindow)
		try await context.onboardingStep("appearance")
		try await driver.button(AXID.onboardingContinue, inWindow: AXID.onboardingWindow)
		try await context.onboardingStep("interaction")
		try await capture("welcome", window: AXID.onboardingWindow)

		/* Finish the flow rather than quit in the middle of it: the welcome
		 window records that it was dismissed as it closes, which a quit would
		 leave behind in the run's settings. */
		try await driver.button(AXID.onboardingContinue, inWindow: AXID.onboardingWindow)
		for step in ["notifications", "network", "summary"] {
			try await context.onboardingStep(step)
			if step != "summary" {
				try await driver.button(AXID.onboardingSkip, inWindow: AXID.onboardingWindow)
			}
		}
		try await driver.button(AXID.onboardingFinish, inWindow: AXID.onboardingWindow)
		try await context.until("the welcome window closes") { try driver.window(AXID.onboardingWindow) == nil }
	}

	// MARK: - Steps

	/// Connects the network `name` and waits until its row says so.
	private func connect(_ name: String) async throws {
		try await context.until("sidebar lists \(name)") { try context.rowState("server", name) != nil }
		if try context.rowState("server", name) != AXID.RowState.connected {
			try await context.selectRow("server", name)
			try await context.connect()
		}
		try await context.server(AXID.RowState.connected, network: name)
	}

	/// Selects `channel` and waits for the last of `lines`: the whole of its
	/// script unless the scene is still holding some of it back.
	private func show(_ channel: DemoChannel, through lines: [DemoLine]? = nil) async throws {
		try await context.selectRow("channel", channel.name)
		if let last = (lines ?? channel.lines).last {
			try await context.transcript(contains: last.text)
		}
	}

	/** Opens the history search and asks it for `text`. The search field is
	 the system's, in the toolbar, and carries no identifier of the
	 application's, so it is the one search field of the window the results
	 list identifies. */
	private func search(for text: String) async throws {
		try await driver.menu("findInAllConversations")
		let field = try await context.until("the history search field") { () throws -> AXUIElement? in
			guard let window = try driver.window(AXID.scrollbackSearchWindow) else { return nil }
			return try driver.all(role: kAXTextFieldRole, in: window)
				.first { try driver.string($0, kAXSubroleAttribute) == kAXSearchFieldSubrole }
		}
		try await context.until("the search field holds the query") {
			if try driver.bool(field, kAXFocusedAttribute) != true {
				try driver.set(field, kAXFocusedAttribute, to: kCFBooleanTrue)
			}
			try driver.set(field, kAXValueAttribute, to: text as CFString)
			return try driver.value(field) == text
		}
		try await context.until("the search lists what it found") {
			guard let results = try driver.element(AXID.scrollbackSearchResults, inWindow: AXID.scrollbackSearchWindow)
			else { return false }
			return try driver.all(role: kAXRowRole, in: results).count >= DemoScript.searchMatches
		}
	}

	// MARK: - Capture

	/** Writes `<name>-<appearance>.png`: the window identified `window`,
	 resized to `size` when given, in front and still.

	 The window is the application's main window while it is captured, so its
	 title bar is drawn active. "Still" is two captures in a row with the same
	 pixels, which is what tells a finished layout, scroll or fade from one
	 in progress. A capture taken while another application came forward is
	 taken again. */
	private func capture(_ name: String, window identifier: String, size: CGSize? = nil) async throws {
		let pid = try context.current.pid
		let scratch = context.artifacts.appendingPathComponent("capture.png")
		let step = "capture \(name)"
		for attempt in 1 ... 4 {
			let element = try await context.until("\(step): window in front") { () throws -> AXUIElement? in
				guard let element = try driver.window(identifier) else { return nil }
				NSRunningApplication(processIdentifier: pid)?.activate()
				if try driver.bool(element, kAXMainAttribute) != true {
					try driver.set(element, kAXMainAttribute, to: kCFBooleanTrue)
				}
				guard try driver.bool(element, kAXMainAttribute) == true,
				      NSRunningApplication(processIdentifier: pid)?.isActive == true
				else { return nil }
				return element
			}
			if let size {
				try await context.until("\(step): window is \(Int(size.width)) x \(Int(size.height))") {
					try driver.setFrame(element, to: CGRect(origin: Self.windowOrigin, size: size))
					return try driver.frame(element)?.size == size
				}
			}
			let (still, frame) = try await stillPicture(of: element, pid: pid, scratch: scratch, step: step)
			guard NSRunningApplication(processIdentifier: pid)?.isActive == true,
			      try driver.bool(element, kAXMainAttribute) == true
			else {
				context.note("\(step): attempt \(attempt) lost the foreground, taking it again")
				continue
			}
			let file = output.appendingPathComponent("\(name)-\(appearance.rawValue).png")
			try await WindowCapture.write(WindowCapture.render(still, size: frame.size), to: file)
			print("  \(file.lastPathComponent)  \(Int(frame.width)) x \(Int(frame.height))")
			return
		}
		throw HarnessFailure.assertion("\(step): another application kept coming forward")
	}

	/// Captures the window until two captures in a row are the same picture
	/// of the same frame, and returns that picture and frame.
	private func stillPicture(
		of element: AXUIElement,
		pid: pid_t,
		scratch: URL,
		step: String
	) async throws -> (CGImage, CGRect) {
		try driver.currentStep = "\(step): window is still"
		let deadline = Deadline(after: .seconds(20))
		var last: (digest: String, frame: CGRect)?
		while true {
			try Task.checkCancellation()
			if let frame = try? driver.frame(element),
			   let number = WindowCapture.windowNumber(pid: pid, frame: frame),
			   let image = await WindowCapture.capture(number, scratch: scratch)
			{
				let digest = WindowCapture.digest(image)
				if last?.digest == digest, last?.frame == frame {
					try? FileManager.default.removeItem(at: scratch)
					return (image, frame)
				}
				last = (digest, frame)
			}
			guard deadline.hasPassed == false else { throw HarnessFailure.timeout("\(step): window is still") }
			try await Task.sleep(for: .milliseconds(120))
		}
	}
}
