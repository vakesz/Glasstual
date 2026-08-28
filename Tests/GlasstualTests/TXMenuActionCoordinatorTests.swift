@testable import Glasstual
import XCTest

@MainActor
final class TXMenuActionCoordinatorTests: XCTestCase {
	func testMemberCommandsPreserveLegacyWireFormat() {
		XCTAssertEqual(MenuMemberCommand.ignore("Alice"), "ignore Alice")
		XCTAssertEqual(MenuMemberCommand.unignore("Alice"), "unignore Alice")
		XCTAssertEqual(
			MenuMemberCommand.mode("HALFOP", nicknames: ["Alice", "Bob"]),
			"HALFOP Alice Bob"
		)
		XCTAssertEqual(
			MenuMemberCommand.kickban("Alice", reason: "Requested"),
			"KICKBAN Alice Requested"
		)
		XCTAssertEqual(
			MenuMemberCommand.operatorCommand("GLINE", nickname: "Alice", reason: "Abuse"),
			"GLINE Alice Abuse"
		)
		XCTAssertEqual(
			MenuMemberCommand.setVhost("staff.example", nickname: "Alice"),
			"hs setall Alice staff.example"
		)
	}

	func testNavigationTagsMapToExistingResponderSelectors() {
		let mappings: [(Int, String)] = [
			(MenuNavigationTag.nextServer, "selectNextServer:"),
			(MenuNavigationTag.previousServer, "selectPreviousServer:"),
			(MenuNavigationTag.nextActiveServer, "selectNextActiveServer:"),
			(MenuNavigationTag.previousActiveServer, "selectPreviousActiveServer:"),
			(MenuNavigationTag.nextChannel, "selectNextChannel:"),
			(MenuNavigationTag.previousChannel, "selectPreviousChannel:"),
			(MenuNavigationTag.nextActiveChannel, "selectNextActiveChannel:"),
			(MenuNavigationTag.previousActiveChannel, "selectPreviousActiveChannel:"),
			(MenuNavigationTag.nextUnreadChannel, "selectNextUnreadChannel:"),
			(MenuNavigationTag.previousUnreadChannel, "selectPreviousUnreadChannel:"),
			(MenuNavigationTag.moveBackward, "selectPreviousWindow:"),
			(MenuNavigationTag.moveForward, "selectNextWindow:"),
			(MenuNavigationTag.previousSelection, "selectPreviousSelection:"),
		]

		for (tag, selectorName) in mappings {
			XCTAssertEqual(
				MenuActionCoordinator.navigationSelector(for: tag),
				NSSelectorFromString(selectorName)
			)
		}
	}

	func testNavigationIgnoresUnrelatedTags() {
		XCTAssertNil(MenuActionCoordinator.navigationSelector(for: 100))
	}

	func testMenuClosePolicyPreservesClickTimeSelectionUntilActionRuns() {
		XCTAssertTrue(
			MenuLifecyclePolicy.shouldResetSelectionAfterMenuCloses(performedAction: false)
		)
		XCTAssertFalse(
			MenuLifecyclePolicy.shouldResetSelectionAfterMenuCloses(performedAction: true)
		)
	}

	func testLifecycleCoordinatorKeepsObjectiveCRuntimeSurface() {
		let selectors = [
			"prepareInitialState",
			"prepareForApplicationTermination",
			"preferencesChanged",
			"menuWillOpen:",
			"menuDidClose:",
			"resetSelectedItems",
			"selectedClient",
			"selectedChannel",
			"selectedViewController",
			"selectedViewControllerBackingView",
		]

		for selectorName in selectors {
			XCTAssertTrue(MenuActionCoordinator.instancesRespond(to: NSSelectorFromString(selectorName)))
		}
	}

	func testServerConnectionActionsPreserveLegacyStateGuards() {
		XCTAssertTrue(MenuServerActionPolicy.canConnect(
			isConnecting: false,
			isConnected: false,
			isQuitting: false
		))
		XCTAssertFalse(MenuServerActionPolicy.canConnect(
			isConnecting: true,
			isConnected: false,
			isQuitting: false
		))
		XCTAssertTrue(MenuServerActionPolicy.canDisconnect(
			isConnecting: false,
			isConnected: true,
			isQuitting: false
		))
		XCTAssertFalse(MenuServerActionPolicy.canDisconnect(
			isConnecting: false,
			isConnected: true,
			isQuitting: true
		))
	}

