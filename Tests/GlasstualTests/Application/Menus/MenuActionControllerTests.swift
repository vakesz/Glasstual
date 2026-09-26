import AppKit
@testable import Glasstual
import Testing

@MainActor
@Suite("Menu action coordinator")
struct MenuActionControllerTests {
	private let activeStates: [SessionConnectionState] = [
		.init(transport: .preparingCredentials), .init(transport: .connecting), .init(transport: .connected),
	]

	private let stoppingStates: [SessionConnectionState] = [
		.init(transport: .preparingCredentials, shutdown: .quitting),
		.init(transport: .connecting, shutdown: .quitting),
		.init(transport: .connected, shutdown: .quitting),
		.init(transport: .preparingCredentials, shutdown: .disconnecting),
		.init(transport: .connecting, shutdown: .disconnecting),
		.init(transport: .connected, shutdown: .disconnecting),
		.init(transport: .connected, shutdown: .disconnectingAfterQuit),
	]

	@Test("Connection commands reject every stopping state")
	func serverConnectionActionsShareStateGuards() {
		let cases = [(SessionConnectionState(), true, false)]
			+ activeStates.map { ($0, false, true) }
			+ stoppingStates.map { ($0, false, false) }
		for (state, canConnect, canDisconnect) in cases {
			let session = TestServerSession()
			session.connectionState = state
			session.config.proxyType = .socks5
			let policy = MenuServerActionRules(session: session)
			#expect(policy.canConnect == canConnect)
			#expect(policy.canConnectWithoutProxy == canConnect)
			#expect(policy.canDisconnect == canDisconnect)
			session.isTerminating = true
			let terminatingPolicy = MenuServerActionRules(session: session)
			#expect(!terminatingPolicy.canConnect)
			#expect(!terminatingPolicy.canDisconnect)
		}
	}

	@Test("Proxy bypass requires a proxy and all connection commands require a session")
	func connectionCommandsRequireTheirTargets() {
		let session = TestServerSession()
		session.config.proxyType = .none
		#expect(MenuServerActionRules(session: session).canConnect)
		#expect(MenuServerActionRules(session: session).canConnectWithoutProxy == false)
		let noSession = MenuServerActionRules(session: nil)
		#expect(noSession.canConnect == false)
		#expect(noSession.canConnectWithoutProxy == false)
		#expect(noSession.canDisconnect == false)
		#expect(noSession.canCancelReconnect == false)
	}

	@Test("Cancel reconnect is eligible only while a live session is waiting")
	func cancelReconnectRequiresWaitingSession() {
		let session = TestServerSession()
		#expect(MenuServerActionRules(session: session).canCancelReconnect == false)
		session.reconnect.timer.start(3600, repeats: false)
		defer { session.reconnect.timer.stop() }
		#expect(MenuServerActionRules(session: session).canCancelReconnect)
		session.setConnectionShutdownForTesting(.disconnecting)
		#expect(MenuServerActionRules(session: session).canCancelReconnect == false)
		session.setConnectionShutdownForTesting(.none)
		session.setConnectionShutdownForTesting(.quitting)
		#expect(MenuServerActionRules(session: session).canCancelReconnect == false)
		session.setConnectionShutdownForTesting(.none)
		session.isTerminating = true
		#expect(MenuServerActionRules(session: session).canCancelReconnect == false)
	}

	@Test("Connection menu validation shares action eligibility without changing visibility")
	func connectionMenuPreservesVisibility() {
		for state in [SessionConnectionState()] + activeStates + stoppingStates {
			let controller = MenuActionController()
			let session = TestServerSession()
			controller.context.pointedSession = session
			session.connectionState = state
			let policy = MenuServerActionRules(session: session)
			let connect = NSMenuItem()
			connect.command = .connect
			let disconnect = NSMenuItem()
			disconnect.command = .disconnect

			#expect(controller.validator.validateServerCommand(connect) == policy.canConnect)
			#expect(controller.validator.validateServerCommand(disconnect) == policy.canDisconnect)
			#expect(connect.isHidden == (session.isConnecting || session.isConnected))
			#expect(disconnect.isHidden == (session.isConnecting == false && session.isConnected == false))
		}
	}

	@Test("Disconnect becomes disabled after its first invocation and cannot quit twice")
	func disconnectActionAndValidationAgree() throws {
		let controller = MenuActionController()
		let session = TestServerSession()
		controller.context.pointedSession = session
		let connection = Connection(config: ConnectionConfig(), onSession: session)
		session.socket = connection
		session.setConnectionTransportForTesting(.connected)
		session.markAsLoggedIn()
		defer {
			session.cancelDelayedDisconnect()
			connection.close()
		}
		let item = NSMenuItem()
		item.command = .disconnect

		#expect(controller.validator.validateServerCommand(item))
		controller.disconnect(item)
		#expect(session.isQuitting)
		#expect(controller.validator.validateServerCommand(item) == false)
		#expect(item.isHidden == false)
		let delayedDisconnect = try #require(session.pendingDisconnectTask)
		#expect(session.sentLines.count == 1)
		#expect((session.sentLines.firstObject as? String)?.hasPrefix("QUIT ") == true)
		let titleUpdateCount = session.recordedOutput.titleUpdates.count
		controller.disconnect(item)
		#expect(session.recordedOutput.titleUpdates.count == titleUpdateCount)
		#expect(session.sentLines.count == 1)
		#expect(!delayedDisconnect.isCancelled)

		session.cancelDelayedDisconnect()
		connection.close()
		#expect(!session.isQuitting)
		#expect(!session.isConnected)
		#expect(controller.validator.validateServerCommand(item) == false)
		#expect(item.isHidden)
	}

	/** Change Nickname validated on `isConnected` while the action it enables
	 guards on `isLoggedIn`, so choosing it during registration did nothing at
	 all. */
	@Test("Change Nickname needs a registered connection, not merely a socket")
	func changeNicknameNeedsLogin() {
		let controller = MenuActionController()
		let session = TestServerSession()
		controller.context.pointedSession = session
		session.setConnectionTransportForTesting(.connected)
		let item = NSMenuItem()
		item.command = .changeNickname

		#expect(controller.validator.validateServerCommand(item) == false)
		session.markAsLoggedIn()
		#expect(controller.validator.validateServerCommand(item))
	}

	@Test("Each appearance menu item names the appearance it selects")
	func appearanceItemsNameOneAppearanceEach() {
		#expect(MenuWindowPolicy.appearance(for: .appearanceSystem) == .inherited)
		#expect(MenuWindowPolicy.appearance(for: .appearanceLight) == .light)
		#expect(MenuWindowPolicy.appearance(for: .appearanceDark) == .dark)
		#expect(MenuWindowPolicy.appearance(for: .about) == nil)
		#expect(MenuWindowPolicy.appearance(for: nil) == nil)
	}

	/// The window menu's "reset suppressed warnings" command finds them by
	/// prefix, so it has to read the prefix the flags are written under rather
	/// than one of its own.
	@Test("Resetting suppressed warnings uses the declared suppression prefix")
	func suppressedWarningPolicyReadsTheDeclaredPrefix() {
		#expect(MenuWindowPolicy.alertSuppressionPrefix == SettingsKeys.Families.alertSuppression.pattern)
		#expect(MenuWindowPolicy.alertSuppressionPrefix == "Alerts -> ")
	}
}
