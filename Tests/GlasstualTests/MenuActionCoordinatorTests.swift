@testable import Glasstual
import Testing

@MainActor
@Suite("Menu action coordinator")
struct MenuActionCoordinatorTests {
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
			#expect(MenuActionCoordinator.navigationAction(for: command) == action)
		}

		/* Every action has to be reachable from a command, or a menu item
		 exists that nothing can invoke. */
		#expect(
			Set(mappings.map(\.1).map(String.init(describing:))).count == MenuNavigationAction.allCases.count
		)
	}

	@Test("A command that belongs to no navigation item is not treated as navigation")
	func navigationIgnoresUnrelatedCommands() {
		#expect(MenuActionCoordinator.navigationAction(for: .about) == nil)
		#expect(MenuActionCoordinator.navigationAction(for: nil) == nil)
	}

	@Test("The click-time selection is kept until the action it was captured for has run")
	func menuClosePolicyPreservesClickTimeSelectionUntilActionRuns() {
		#expect(MenuLifecyclePolicy.shouldResetSelectionAfterMenuCloses(performedAction: false))
		#expect(MenuLifecyclePolicy.shouldResetSelectionAfterMenuCloses(performedAction: true) == false)
	}

	@Test("Connect and disconnect stay guarded by the connection state they were guarded by")
	func serverConnectionActionsPreserveLegacyStateGuards() {
		#expect(MenuServerActionPolicy.canConnect(
			isConnecting: false,
			isConnected: false,
			isQuitting: false
		))
		#expect(MenuServerActionPolicy.canConnect(
			isConnecting: true,
			isConnected: false,
			isQuitting: false
		) == false)
		#expect(MenuServerActionPolicy.canDisconnect(
			isConnecting: false,
			isConnected: true,
			isQuitting: false
		))
		#expect(MenuServerActionPolicy.canDisconnect(
			isConnecting: false,
			isConnected: true,
			isQuitting: true
		) == false)
	}

	@Test("A channel-mode command decides whether the mode is set or removed")
	func channelModeCommandsChooseTheModeChange() {
		#expect(MenuChannelModePolicy.moderationMode(for: .channelModeModerated) == "+m")
		#expect(MenuChannelModePolicy.moderationMode(for: .channelModeUnmoderated) == "-m")
		#expect(MenuChannelModePolicy.moderationMode(for: nil) == "+m")
		#expect(MenuChannelModePolicy.inviteMode(for: .channelModeInviteOnly) == "+i")
		#expect(MenuChannelModePolicy.inviteMode(for: .channelModeAnyoneCanJoin) == "-i")
		#expect(MenuChannelModePolicy.inviteMode(for: nil) == "+i")
	}

	@Test("The appearance toggle cycles away from whatever the system is showing")
	func appearanceTogglePolicyPreservesLegacyCycle() {
		#expect(MenuWindowPolicy.nextAppearance(current: .inherited, systemIsDark: false) == .dark)
		#expect(MenuWindowPolicy.nextAppearance(current: .inherited, systemIsDark: true) == .light)
		#expect(MenuWindowPolicy.nextAppearance(current: .light, systemIsDark: false) == .dark)
		#expect(MenuWindowPolicy.nextAppearance(current: .dark, systemIsDark: false) == .light)
	}

	/// The prefix names the defaults keys already on disk; changing it forgets
	/// every warning the user has suppressed.
	@Test("Suppressed warnings keep the defaults key prefix already written to disk")
	func suppressedWarningPolicyPreservesLegacyDefaultsPrefix() {
		#expect(MenuWindowPolicy.alertSuppressionPrefix == "Text Input Prompt Suppression -> ")
	}
}
