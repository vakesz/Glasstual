// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("UI shell localized copy")
struct UIShellLocalizationCatalogTests {
	@Test("Onboarding copy is resolved by role, and its counted step is formatted")
	func onboardingBoundaryResolvesSemanticCopyAndFormatting() {
		#expect(String(localized: .Onboarding.windowChromeWelcomeToGlasstual) == "Welcome to Glasstual")
		#expect(String(localized: .Onboarding.windowChromeStep(2, 4)) == "Step 2 of 4")
		#expect(String(localized: .Onboarding.stepWelcomeAndIdentityNickname) == "Nickname")
		#expect(
			String(localized: .Onboarding.usedWhenYourNicknameIsAlready) ==
				"Used when your nickname is already taken. Optional."
		)
		#expect(OnboardingTextSize.allCases.map { String(localized: $0.title) } == ["Small", "Medium", "Large"])
		#expect(
			PreferredAppearance.allCases.map { String(localized: $0.onboardingTitle) }
				== ["System", "Light", "Dark"]
		)
		#expect(
			String(localized: .Onboarding.notificationsAreAllowedForGlasstual)
				== "Notifications are allowed for Glasstual."
		)
		#expect(String(localized: .Onboarding.suggestedChannels) == "Suggested channels")
		#expect(String(localized: .Onboarding.customServer) == "Custom Server")
		#expect(String(localized: .Onboarding.enterAPortBetween1) == "Enter a port between 1 and 65535.")
	}

	@Test("Server properties copy is keyed by domain types and keeps its multiline shape")
	func serverPropertiesBoundaryUsesDomainTypesAndPreservesMultilineCopy() {
		#expect(String(localized: AddressBookEntryType.ignore.listTitle) == "User Ignore")
		#expect(String(localized: AddressBookEntryType.userTracking.listTitle) == "User Tracking")
		#expect(String(localized: HighlightMatchBehavior.exclude.title) == "Exclude")
		#expect(String(localized: HighlightMatchBehavior.include.title) == "Match")
		#expect(
			[
				String(localized: .ServerProperties.navigationSectionConnection),
				String(localized: .ServerProperties.vendorSpecific),
				String(localized: .ServerProperties.serverPropertiesNavigationMenuAdvanced),
				String(localized: .ServerProperties.addressBook),
				String(localized: .ServerProperties.channelList),
				String(localized: .ServerProperties.connectCommands),
				String(localized: .ServerProperties.serverPropertiesNavigationMenuEncoding),
				String(localized: .ServerProperties.serverPropertiesNavigationMenuGeneral),
				String(localized: .ServerProperties.serverPropertiesNavigationMenuIdentity),
				String(localized: .ServerProperties.serverPropertiesNavigationMenuHighlights),
				String(localized: .ServerProperties.serverPropertiesNavigationMenuMessages),
				String(localized: .ServerProperties.zncBouncer),
				String(localized: .ServerProperties.clientCertificate),
				String(localized: .ServerProperties.floodControl),
				String(localized: .ServerProperties.networkSocket),
				String(localized: .ServerProperties.proxyServer),
			] == [
				"Connection", "Vendor Specific", "Advanced", "Address Book", "Channel List",
				"Connect Commands", "Encoding", "General", "Identity", "Highlights", "Messages",
				"ZNC Bouncer", "Client Certificate", "Flood Control", "Network Socket", "Proxy Server",
			]
		)
		#expect(
			String(localized: .ServerProperties.pleaseEnterAListOfProperly("bad nick")) ==
				"“bad nick” is not a valid nickname. Separate alternative nicknames with spaces, "
				+ "for example: Guest1 Guest2 Guest3"
		)
		#expect(
			String(localized: .ServerProperties.includesTheFollowingCipherSuites("Default list")) ==
				"The “Default list” prefers these cipher suites, most preferred first."
		)
		/* The alert asks whether to reload, and its buttons are Cancel and
		 Reload -- so the body cannot name a "Yes" button that is not there. */
		#expect(String(localized: .ServerProperties.thisConnectionsConfigurationHasChangedDo)
			== "Reload the connection’s settings?")
		#expect(
			String(localized: .ServerProperties.youWillLooseUnsavedChangesIf) ==
				"Your unsaved changes will be discarded."
		)
	}

	@Test("Main window copy is keyed by the typed status and the typed member rank")
	func mainWindowBoundaryUsesTypedStatusAndRankMappings() {
		#expect(MemberListRanks.privilegeDescription(for: .normalOperator) == "Operator")
		/* A rank column reads down; "No Privileges" was a sentence where every
		 other row held a word. */
		#expect(MemberListRanks.privilegeDescription(for: .none) == "None")
		/* One name per concept: the privilege and the section a server operator
		 is grouped under used to disagree with each other. */
		#expect(MemberListRanks.privilegeDescription(for: .irCopByMode) == "Server Staff")
		#expect(MemberListRanks.privilegeDescription(for: .superOperator) == "Admin")
		#expect(MemberListRanks.sectionTitle(for: .superOperator) == "Admins")
		#expect(MemberListRanks.privilegeDescription(for: .halfOperator) == "Half-Operator")
		#expect(MemberListRanks.sectionTitle(for: .halfOperator) == "Half-Operators")
		#expect(MemberListRanks.sectionTitle(for: .irCopByMode) == "Server Staff")
		#expect(MemberListRanks.sectionTitle(for: .none) == "Members")
		#expect(String(localized: .MemberList.loggedInAs("alice")) == "Logged in as alice")
		#expect(MainWindowConnectionStatus.disconnected.title == "Disconnected")
		#expect(MainWindowConnectionStatus.waitingToReconnect.title == "Waiting to reconnect")
		#expect(MainWindowConnectionStatus.connecting.title == "Connecting")
		#expect(MainWindowConnectionStatus.reconnecting.title == "Reconnecting")
		#expect(MainWindowConnectionStatus.loggingOn.title == "Logging on")
		#expect(MainWindowConnectionStatus.disconnecting.title == "Disconnecting")
		/* "1 users" was the subtitle of every one-member channel; the digits
		 are still grouped the way the reader's locale groups them. */
		#expect(MainWindowTitleContent.memberCount(1) == "1 member")
		#expect(
			MainWindowTitleContent.memberCount(1234)
				== "\(1234.formatted(.number)) members"
		)
		#expect(String(localized: .MainWindow.awayNickname("alice")) == "alice (away)")
		#expect(MenuCommand.serverListTitle(isVisible: false) == "Show Server List")
		#expect(MenuCommand.serverListTitle(isVisible: true) == "Hide Server List")
		#expect(MenuCommand.memberListTitle(isVisible: false) == "Show Member List")
		#expect(MenuCommand.memberListTitle(isVisible: true) == "Hide Member List")
		#expect(String(localized: .MainWindow.dockIconBadgeShown("9,999")) == "9,999+")
		#expect(InputAccessoryView.replyTarget(nil) == "Replying to a message")
		#expect(InputAccessoryView.replyTarget("alice") == "Replying to alice")
		#expect(InputAccessoryView.typingCaption(for: ["alice"]) == "alice is typing…")
		#expect(InputAccessoryView.typingCaption(for: ["alice", "bob"]) == "alice and bob are typing…")
		#expect(InputAccessoryView.typingCaption(for: ["alice", "bob", "carol"]) == "3 people are typing…")
	}

	/// The placeholder contract of the multi-argument entries, which is what a
	/// careless catalog edit actually breaks. Everything structural about
	/// these tables is covered by `StringCatalogStructureTests`.
	@Test("Multi-argument entries keep their placeholder contracts")
	func multiArgumentValuesKeepTheirPlaceholderContracts() throws {
		let expectedValues = [
			"Onboarding": ["window-chrome-step": "Step %1$ld of %2$ld"],
			"ServerProperties": [
				"please-enter-a-list-of-properly":
					"“%@” is not a valid nickname. Separate alternative nicknames with spaces, "
					+ "for example: Guest1 Guest2 Guest3",
				"includes-the-following-cipher-suites":
					"The “%@” prefers these cipher suites, most preferred first.",
				"copy-nickserv-command-for": "Copy NickServ Command for %@",
			],
			"ChannelProperties": [
				"secret-key-length": "%1$ld of %2$ld bytes",
				"secret-key-too-long":
					"%1$@ accepts at most %2$ld bytes. Anything past that may be cut off.",
			],
			/* The member-list entries moved into the feature's own catalog with
				the list itself. */
			"MemberList": [
				"logged-in-as": "Logged in as %@",
			],
			"MainWindow": [
				"dock-icon-badge-shown": "%@+",
				"input-bar-reply-banner-replying": "Replying to %@",
				/* The count twice: as text for the digits, as a number for the
					noun's plural form. */
				"main-window-connection-status-users": "%1$@ %#@count@",
				"is-typing": "%@ is typing…",
				"are-typing": "%@ and %@ are typing…",
			],
		]

		for (tableName, values) in expectedValues {
			let catalog = try catalog(named: tableName)
			for (key, expectedValue) in values {
				#expect(
					catalog.strings[key]?.localizations["en"]?.stringUnit?.value == expectedValue,
					"\(tableName):\(key)"
				)
			}
		}
	}

	/// A catalog lives beside the feature that owns it, so it is found by its
	/// own name rather than in one fixed directory.
	private func catalog(named tableName: String) throws -> UIShellCatalog {
		let sourcesURL = URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.appending(path: "Sources/App")
		guard let walker = FileManager.default.enumerator(at: sourcesURL, includingPropertiesForKeys: nil) else {
			throw CatalogLookupError.notFound(tableName)
		}

		for case let url as URL in walker where url.lastPathComponent == "\(tableName).xcstrings" {
			return try JSONDecoder().decode(UIShellCatalog.self, from: Data(contentsOf: url))
		}

		throw CatalogLookupError.notFound(tableName)
	}

	private enum CatalogLookupError: Error {
		case notFound(String)
	}
}

private struct UIShellCatalog: Decodable {
	let sourceLanguage: String
	let strings: [String: UIShellCatalogEntry]
	let version: String
}

private struct UIShellCatalogEntry: Decodable {
	let comment: String
	let extractionState: String
	let localizations: [String: UIShellCatalogLocalization]
}

private struct UIShellCatalogLocalization: Decodable {
	/// Absent on entries that carry plural variations instead.
	let stringUnit: UIShellCatalogStringUnit?
}

private struct UIShellCatalogStringUnit: Decodable {
	let state: String
	let value: String
}
