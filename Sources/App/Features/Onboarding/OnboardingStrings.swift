/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import Foundation

struct OnboardingAppearancePreviewMessage: Equatable {
	let nickname: String
	let message: String
}

nonisolated enum OnboardingTextSize: CaseIterable { // nonisolated: value
	case small
	case medium
	case large

	var title: String {
		switch self {
		case .small:
			String(localized: .TDCOnboardingWindow.stepLookAndFeelSmall)
		case .medium:
			String(localized: .TDCOnboardingWindow.stepLookAndFeelMedium)
		case .large:
			String(localized: .TDCOnboardingWindow.stepLookAndFeelLarge)
		}
	}
}

nonisolated enum OnboardingInterfaceStyle: CaseIterable { // nonisolated: value
	case system
	case light
	case dark

	var title: String {
		switch self {
		case .system:
			String(localized: .TDCOnboardingWindow.stepLookAndFeelSystem)
		case .light:
			String(localized: .TDCOnboardingWindow.stepLookAndFeelLight)
		case .dark:
			String(localized: .TDCOnboardingWindow.stepLookAndFeelDark)
		}
	}
}

nonisolated enum OnboardingStrings { // nonisolated: value
	enum Window {
		static var title: String {
			String(localized: .TDCOnboardingWindow.windowChromeWelcomeToGlasstual)
		}

		static var backButton: String {
			String(localized: .TDCOnboardingWindow.windowChromeBack)
		}

		static var continueButton: String {
			String(localized: .TDCOnboardingWindow.windowChromeContinue)
		}

		static var finishButton: String {
			String(localized: .TDCOnboardingWindow.windowChromeFinish)
		}

		static var skipButton: String {
			String(localized: .TDCOnboardingWindow.windowChromeSkip)
		}

		static func progress(currentStep: Int, totalSteps: Int) -> String {
			String(localized: .TDCOnboardingWindow.windowChromeStep(currentStep, totalSteps))
		}
	}

	enum Identity {
		static var title: String {
			String(localized: .TDCOnboardingWindow.welcomeToGlasstual)
		}

		static var subtitle: String {
			String(localized: .TDCOnboardingWindow.glasstualIsAnIrcClientBuilt)
		}

		static var nicknameLabel: String {
			String(localized: .TDCOnboardingWindow.stepWelcomeAndIdentityNickname)
		}

		static var realNameLabel: String {
			String(localized: .TDCOnboardingWindow.realName)
		}

		static var alternateNicknameLabel: String {
			String(localized: .TDCOnboardingWindow.alternateNickname)
		}

		static var alternateNicknameHelp: String {
			String(localized: .TDCOnboardingWindow.usedWhenYourNicknameIsAlready)
		}

		static var nicknamePlaceholder: String {
			String(localized: .TDCOnboardingWindow.nickname)
		}

		static var realNamePlaceholder: String {
			String(localized: .TDCOnboardingWindow.yourNameOrAnythingYouLike)
		}

		static var optionalPlaceholder: String {
			String(localized: .TDCOnboardingWindow.stepWelcomeAndIdentityOptional)
		}
	}

	enum Appearance {
		static var title: String {
			String(localized: .TDCOnboardingWindow.lookAndFeel)
		}

		static var subtitle: String {
			String(localized: .TDCOnboardingWindow.chooseHowConversationsAreDisplayed)
		}

		static var bubblesTitle: String {
			String(localized: .TDCOnboardingWindow.stepLookAndFeelBubbles)
		}

		static var bubblesDescription: String {
			String(localized: .TDCOnboardingWindow.messagesInRoundedBubbles)
		}

		static var linesTitle: String {
			String(localized: .TDCOnboardingWindow.stepLookAndFeelLines)
		}

		static var linesDescription: String {
			String(localized: .TDCOnboardingWindow.classicLineByLineView)
		}

		static var textSizeLabel: String {
			String(localized: .TDCOnboardingWindow.textSize)
		}

		static var interfaceStyleLabel: String {
			String(localized: .TDCOnboardingWindow.stepLookAndFeelAppearance)
		}

		static var previewAccessibilityLabel: String {
			String(localized: .TDCOnboardingWindow.chatStyle)
		}

		static var previewTime: String {
			String(localized: .TDCOnboardingWindow.stepLookAndFeel)
		}

		static var textSizeTitles: [String] {
			OnboardingTextSize.allCases.map(\.title)
		}

		static var interfaceStyleTitles: [String] {
			OnboardingInterfaceStyle.allCases.map(\.title)
		}

		static var previewMessages: [OnboardingAppearancePreviewMessage] {
			[
				OnboardingAppearancePreviewMessage(
					nickname: String(localized: .TDCOnboardingWindow.stepLookAndFeelAlice),
					message: String(localized: .TDCOnboardingWindow.goodMorningEveryone)
				),
				OnboardingAppearancePreviewMessage(
					nickname: String(localized: .TDCOnboardingWindow.stepLookAndFeelBob),
					message: String(localized: .TDCOnboardingWindow.morningAnyoneTriedTheNewBuild)
				),
				OnboardingAppearancePreviewMessage(
					nickname: String(localized: .TDCOnboardingWindow.stepLookAndFeelYou),
					message: String(localized: .TDCOnboardingWindow.yesItWorksWellSoFar)
				),
			]
		}
	}

	enum Notifications {
		static var title: String {
			String(localized: .TDCOnboardingWindow.stepNotifications)
		}

		static var subtitle: String {
			String(localized: .TDCOnboardingWindow.chooseWhatGlasstualShouldTell)
		}

		static var mentionCheckbox: String {
			String(localized: .TDCOnboardingWindow.notifyMeWhenSomeoneMentionsMe)
		}

		static var privateMessageCheckbox: String {
			String(localized: .TDCOnboardingWindow.notifyMeAboutPrivateMessages)
		}

		static var soundCheckbox: String {
			String(localized: .TDCOnboardingWindow.playSounds)
		}

		static var permissionExplanation: String {
			String(localized: .TDCOnboardingWindow.glasstualWillAskMacosForPermission)
		}

		static var permissionGranted: String {
			String(localized: .TDCOnboardingWindow.notificationsAreAllowedForGlasstual)
		}

		static var permissionDenied: String {
			String(localized: .TDCOnboardingWindow.notificationsAreTurnedOffForGlasstual)
		}
	}

	enum FirstNetwork {
		static var title: String {
			String(localized: .TDCOnboardingWindow.yourFirstNetwork)
		}

		static var subtitle: String {
			String(localized: .TDCOnboardingWindow.pickANetworkToJoin)
		}

		static var connectWhenFinished: String {
			String(localized: .TDCOnboardingWindow.connectWhenFinished)
		}

		static var suggestedChannelsLabel: String {
			String(localized: .TDCOnboardingWindow.suggestedChannels)
		}

		static var suggestedChannelsPlaceholder: String {
			String(localized: .TDCOnboardingWindow.chooseANetworkToSeeSuggested)
		}

		static var invalidNetwork: String {
			String(localized: .TDCOnboardingWindow.pleaseCheckTheNetworkDetails)
		}
	}

	enum NetworkPicker {
		static var searchPlaceholder: String {
			String(localized: .TDCOnboardingWindow.searchNetworks)
		}

		static var accessibilityLabel: String {
			String(localized: .TDCOnboardingWindow.networkPickerNetworks)
		}

		static var popularGroup: String {
			String(localized: .TDCOnboardingWindow.networkPickerPopular)
		}

		static var allNetworksGroup: String {
			String(localized: .TDCOnboardingWindow.allNetworks)
		}

		static var customServerTitle: String {
			String(localized: .TDCOnboardingWindow.customServer)
		}

		static var customServerDescription: String {
			String(localized: .TDCOnboardingWindow.connectToAnyIrcServer)
		}

		static var secureConnectionAccessibilityLabel: String {
			String(localized: .TDCOnboardingWindow.secureConnection)
		}

		static var serverAddressLabel: String {
			String(localized: .TDCOnboardingWindow.serverAddress)
		}

		static var serverAddressPlaceholder: String {
			String(localized: .TDCOnboardingWindow.ircExampleOrg)
		}

		static var portLabel: String {
			String(localized: .TDCOnboardingWindow.networkPickerPort)
		}

		static var portPlaceholder: String {
			String(localized: .TDCOnboardingWindow.networkPicker)
		}

		static var useTLSCheckbox: String {
			String(localized: .TDCOnboardingWindow.useSslTls)
		}

		static var accountGroup: String {
			String(localized: .TDCOnboardingWindow.networkPickerAccount)
		}

		static var accountNameLabel: String {
			String(localized: .TDCOnboardingWindow.accountName)
		}

		static var passwordLabel: String {
			String(localized: .TDCOnboardingWindow.networkPickerPassword)
		}

		static var useSASLCheckbox: String {
			String(localized: .TDCOnboardingWindow.signInWithSasl)
		}

		static var registrationRequired: String {
			String(localized: .TDCOnboardingWindow.registrationRequired)
		}

		static var missingServer: String {
			String(localized: .TDCOnboardingWindow.chooseANetworkOrEnter)
		}

		static var invalidPort: String {
			String(localized: .TDCOnboardingWindow.enterAPortBetween1)
		}
	}
}
