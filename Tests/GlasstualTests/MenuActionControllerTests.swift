import AppKit
@testable import Glasstual
import Testing

@MainActor
@Suite("Menu action coordinator")
struct MenuActionControllerTests {
	@Test("A member menu item still sends the command the network expects")
	func memberCommandsPreserveLegacyWireFormat() {
		#expect(MenuMemberCommand.ignore("Alice") == "ignore Alice")
		#expect(MenuMemberCommand.unignore("Alice") == "unignore Alice")
		#expect(MenuMemberCommand.mode("HALFOP", nicknames: ["Alice", "Bob"]) == "HALFOP Alice Bob")
		#expect(MenuMemberCommand.kickban("Alice", reason: "Requested") == "KICKBAN Alice Requested")
		#expect(
			MenuMemberCommand.operatorCommand("GLINE", nickname: "Alice", reason: "Abuse")
				== "GLINE Alice Abuse"
		)
		#expect(MenuMemberCommand.setVhost("staff.example", nickname: "Alice") == "hs setall Alice staff.example")
	}

	@Test("Every navigation action is reachable from the command its menu item carries")
	func navigationCommandsMapToNavigationActions() {
		let mappings: [(MenuCommand, MenuNavigationAction)] = [
			(.nextServer, .nextServer),
			(.previousServer, .previousServer),
			(.nextActiveServer, .nextActiveServer),
			(.previousActiveServer, .previousActiveServer),
			(.nextChannel, .nextChannel),
			(.previousChannel, .previousChannel),
			(.nextActiveChannel, .nextActiveChannel),
			(.previousActiveChannel, .previousActiveChannel),
			(.nextUnreadChannel, .nextUnreadChannel),
			(.previousUnreadChannel, .previousUnreadChannel),
			(.moveBackward, .moveBackward),
			(.moveForward, .moveForward),
			(.previousSelection, .previousSelection),
		]

		for (command, action) in mappings {
			#expect(MenuActionController.navigationAction(for: command) == action)
		}

		/* Every action has to be reachable from a command, or a menu item
		 exists that nothing can invoke. */
		#expect(
			Set(mappings.map(\.1).map(String.init(describing:))).count == MenuNavigationAction.allCases.count
		)
	}

	@Test("A command that belongs to no navigation item is not treated as navigation")
	func navigationIgnoresUnrelatedCommands() {
		#expect(MenuActionController.navigationAction(for: .about) == nil)
		#expect(MenuActionController.navigationAction(for: nil) == nil)
	}

	@Test("Connection commands reject every stopping state", arguments: 0 ..< 32)
	func serverConnectionActionsShareStateGuards(flags: Int) {
		let client = TestClient()
		client.isConnecting = flags & 1 != 0
		client.isConnected = flags & 2 != 0
		client.isQuitting = flags & 4 != 0
		client.isDisconnecting = flags & 8 != 0
		client.isTerminating = flags & 16 != 0
		client.config.proxyType = .socks5
		let policy = MenuServerActionPolicy(client: client)

		#expect(policy.canConnect == (flags == 0))
		#expect(policy.canConnectWithoutProxy == policy.canConnect)
		#expect(policy.canDisconnect == (flags > 0 && flags < 4))
	}

	@Test("Proxy bypass requires a proxy and all connection commands require a client")
	func connectionCommandsRequireTheirTargets() {
		let client = TestClient()
		client.config.proxyType = .none
		#expect(MenuServerActionPolicy(client: client).canConnect)
		#expect(MenuServerActionPolicy(client: client).canConnectWithoutProxy == false)
		let noClient = MenuServerActionPolicy(client: nil)
		#expect(noClient.canConnect == false)
		#expect(noClient.canConnectWithoutProxy == false)
		#expect(noClient.canDisconnect == false)
		#expect(noClient.canCancelReconnect == false)
	}

	@Test("Cancel reconnect is eligible only while a live client is waiting")
	func cancelReconnectRequiresWaitingClient() {
		let client = TestClient()
		#expect(MenuServerActionPolicy(client: client).canCancelReconnect == false)
		client.reconnect.timer.start(3600, repeats: false)
		defer { client.reconnect.timer.stop() }
		#expect(MenuServerActionPolicy(client: client).canCancelReconnect)
		client.isDisconnecting = true
		#expect(MenuServerActionPolicy(client: client).canCancelReconnect == false)
		client.isDisconnecting = false
		client.isQuitting = true
		#expect(MenuServerActionPolicy(client: client).canCancelReconnect == false)
		client.isQuitting = false
		client.isTerminating = true
		#expect(MenuServerActionPolicy(client: client).canCancelReconnect == false)
	}

	@Test("Connection menu validation shares action eligibility without changing visibility", arguments: 0 ..< 32)
	func connectionMenuPreservesVisibility(flags: Int) {
		let controller = MenuActionController()
		let coordinator = controller
		let client = TestClient()
		coordinator.pointedClient = client
		client.isConnecting = flags & 1 != 0
		client.isConnected = flags & 2 != 0
		client.isQuitting = flags & 4 != 0
		client.isDisconnecting = flags & 8 != 0
		client.isTerminating = flags & 16 != 0
		let policy = MenuServerActionPolicy(client: client)
		let connect = NSMenuItem()
		connect.command = .connect
		let disconnect = NSMenuItem()
		disconnect.command = .disconnect

		#expect(coordinator.validateServerCommand(connect) == policy.canConnect)
		#expect(coordinator.validateServerCommand(disconnect) == policy.canDisconnect)
		#expect(connect.isHidden == (client.isConnecting || client.isConnected))
		#expect(disconnect.isHidden == (client.isConnecting == false && client.isConnected == false))
	}

	@Test("Disconnect becomes disabled after its first invocation and cannot quit twice")
	func disconnectActionAndValidationAgree() throws {
		let controller = MenuActionController()
		let coordinator = controller
		let client = TestClient()
		coordinator.pointedClient = client
		let connection = Connection(config: ConnectionConfig(), onClient: client)
		client.socket = connection
		client.isConnected = true
		client.markAsLoggedIn()
		defer {
			client.cancelDelayedDisconnect()
			connection.close()
		}
		let item = NSMenuItem()
		item.command = .disconnect

		#expect(coordinator.validateServerCommand(item))
		coordinator.disconnect(item)
		#expect(client.isQuitting)
		#expect(coordinator.validateServerCommand(item) == false)
		#expect(item.isHidden == false)
		let delayedDisconnect = try #require(client.pendingDisconnectTask)
		#expect(client.sentLines.count == 1)
		#expect((client.sentLines.firstObject as? String)?.hasPrefix("QUIT ") == true)
		let titleUpdateCount = client.recordedOutput.titleUpdates.count
		coordinator.disconnect(item)
		#expect(client.recordedOutput.titleUpdates.count == titleUpdateCount)
		#expect(client.sentLines.count == 1)
		#expect(!delayedDisconnect.isCancelled)

		client.cancelDelayedDisconnect()
		connection.close()
		#expect(!client.isQuitting)
		#expect(!client.isConnected)
		#expect(coordinator.validateServerCommand(item) == false)
		#expect(item.isHidden)
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

	/// The prefix names the defaults keys already on disk; changing it forgets
	/// every warning the user has suppressed.
	@Test("Suppressed warnings keep the defaults key prefix already written to disk")
	func suppressedWarningPolicyPreservesLegacyDefaultsPrefix() {
		#expect(MenuWindowPolicy.alertSuppressionPrefix == "Text Input Prompt Suppression -> ")
	}
}
