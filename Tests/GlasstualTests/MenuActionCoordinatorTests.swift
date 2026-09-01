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

	@Test("Every navigation action is reachable from the tag its menu item carries")
	func navigationTagsMapToNavigationActions() {
		let mappings: [(Int, MenuNavigationAction)] = [
			(MenuNavigationTag.nextServer, .nextServer),
			(MenuNavigationTag.previousServer, .previousServer),
			(MenuNavigationTag.nextActiveServer, .nextActiveServer),
			(MenuNavigationTag.previousActiveServer, .previousActiveServer),
			(MenuNavigationTag.nextChannel, .nextChannel),
			(MenuNavigationTag.previousChannel, .previousChannel),
			(MenuNavigationTag.nextActiveChannel, .nextActiveChannel),
			(MenuNavigationTag.previousActiveChannel, .previousActiveChannel),
			(MenuNavigationTag.nextUnreadChannel, .nextUnreadChannel),
			(MenuNavigationTag.previousUnreadChannel, .previousUnreadChannel),
			(MenuNavigationTag.moveBackward, .moveBackward),
			(MenuNavigationTag.moveForward, .moveForward),
			(MenuNavigationTag.previousSelection, .previousSelection),
		]

		for (tag, action) in mappings {
			#expect(MenuActionCoordinator.navigationAction(for: tag) == action)
		}

		/* Every action has to be reachable from a tag, or a menu item exists
		 that nothing can invoke. */
		#expect(
			Set(mappings.map(\.1).map(String.init(describing:))).count == MenuNavigationAction.allCases.count
		)
	}

	@Test("A tag that belongs to no navigation item is not treated as navigation")
	func navigationIgnoresUnrelatedTags() {
		#expect(MenuActionCoordinator.navigationAction(for: 100) == nil)
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

	@Test("Find commands keep stable identifiers for non-menu callers")
	func findTagsPreserveMenuContracts() {
		#expect(MenuFindTag.open == 3_090_000)
		#expect(MenuFindTag.next == 3_090_001)
	}

	@Test("A channel-mode command decides whether the mode is set or removed")
	func channelModeTagsPreserveLegacyModeCommands() {
		#expect(MenuChannelModePolicy.removeModeratedTag == 6_090_001)
		#expect(MenuChannelModePolicy.removeInviteOnlyTag == 6_090_003)
		#expect(MenuChannelModePolicy.moderationMode(for: 0) == "+m")
		#expect(MenuChannelModePolicy.moderationMode(for: 6_090_001) == "-m")
		#expect(MenuChannelModePolicy.inviteMode(for: 0) == "+i")
		#expect(MenuChannelModePolicy.inviteMode(for: 6_090_003) == "-i")
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
