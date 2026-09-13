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

extension OnboardingTextSize {
	var title: String {
		switch self {
		case .small:
			String(localized: .Onboarding.stepLookAndFeelSmall)
		case .medium:
			String(localized: .Onboarding.stepLookAndFeelMedium)
		case .large:
			String(localized: .Onboarding.stepLookAndFeelLarge)
		}
	}
}

enum OnboardingStrings {
	enum Window {
		static var connectionUnavailable: String {
			String(localized: .Onboarding.connectionUnavailable)
		}

		static var connectionUnavailableRecovery: String {
			String(localized: .Onboarding.connectionUnavailableRecovery)
		}

		static var title: String {
			String(localized: .Onboarding.windowChromeWelcomeToGlasstual)
		}

		static var backButton: String {
			String(localized: .Onboarding.windowChromeBack)
		}

		static var continueButton: String {
			String(localized: .Onboarding.windowChromeContinue)
		}

		static var finishButton: String {
			String(localized: .Onboarding.windowChromeFinish)
		}

		static var skipButton: String {
			String(localized: .Onboarding.windowChromeSkip)
		}

		static var setUpLaterButton: String {
			String(localized: .Onboarding.windowChromeSetUpLater)
		}

		static func progress(currentStep: Int, totalSteps: Int) -> String {
			String(localized: .Onboarding.windowChromeStep(currentStep, totalSteps))
		}
	}

	enum Identity {
		static var title: String {
			String(localized: .Onboarding.welcomeToGlasstual)
		}

		static var subtitle: String {
			String(localized: .Onboarding.glasstualIsAnIrcClientBuilt)
		}

		static var nicknameLabel: String {
			String(localized: .Onboarding.stepWelcomeAndIdentityNickname)
		}

		static var nicknameRequired: String {
			String(localized: .Onboarding.stepWelcomeAndIdentityNicknameRequired)
		}

		static var realNameLabel: String {
			String(localized: .Onboarding.realName)
		}

		static var alternateNicknameLabel: String {
			String(localized: .Onboarding.alternateNickname)
		}

		static var alternateNicknameHelp: String {
			String(localized: .Onboarding.usedWhenYourNicknameIsAlready)
		}

		static var nicknamePlaceholder: String {
			String(localized: .Onboarding.nickname)
		}

		static var realNamePlaceholder: String {
			String(localized: .Onboarding.yourNameOrAnythingYouLike)
		}

		static var optionalPlaceholder: String {
			String(localized: .Onboarding.stepWelcomeAndIdentityOptional)
		}
	}

	enum Appearance {
		static var title: String {
			String(localized: .Onboarding.lookAndFeel)
		}

		static var subtitle: String {
			String(localized: .Onboarding.chooseHowConversationsAreDisplayed)
		}

		static var bubblesTitle: String {
			String(localized: .Onboarding.stepLookAndFeelBubbles)
		}

		static var bubblesDescription: String {
			String(localized: .Onboarding.messagesInRoundedBubbles)
		}

		static var linesTitle: String {
			String(localized: .Onboarding.stepLookAndFeelLines)
		}

		static var linesDescription: String {
			String(localized: .Onboarding.classicLineByLineView)
		}

		static var textSizeLabel: String {
			String(localized: .Onboarding.textSize)
		}

		static var interfaceStyleLabel: String {
			String(localized: .Onboarding.stepLookAndFeelAppearance)
		}

		static var previewAccessibilityLabel: String {
			String(localized: .Onboarding.chatStyle)
		}

		static var previewTime: String {
			String(localized: .Onboarding.stepLookAndFeel)
		}

		/// One title per case of `PreferredAppearance`, so the picker cannot
		/// drift out of step with the tags it sets.
		static func interfaceStyleTitle(_ appearance: PreferredAppearance) -> String {
			switch appearance {
			case .inherited: String(localized: .Onboarding.stepLookAndFeelSystem)
			case .light: String(localized: .Onboarding.stepLookAndFeelLight)
			case .dark: String(localized: .Onboarding.stepLookAndFeelDark)
			}
		}

		static var previewMessages: [OnboardingAppearancePreviewMessage] {
			[
				OnboardingAppearancePreviewMessage(
					nickname: String(localized: .Onboarding.stepLookAndFeelAlice),
					message: String(localized: .Onboarding.goodMorningEveryone)
				),
				OnboardingAppearancePreviewMessage(
					nickname: String(localized: .Onboarding.stepLookAndFeelBob),
					message: String(localized: .Onboarding.morningAnyoneTriedTheNewBuild)
				),
				OnboardingAppearancePreviewMessage(
					nickname: String(localized: .Onboarding.stepLookAndFeelYou),
					message: String(localized: .Onboarding.yesItWorksWellSoFar)
				),
			]
		}
	}

