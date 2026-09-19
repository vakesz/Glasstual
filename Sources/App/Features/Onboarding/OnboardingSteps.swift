// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import SwiftUI

struct OnboardingIdentityView: View {
	let model: OnboardingModel
	@Bindable var settings: OnboardingSettings
	@FocusState private var focusedField: Field?

	private enum Field {
		case nickname
		case realName
		case alternateNickname
	}

	var body: some View {
		Form {
			ValidatedFormRow(
				label: String(localized: .Onboarding.stepWelcomeAndIdentityNickname),
				problem: model.nicknameProblem
			) {
				TextField(.Onboarding.nickname, text: $settings.identity.nickname)
					.focused($focusedField, equals: .nickname)
					.accessibilityIdentifier("onboarding-nickname")
			}

			ValidatedFormRow(
				label: String(localized: .Onboarding.realName),
				problem: model.realNameProblem
			) {
				TextField(.Onboarding.realName, text: $settings.identity.realName,
				          prompt: Text(.Onboarding.yourNameOrAnythingYouLike))
					.focused($focusedField, equals: .realName)
					.accessibilityIdentifier("onboarding-real-name")
			}

			ValidatedFormRow(
				label: String(localized: .Onboarding.alternateNickname),
				problem: model.alternateNicknameProblem
			) {
				TextField(
					.Onboarding.alternateNickname,
					text: $settings.identity.alternateNickname,
					prompt: Text(.Onboarding.stepWelcomeAndIdentityOptional)
				)
				.focused($focusedField, equals: .alternateNickname)
				.accessibilityIdentifier("onboarding-alternate-nickname")

				Text(.Onboarding.usedWhenYourNicknameIsAlready)
					.font(.callout)
					.foregroundStyle(.secondary)
					.fixedSize(horizontal: false, vertical: true)
			}
		}
		.formStyle(.columns)
		.frame(maxWidth: 460)
		.frame(maxWidth: .infinity, alignment: .center)
		.padding(.top, 30)
		.onAppear { focusedField = .nickname }
	}
}

struct OnboardingNotificationsView: View {
	@Bindable var model: OnboardingModel
	@Bindable var settings: OnboardingSettings

	var body: some View {
		VStack(alignment: .leading, spacing: UISpacing.wide) {
			Toggle(
				.Onboarding.notifyAboutMentionsAndPrivateMessages,
				isOn: $settings.notifications.notifyAboutMentions
			)
			Toggle(.Onboarding.playSounds, isOn: $settings.notifications.playSounds)

			if settings.notifications.notifyAboutMentions {
				Label {
					Text(model.notificationPermissionMessage)
						.foregroundStyle(.secondary)
						.fixedSize(horizontal: false, vertical: true)
				} icon: {
					Image(systemName: model.notificationPermissionSymbol)
						.font(.title2)
						.foregroundStyle(.secondary)
				}
				.padding(.top, 22)
			}
		}
		.frame(maxWidth: 440, alignment: .leading)
		.frame(maxWidth: .infinity, alignment: .center)
		.padding(.top, 30)
		.task { await model.refreshNotificationPermission() }
	}
}

/// The review the last step shows: one row per step, each reading what that step
/// contributed rather than what its controls are showing.
struct OnboardingSummaryView: View {
	let model: OnboardingModel

	private var nothingChosen: String {
		String(localized: .Onboarding.summaryNothingChosen)
	}

	private var summaryRows: [(title: LocalizedStringResource, value: String)] {
		[
			(.Onboarding.summaryNickname, nicknameSummary),
			(.Onboarding.summaryChatStyle, chatStyleSummary),
			(.Onboarding.summaryTextSize, textSizeSummary),
			(.Onboarding.summaryAppearance, appearanceSummary),
			(.Onboarding.summaryNotifications, notificationSummary),
			(.Onboarding.summaryNetwork, networkSummary),
			(.Onboarding.summaryChannels, channelSummary),
		]
	}

	var body: some View {
		Form {
			ForEach(summaryRows.indices, id: \.self) { index in
				let row = summaryRows[index]
				LabeledContent(row.title, value: row.value)
			}
		}
		.formStyle(.columns)
		// The read-only summary is one announcement. Include every label so
		// adjacent static values cannot lose their meaning when combined.
		.accessibilityElement(children: .ignore)
		.accessibilityLabel(Text(verbatim: summaryRows.map {
			"\(String(localized: $0.title)): \($0.value)"
		}.joined(separator: "\n")))
		.accessibilityAddTraits(.isStaticText)
		.accessibilityIdentifier("onboarding-summary")
		.frame(maxWidth: 460)
		.frame(maxWidth: .infinity, alignment: .center)
	}

	private var nicknameSummary: String {
		model.accepted.identity?.nickname ?? nothingChosen
	}

	private var chatStyleSummary: String {
		guard let appearance = model.accepted.appearance else { return nothingChosen }
		return String(localized: appearance.transcriptStyle.title)
	}

	private var textSizeSummary: String {
		guard let appearance = model.accepted.appearance else { return nothingChosen }
		return String(localized: appearance.textSize.title)
	}

	private var appearanceSummary: String {
		guard let appearance = model.accepted.appearance else { return nothingChosen }
		return String(localized: appearance.preferredAppearance.onboardingTitle)
	}

	private var networkSummary: String {
		model.accepted.network?.serverConfig?.connectionName ?? nothingChosen
	}

	private var notificationSummary: String {
		guard let notifications = model.accepted.notifications else {
			return nothingChosen
		}

		let kinds = [
			notifications.notifyAboutMentions ? String(localized: .Onboarding.summaryMentions) : nil,
			notifications.notifyAboutMentions ? String(localized: .Onboarding.summaryPrivateMessages) : nil,
			notifications.playSounds ? String(localized: .Onboarding.summarySounds) : nil,
		].compactMap(\.self)

		return kinds.isEmpty ? nothingChosen : kinds.formatted(.list(type: .and))
	}

	private var channelSummary: String {
		let channels = model.accepted.network?.channelsToJoin ?? []
		return channels.isEmpty ? nothingChosen : channels.formatted(.list(type: .and))
	}
}