	func testFindTagsPreserveMenuContracts() {
		XCTAssertEqual(MenuFindTag.open, 3_090_000)
		XCTAssertEqual(MenuFindTag.next, 3_090_001)
	}

	func testActionConcernCoordinatorKeepsObjectiveCRuntimeSurface() {
		let selectors = [
			"performEditingAction:sender:",
			"performChannelViewAction:sender:",
			"performServerChannelAction:sender:",
			"performSupportAction:sender:",
			"performIRCAction:sender:",
			"performWindowAction:sender:",
			"setNotificationsMuted:",
			"setNotificationSoundsMuted:",
			"performDialogAction:sender:",
			"showServerPropertiesForClient:selection:context:",
			"showNicknameColorSheetForNickname:",
			"channelInviteDidSelect:channelName:",
			"serverPropertiesDidAccept:config:",
			"nicknameColorDidAccept:",
			"channelTopicDidAccept:topic:",
			"channelModesDidAccept:modes:",
			"channelSpotlightDidSelect:channel:",
			"serverNicknameDidAccept:nickname:",
			"dialogDidClose:",
			"preferencesDialogDidClose:",
			"messageReplyItemsForMessageIdentifier:nickname:excerpt:",
			"shareMenuItemForItems:",
			"selectedMembersForSender:returnNicknames:",
			"deselectMembersForSender:",
			"performMemberAction:sender:",
			"sendDroppedFilesToSelectedChannel:",
			"sendDroppedFiles:row:",
			"sendDroppedFiles:nickname:",
			"navigateToTreeItemAtURL:",
			"navigateToTreeItemWithIdentifier:",
			"navigateToTreeItem:",
			"populateNavigationChannelList",
			"navigateToChannelInNavigationList:",
			"performNavigationAction:",
			"moveHighlightOrScrollbackForTag:",
			"validateMenuItem:",
		]

		for selectorName in selectors {
			XCTAssertTrue(MenuActionCoordinator.instancesRespond(to: NSSelectorFromString(selectorName)))
		}
	}

	func testActionRawValuesPreserveObjectiveCContracts() {
		XCTAssertEqual(TXMenuMemberAction.allCases.map(\.rawValue), Array(0 ... 28))
		XCTAssertEqual(TXMenuEditingAction.allCases.map(\.rawValue), Array(0 ... 3))
		XCTAssertEqual(TXMenuChannelViewAction.allCases.map(\.rawValue), Array(0 ... 12))
		XCTAssertEqual(TXMenuServerChannelAction.allCases.map(\.rawValue), Array(0 ... 14))
		XCTAssertEqual(TXMenuSupportAction.allCases.map(\.rawValue), Array(0 ... 5))
		XCTAssertEqual(TXMenuIRCAction.allCases.map(\.rawValue), Array(0 ... 5))
		XCTAssertEqual(TXMenuWindowAction.allCases.map(\.rawValue), Array(0 ... 16))
		XCTAssertEqual(TXMenuDialogAction.allCases.map(\.rawValue), Array(0 ... 14))
	}

	func testChannelModeTagsPreserveLegacyModeCommands() {
		XCTAssertEqual(MenuChannelModePolicy.removeModeratedTag, 6_090_001)
		XCTAssertEqual(MenuChannelModePolicy.removeInviteOnlyTag, 6_090_003)
		XCTAssertEqual(MenuChannelModePolicy.moderationMode(for: 0), "+m")
		XCTAssertEqual(MenuChannelModePolicy.moderationMode(for: 6_090_001), "-m")
		XCTAssertEqual(MenuChannelModePolicy.inviteMode(for: 0), "+i")
		XCTAssertEqual(MenuChannelModePolicy.inviteMode(for: 6_090_003), "-i")
	}

