/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\\_\\__|\\__,_|\\__,_|_|
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

enum OnboardingTextSize: CaseIterable {
	case small
	case medium
	case large

	var title: String {
		switch self {
		case .small:
			String(localized: .TDCOnboardingWindow.lf1S1)
		case .medium:
			String(localized: .TDCOnboardingWindow.lf1S2)
		case .large:
			String(localized: .TDCOnboardingWindow.lf1S3)
		}
	}
}

enum OnboardingInterfaceStyle: CaseIterable {
	case system
	case light
	case dark

	var title: String {
		switch self {
		case .system:
			String(localized: .TDCOnboardingWindow.lf1A1)
		case .light:
			String(localized: .TDCOnboardingWindow.lf1A2)
		case .dark:
			String(localized: .TDCOnboardingWindow.lf1A3)
		}
	}
}

enum OnboardingStrings {
	enum Window {
		static var title: String {
			String(localized: .TDCOnboardingWindow.ob1Wt)
		}

		static var backButton: String {
			String(localized: .TDCOnboardingWindow.ob1Bk)
		}

		static var continueButton: String {
			String(localized: .TDCOnboardingWindow.ob1Ct)
		}

		static var finishButton: String {
			String(localized: .TDCOnboardingWindow.ob1Fn)
		}

		static var skipButton: String {
			String(localized: .TDCOnboardingWindow.ob1Sk)
		}

		static func progress(currentStep: Int, totalSteps: Int) -> String {
			String(localized: .TDCOnboardingWindow.ob1Pg(currentStep, totalSteps))
		}
	}

	enum Identity {
		static var title: String {
			String(localized: .TDCOnboardingWindow.id1Tt)
		}

		static var subtitle: String {
			String(localized: .TDCOnboardingWindow.id1St)
		}

		static var nicknameLabel: String {
			String(localized: .TDCOnboardingWindow.id1Nk)
		}

		static var realNameLabel: String {
			String(localized: .TDCOnboardingWindow.id1Rn)
		}

		static var alternateNicknameLabel: String {
			String(localized: .TDCOnboardingWindow.id1An)
		}

		static var alternateNicknameHelp: String {
			String(localized: .TDCOnboardingWindow.id1Ah)
		}

		static var nicknamePlaceholder: String {
			String(localized: .TDCOnboardingWindow.id1Np)
		}

		static var realNamePlaceholder: String {
			String(localized: .TDCOnboardingWindow.id1Rp)
		}

		static var optionalPlaceholder: String {
			String(localized: .TDCOnboardingWindow.id1Ap)
		}
	}

	enum Appearance {
		static var title: String {
			String(localized: .TDCOnboardingWindow.lf1Tt)
		}

		static var subtitle: String {
			String(localized: .TDCOnboardingWindow.lf1St)
		}

		static var bubblesTitle: String {
			String(localized: .TDCOnboardingWindow.lf1Bb)
		}

		static var bubblesDescription: String {
			String(localized: .TDCOnboardingWindow.lf1Bd)
		}

		static var linesTitle: String {
			String(localized: .TDCOnboardingWindow.lf1Ln)
		}

		static var linesDescription: String {
			String(localized: .TDCOnboardingWindow.lf1Ld)
		}

		static var textSizeLabel: String {
			String(localized: .TDCOnboardingWindow.lf1Fs)
		}

		static var interfaceStyleLabel: String {
			String(localized: .TDCOnboardingWindow.lf1Ap)
		}

		static var previewAccessibilityLabel: String {
			String(localized: .TDCOnboardingWindow.lf1Ax)
		}