	enum Notifications {
		static var title: String {
			String(localized: .Onboarding.stepNotifications)
		}

		static var subtitle: String {
			String(localized: .Onboarding.chooseWhatGlasstualShouldTell)
		}

		static var mentionCheckbox: String {
			String(localized: .Onboarding.notifyMeWhenSomeoneMentionsMe)
		}

		static var privateMessageCheckbox: String {
			String(localized: .Onboarding.notifyMeAboutPrivateMessages)
		}

		static var soundCheckbox: String {
			String(localized: .Onboarding.playSounds)
		}

		static var permissionExplanation: String {
			String(localized: .Onboarding.glasstualWillAskMacosForPermission)
		}

		static var permissionGranted: String {
			String(localized: .Onboarding.notificationsAreAllowedForGlasstual)
		}

		static var permissionDenied: String {
			String(localized: .Onboarding.notificationsAreTurnedOffForGlasstual)
		}
	}

	enum FirstNetwork {
		static var title: String {
			String(localized: .Onboarding.yourFirstNetwork)
		}

		static var subtitle: String {
			String(localized: .Onboarding.pickANetworkToJoin)
		}

		static var connectWhenFinished: String {
			String(localized: .Onboarding.connectWhenFinished)
		}

		static var suggestedChannelsLabel: String {
			String(localized: .Onboarding.suggestedChannels)
		}

		static var suggestedChannelsPlaceholder: String {
			String(localized: .Onboarding.chooseANetworkToSeeSuggested)
		}
	}

	enum Summary {
		static var title: String {
			String(localized: .Onboarding.summary)
		}

		static var subtitle: String {
			String(localized: .Onboarding.summaryReviewYourChoices)
		}

		static var nicknameLabel: String {
			String(localized: .Onboarding.summaryNickname)
		}

		static var chatStyleLabel: String {
			String(localized: .Onboarding.summaryChatStyle)
		}

		static var textSizeLabel: String {
			String(localized: .Onboarding.summaryTextSize)
		}

		static var appearanceLabel: String {
			String(localized: .Onboarding.summaryAppearance)
		}

		static var notificationsLabel: String {
			String(localized: .Onboarding.summaryNotifications)
		}

		static var networkLabel: String {
			String(localized: .Onboarding.summaryNetwork)
		}

		static var channelsLabel: String {
			String(localized: .Onboarding.summaryChannels)
		}

		static var nothingChosen: String {
			String(localized: .Onboarding.summaryNothingChosen)
		}

		static var mentions: String {
			String(localized: .Onboarding.summaryMentions)
		}

		static var privateMessages: String {
			String(localized: .Onboarding.summaryPrivateMessages)
		}

		static var sounds: String {
			String(localized: .Onboarding.summarySounds)
		}

		static var settingUp: String {
			String(localized: .Onboarding.summarySettingThingsUp)
		}
	}

	enum NetworkPicker {
		static var accountIdentityHelp: String {
			String(localized: .Onboarding.accountIdentityHelp)
		}

		static var invalidAccount: String {
			String(localized: .Onboarding.invalidAccount)
		}

		static var searchPlaceholder: String {
			String(localized: .Onboarding.searchNetworks)
		}

		static var accessibilityLabel: String {
			String(localized: .Onboarding.networkPickerNetworks)
		}

		static var popularGroup: String {
			String(localized: .Onboarding.networkPickerPopular)
		}

		static var allNetworksGroup: String {
			String(localized: .Onboarding.allNetworks)
		}

		static var customServerTitle: String {
			String(localized: .Onboarding.customServer)
		}

		static var customServerDescription: String {
			String(localized: .Onboarding.connectToAnyIrcServer)
		}

		static var secureConnectionAccessibilityLabel: String {
			String(localized: .Onboarding.secureConnection)
		}

		static var serverAddressLabel: String {
			String(localized: .Onboarding.serverAddress)
		}

		static var serverAddressPlaceholder: String {
			String(localized: .Onboarding.ircExampleOrg)
		}

		static var portLabel: String {
			String(localized: .Onboarding.networkPickerPort)
		}

		static var useTLSCheckbox: String {
			String(localized: .Onboarding.useSslTls)
		}

		static var accountGroup: String {
			String(localized: .Onboarding.networkPickerAccount)
		}

		static var accountNameLabel: String {
			String(localized: .Onboarding.accountName)
		}

		static var passwordLabel: String {
			String(localized: .Onboarding.networkPickerPassword)
		}

		static var useSASLCheckbox: String {
			String(localized: .Onboarding.signInWithSasl)
		}

		static var registrationRequired: String {
			String(localized: .Onboarding.registrationRequired)
		}

		static var missingServer: String {
			String(localized: .Onboarding.chooseANetworkOrEnter)
		}

		static var invalidPort: String {
			String(localized: .Onboarding.enterAPortBetween1)
		}
	}
}
