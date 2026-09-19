// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
import Observation

enum OnboardingTextSize: UInt, CaseIterable, Identifiable {
	case small
	case medium
	case large

	var id: Self {
		self
	}

	var title: LocalizedStringResource {
		switch self {
		case .small: .Onboarding.stepLookAndFeelSmall
		case .medium: .Onboarding.stepLookAndFeelMedium
		case .large: .Onboarding.stepLookAndFeelLarge
		}
	}

	/// What the transcript's font is set to for this choice.
	var fontSize: CGFloat {
		switch self {
		case .small: 11
		case .medium: 14
		case .large: 15
		}
	}

	/// The choice a transcript already set to `fontSize` stands for, so the step
	/// opens on what the person is reading rather than on the middle size.
	init(fontSize: CGFloat) {
		if fontSize < 12 {
			self = .small
		} else if fontSize > 14 {
			self = .large
		} else {
			self = .medium
		}
	}
}

/// The two transcript appearances the appearance step offers.
enum OnboardingTranscriptStyle: CaseIterable, Identifiable {
	case bubbles
	case lines

	var id: Self {
		self
	}

	var theme: TranscriptTheme {
		switch self {
		case .bubbles: .bubbles
		case .lines: .lines
		}
	}

	var title: LocalizedStringResource {
		switch self {
		case .bubbles: .Onboarding.stepLookAndFeelBubbles
		case .lines: .Onboarding.stepLookAndFeelLines
		}
	}

	var summary: LocalizedStringResource {
		switch self {
		case .bubbles: .Onboarding.messagesInRoundedBubbles
		case .lines: .Onboarding.classicLineByLineView
		}
	}
}

extension PreferredAppearance {
	/// One title per case, so the appearance step's picker cannot drift out of
	/// step with the tags it sets.
	var onboardingTitle: LocalizedStringResource {
		switch self {
		case .inherited: .Onboarding.stepLookAndFeelSystem
		case .light: .Onboarding.stepLookAndFeelLight
		case .dark: .Onboarding.stepLookAndFeelDark
		}
	}
}

/// What the identity step asks for: who the person is on IRC.
struct OnboardingIdentity: Equatable {
	var nickname = ""
	var realName = ""
	var alternateNickname = ""

	/// Applied as the step is accepted: a nickname is one word, and a name
	/// padded with spaces is not what anybody typed on purpose.
	mutating func trimWhitespace() {
		nickname = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
		realName = realName.trimmingCharacters(in: .whitespacesAndNewlines)
		alternateNickname = alternateNickname.trimmingCharacters(in: .whitespacesAndNewlines)
	}
}

/// What the appearance step asks for: how a conversation is drawn.
struct OnboardingAppearance: Equatable {
	var transcriptStyle: OnboardingTranscriptStyle = .bubbles
	var textSize: OnboardingTextSize = .medium
	var preferredAppearance: PreferredAppearance = .inherited

	/// The transcript theme the style and the text size add up to.
	var theme: TranscriptTheme {
		var theme = transcriptStyle.theme
		theme.fontSize = textSize.fontSize
		return theme
	}
}

/// What the notifications step asks for: what Glasstual interrupts for.
struct OnboardingNotifications: Equatable {
	var notifyAboutMentions = true
	var playSounds = true
}

/** What the network step asks for: the first connection, if any.

 `connectWhenFinished` is the step's own toggle. The connection and its channels
 are what the network picker answered when the step was accepted, which is why
 they are not on screen anywhere. */
struct OnboardingNetwork {
	var connectWhenFinished = true
	var serverConfig: ServerConfig?
	var channelsToJoin: [String] = []
}

/** What the steps are showing, one value per step.

 Observable because the steps bind straight into these fields; a step accepts by
 handing its whole group to `OnboardingAcceptedSteps`, so there is no second
 description of what any step collects. */
@Observable
final class OnboardingSettings {
	var identity = OnboardingIdentity()
	var appearance = OnboardingAppearance()
	var notifications = OnboardingNotifications()
	var network = OnboardingNetwork()
}

/** What each step contributed, rather than what its controls currently show.

 A step contributes only once it has been accepted with Continue: passing over a
 step with Skip, or leaving onboarding without reaching it, has to leave the
 corresponding settings exactly as they were, which is what `nil` says. */
struct OnboardingAcceptedSteps {
	var identity: OnboardingIdentity?
	var appearance: OnboardingAppearance?
	var notifications: OnboardingNotifications?
	var network: OnboardingNetwork?
}