		static var previewTime: String {
			String(localized: .TDCOnboardingWindow.lf1Tm)
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
					nickname: String(localized: .TDCOnboardingWindow.lf1N1),
					message: String(localized: .TDCOnboardingWindow.lf1M1)
				),
				OnboardingAppearancePreviewMessage(
					nickname: String(localized: .TDCOnboardingWindow.lf1N2),
					message: String(localized: .TDCOnboardingWindow.lf1M2)
				),
				OnboardingAppearancePreviewMessage(
					nickname: String(localized: .TDCOnboardingWindow.lf1N3),
					message: String(localized: .TDCOnboardingWindow.lf1M3)
				),
			]
		}
	}

	enum Notifications {
		static var title: String {
			String(localized: .TDCOnboardingWindow.nt1Tt)
		}

		static var subtitle: String {
			String(localized: .TDCOnboardingWindow.nt1St)
		}

		static var mentionCheckbox: String {
			String(localized: .TDCOnboardingWindow.nt1Hl)
		}

		static var privateMessageCheckbox: String {
			String(localized: .TDCOnboardingWindow.nt1Pm)
		}

		static var soundCheckbox: String {
			String(localized: .TDCOnboardingWindow.nt1Sn)
		}

		static var permissionExplanation: String {
			String(localized: .TDCOnboardingWindow.nt1Pr)
		}

		static var permissionGranted: String {
			String(localized: .TDCOnboardingWindow.nt1Pd)
		}

		static var permissionDenied: String {
			String(localized: .TDCOnboardingWindow.nt1Pn)
		}
	}

	enum FirstNetwork {
		static var title: String {
			String(localized: .TDCOnboardingWindow.nw1Tt)
		}

		static var subtitle: String {
			String(localized: .TDCOnboardingWindow.nw1St)
		}

		static var connectWhenFinished: String {
			String(localized: .TDCOnboardingWindow.nw1Cn)
		}

		static var suggestedChannelsLabel: String {
			String(localized: .TDCOnboardingWindow.nw1Ch)
		}

		static var suggestedChannelsPlaceholder: String {
			String(localized: .TDCOnboardingWindow.nw1Ep)
		}

		static var invalidNetwork: String {
			String(localized: .TDCOnboardingWindow.nw1Er)
		}
	}

	enum NetworkPicker {
		static var searchPlaceholder: String {
			String(localized: .TDCOnboardingWindow.np1Sp)
		}

		static var accessibilityLabel: String {
			String(localized: .TDCOnboardingWindow.np1Ax)
		}

		static var popularGroup: String {
			String(localized: .TDCOnboardingWindow.np1Gp)
		}

		static var allNetworksGroup: String {
			String(localized: .TDCOnboardingWindow.np1Ga)
		}

		static var customServerTitle: String {
			String(localized: .TDCOnboardingWindow.np1Cs)
		}

		static var customServerDescription: String {
			String(localized: .TDCOnboardingWindow.np1Cd)
		}

		static var secureConnectionAccessibilityLabel: String {
			String(localized: .TDCOnboardingWindow.np1Lk)
		}

		static var serverAddressLabel: String {
			String(localized: .TDCOnboardingWindow.np1Sv)
		}

		static var serverAddressPlaceholder: String {
			String(localized: .TDCOnboardingWindow.np1Sh)
		}

		static var portLabel: String {
			String(localized: .TDCOnboardingWindow.np1Pt)
		}

		static var portPlaceholder: String {
			String(localized: .TDCOnboardingWindow.np1Pp)
		}

		static var useTLSCheckbox: String {
			String(localized: .TDCOnboardingWindow.np1Tl)
		}

		static var accountGroup: String {
			String(localized: .TDCOnboardingWindow.np1Ac)
		}

		static var accountNameLabel: String {
			String(localized: .TDCOnboardingWindow.np1An)
		}

		static var passwordLabel: String {
			String(localized: .TDCOnboardingWindow.np1Pw)
		}

		static var useSASLCheckbox: String {
			String(localized: .TDCOnboardingWindow.np1Sa)
		}

		static var registrationRequired: String {
			String(localized: .TDCOnboardingWindow.np1Rq)
		}

		static var missingServer: String {
			String(localized: .TDCOnboardingWindow.np1E1)
		}

		static var invalidPort: String {
			String(localized: .TDCOnboardingWindow.np1E2)
		}
	}
}