	func testAppearanceTogglePolicyPreservesLegacyCycle() {
		XCTAssertEqual(MenuWindowPolicy.nextAppearance(current: .inherited, systemIsDark: false), .dark)
		XCTAssertEqual(MenuWindowPolicy.nextAppearance(current: .inherited, systemIsDark: true), .light)
		XCTAssertEqual(MenuWindowPolicy.nextAppearance(current: .light, systemIsDark: false), .dark)
		XCTAssertEqual(MenuWindowPolicy.nextAppearance(current: .dark, systemIsDark: false), .light)
	}

	func testSuppressedWarningPolicyPreservesLegacyDefaultsPrefix() {
		XCTAssertEqual(MenuWindowPolicy.alertSuppressionPrefix, "Text Input Prompt Suppression -> ")
	}

	func testNativeMenuControllerKeepsLegacyRuntimeClassAndCoreSelectors() {
		XCTAssertTrue(NSClassFromString("TXMenuController") === TXMenuController.self)

		let selectors = [
			"prepareInitialState",
			"applySymbolsToMenu:",
			"prepareForApplicationTermination",
			"preferencesChanged",
			"validateMenuItem:",
			"menuWillOpen:",
			"menuDidClose:",
			"resetSelectedItems",
			"selectedClient",
			"selectedChannel",
			"selectedViewController",
			"selectedViewControllerBackingView",
			"checkSelectedMembers:",
			"selectedMembers:",
			"selectedMembersNicknames:",
			"deselectMembers:",
			"populateNavigationChannelList",
			"toggleMuteOnNotificationsShortcutOn:",
			"toggleMuteOnNotificationSoundsShortcutOn:",
			"memberChangeColor:",
			"memberSendDroppedFilesToSelectedChannel:",
			"navigateToTreeItemAtURL:",
			"navigateToTreeItemWithIdentifier:",
			"navigateToTreeItem:",
		]

		for selectorName in selectors {
			XCTAssertTrue(
				TXMenuController.instancesRespond(to: NSSelectorFromString(selectorName)),
				"Missing legacy selector: \(selectorName)"
			)
		}
	}

	func testNativeMenuControllerKeepsNibActionsOutletsAndDialogCallbacks() {
		let selectors = [
			"setChannelViewChannelNameMenu:",
			"setChannelViewGeneralMenu:",
			"setChannelViewURLMenu:",
			"setDockMenu:",
			"setMainMenuNavigationChannelListMenu:",
			"setMainMenuChannelMenu:",
			"setMainMenuQueryMenu:",
			"setMainMenuChannelMenuItem:",
			"setMainMenuQueryMenuItem:",
			"setMainMenuServerMenuItem:",
			"setMainWindowSegmentedControllerCellMenu:",
			"setServerListNoSelectionMenu:",
			"setUserControlMenu:",
			"showFindPrompt:",
			"copy:",
			"paste:",
			"print:",
			"connect:",
			"joinChannel:",
			"memberSendWhois:",
			"openLogLocation:",
			"showMainWindow:",
			"performNavigationAction:",
			"showChannelPropertiesSheet:",
			"showServerPropertiesSheet:",
			"showPreferencesWindow:",
			"showOnboardingWindow:",
			"channelInviteSheet:onSelectChannel:",
			"serverPropertiesSheet:onOk:",
			"channelModifyTopicSheet:onOk:",
			"channelModifyModesSheet:onOk:",
			"channelSpotlightController:selectChannel:",
			"serverChangeNicknameSheet:didInputNickname:",
			"preferencesDialogWillClose:",
		]

		for selectorName in selectors {
			XCTAssertTrue(
				TXMenuController.instancesRespond(to: NSSelectorFromString(selectorName)),
				"Missing nib or delegate selector: \(selectorName)"
			)
		}

		XCTAssertTrue(
			NSClassFromString("TXMenuControllerMainWindowProxy") === TXMenuControllerMainWindowProxy.self
		)
		XCTAssertTrue(
			TXMenuControllerMainWindowProxy
				.instancesRespond(to: #selector(TXMenuControllerMainWindowProxy.showOnboardingWindow(_:)))
		)
	}
}
