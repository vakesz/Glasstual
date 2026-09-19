import AppKit
@testable import Glasstual
import Testing

@MainActor
@Suite("Menu action coordinator")
struct MenuActionControllerTests {
	@Test("Connection commands reject every stopping state", arguments: 0 ..< 32)
	func serverConnectionActionsShareStateGuards(flags: Int) {
		let session = TestServerSession()
		session.isConnecting = flags & 1 != 0
		session.isConnected = flags & 2 != 0
		session.isQuitting = flags & 4 != 0
		session.isDisconnecting = flags & 8 != 0
		session.isTerminating = flags & 16 != 0
		session.config.proxyType = .socks5
		let policy = MenuServerActionRules(session: session)

		#expect(policy.canConnect == (flags == 0))
		#expect(policy.canConnectWithoutProxy == policy.canConnect)
		#expect(policy.canDisconnect == (flags > 0 && flags < 4))
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
		session.isDisconnecting = true
		#expect(MenuServerActionRules(session: session).canCancelReconnect == false)
		session.isDisconnecting = false
		session.isQuitting = true
		#expect(MenuServerActionRules(session: session).canCancelReconnect == false)
		session.isQuitting = false
		session.isTerminating = true
		#expect(MenuServerActionRules(session: session).canCancelReconnect == false)
	}

	@Test("Connection menu validation shares action eligibility without changing visibility", arguments: 0 ..< 32)
	func connectionMenuPreservesVisibility(flags: Int) {
		let controller = MenuActionController()
		let session = TestServerSession()
		controller.context.pointedSession = session
		session.isConnecting = flags & 1 != 0
		session.isConnected = flags & 2 != 0
		session.isQuitting = flags & 4 != 0
		session.isDisconnecting = flags & 8 != 0
		session.isTerminating = flags & 16 != 0
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

	@Test("Disconnect becomes disabled after its first invocation and cannot quit twice")
	func disconnectActionAndValidationAgree() throws {
		let controller = MenuActionController()
		let session = TestServerSession()
		controller.context.pointedSession = session
		let connection = Connection(config: ConnectionConfig(), onSession: session)
		session.socket = connection
		session.isConnected = true
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
		session.isConnected = true
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

	/// The name says a copy, not a truncated original: the connection used to
	/// be called "Libera_".
	@Test("A duplicated connection is named the way a duplicated file is")
	func duplicateConnectionNamePreservesTheOriginal() {
		#expect(MenuServerNamePolicy.duplicateName(of: "Libera") == "Libera copy")
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
