/* *********************************************************************
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
import SwiftUI

struct OnboardingScene: Scene {
	var body: some Scene {
		Window(
			String(localized: .Onboarding.windowChromeWelcomeToGlasstual),
			id: ApplicationSceneID.onboarding
		) {
			OnboardingSceneRoot()
		}
		.windowResizability(.contentMinSize)
		.windowStyle(.hiddenTitleBar)
	}
}

private struct OnboardingSceneRoot: View {
	@Environment(\.dismissWindow) private var dismissWindow
	@State private var model = OnboardingModel()

	var body: some View {
		OnboardingView(
			model: model,
			applicationIcon: Image(nsImage: NSApp.applicationIconImage),
			dismiss: { dismissWindow(id: ApplicationSceneID.onboarding) }
		)
		/* The window keeps its close button even with the title bar hidden.
		 Closing it applies nothing, but it still records that onboarding was
		 answered — leaving it unmarked is what made the window come back at
		 every launch. A finished flow ignores this. */
		.onDisappear(perform: model.setUpLater)
	}
}

struct OnboardingView: View {
	@Bindable var model: OnboardingModel
	let applicationIcon: Image
	let dismiss: () -> Void

	/// Sliding a full panel across the window is exactly the motion Reduce
	/// Motion asks applications to stop making.
	@Environment(\.accessibilityReduceMotion) private var reduceMotion

	var body: some View {
		VStack(spacing: 0) {
			header

			Group {
				if model.isCompleting {
					OnboardingCompletionProgress()
				} else {
					ScrollView {
						stepContent
							.padding(.horizontal, 32)
							.padding(.bottom, 16)
					}
					.scrollBounceBehavior(.basedOnSize)
					.id(model.currentStep)
					.transition(
						reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .trailing))
					)
				}
			}
			.frame(maxWidth: .infinity, maxHeight: .infinity)

			Divider()

			footer
		}
		.frame(minWidth: 720, idealWidth: 720, minHeight: 620, idealHeight: 700)
		.animation(reduceMotion ? nil : .snappy(duration: 0.2), value: model.currentStep)
		.animation(reduceMotion ? nil : .snappy(duration: 0.2), value: model.isCompleting)
		.alert(
			Text(.Onboarding.connectionUnavailable),
			isPresented: $model.isCompletionFailurePresented
		) {
			Button(PromptStrings.Action.confirmation, role: .cancel) {}
		} message: {
			Text(.Onboarding.connectionUnavailableRecovery)
		}
	}

	private var header: some View {
		VStack(spacing: 6) {
			applicationIcon
				.resizable()
				.scaledToFit()
				.frame(width: 72, height: 72)
				.accessibilityHidden(true)

			Text(model.currentStep.title)
				.font(.largeTitle.weight(.bold))
				.contentTransition(.numericText())

			Text(model.currentStep.subtitle)
				.foregroundStyle(.secondary)
				.multilineTextAlignment(.center)
				.frame(maxWidth: 560)
		}
		.padding(.top, 24)
		.padding(.bottom, 14)
	}

	@ViewBuilder
	private var stepContent: some View {
		switch model.currentStep {
		case .identity:
			OnboardingIdentityView(model: model, settings: model.settings)
		case .appearance:
			OnboardingAppearanceView(settings: model.settings)
		case .notifications:
			OnboardingNotificationsView(model: model, settings: model.settings)
		case .network:
			OnboardingNetworkView(
				settings: model.settings,
				picker: model.networkPicker,
				confirm: advance
			)
		case .summary:
			OnboardingSummaryView(model: model)
		}
	}

	private var footer: some View {
		HStack {
			/* Onboarding has to be dismissible without answering it, and
			 without it asking again at the next launch. */
			Button(.Onboarding.windowChromeSetUpLater, action: setUpLater)
				.buttonStyle(.link)

			Button(.Onboarding.windowChromeSkip) { model.skip() }
				.buttonStyle(.link)
				.disabled(model.currentStep.isSkippable == false)
				.opacity(model.currentStep.isSkippable ? 1 : 0)

			Spacer()

			OnboardingPageIndicator(
				currentStep: model.currentStep.rawValue,
				stepCount: OnboardingStep.allCases.count,
				accessibilityDescription: model.progressDescription
			)

			Spacer()

			Button(.Onboarding.windowChromeBack, action: model.moveBack)
				.disabled(model.isFirstStep)
				.opacity(model.isFirstStep ? 0 : 1)
				.keyboardShortcut(.leftArrow, modifiers: .command)

			Button(model.primaryButtonTitle, action: advance)
				.keyboardShortcut(.defaultAction)
				.disabled(model.isCurrentStepValid == false)
		}
		.disabled(model.isCompleting)
		.padding(16)
	}

	private func advance() {
		guard model.advance() else { return }

		Task {
			if await model.finish() {
				dismiss()
			}
		}
	}

	private func setUpLater() {
		model.setUpLater()
		dismiss()
	}
}

private struct OnboardingCompletionProgress: View {
	var body: some View {
		ProgressView(.Onboarding.summarySettingThingsUp)
			.progressViewStyle(.circular)
			.controlSize(.large)
			.frame(maxWidth: .infinity, maxHeight: .infinity)
	}
}

private struct OnboardingPageIndicator: View {
	let currentStep: Int
	let stepCount: Int
	let accessibilityDescription: LocalizedStringResource

	var body: some View {
		HStack(spacing: 8) {
			ForEach(0 ..< stepCount, id: \.self) { step in
				Circle()
					.fill(step == currentStep ? Color.accentColor : Color.secondary.opacity(0.25))
					.frame(width: 7, height: 7)
			}
		}
		.accessibilityElement(children: .ignore)
		.accessibilityLabel(Text(accessibilityDescription))
	}
}

/// A form row whose complaint is shown under the control it belongs to, rather
/// than in an alert after the fact.
struct OnboardingValidatedRow<Content: View>: View {
	let label: String
	let problem: String?
	@ViewBuilder let content: Content

	var body: some View {
		LabeledContent(label) {
			VStack(alignment: .leading, spacing: 4) {
				content
				if let problem {
					ValidationMessageLabel(problem)
						.fixedSize(horizontal: false, vertical: true)
				}
			}
		}
	}
}

private struct OnboardingIdentityView: View {
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
			OnboardingValidatedRow(
				label: String(localized: .Onboarding.stepWelcomeAndIdentityNickname),
				problem: model.nicknameProblem
			) {
				TextField(.Onboarding.nickname, text: $settings.nickname)
					.focused($focusedField, equals: .nickname)
					.accessibilityIdentifier("onboarding-nickname")
			}

			OnboardingValidatedRow(
				label: String(localized: .Onboarding.realName),
				problem: model.realNameProblem
			) {
				TextField(.Onboarding.yourNameOrAnythingYouLike, text: $settings.realName)
					.focused($focusedField, equals: .realName)
					.accessibilityIdentifier("onboarding-real-name")
			}

			OnboardingValidatedRow(
				label: String(localized: .Onboarding.alternateNickname),
				problem: model.alternateNicknameProblem
			) {
				TextField(
					.Onboarding.stepWelcomeAndIdentityOptional,
					text: $settings.alternateNickname
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

private struct OnboardingAppearanceView: View {
	@Bindable var settings: OnboardingSettings

	var body: some View {
		VStack(spacing: 18) {
			HStack(spacing: 18) {
				ForEach(OnboardingTranscriptStyle.allCases) { style in
					OnboardingStylePreview(
						style: style,
						fontSize: OnboardingSettings.fontSize(for: settings.textSize),
						isSelected: settings.transcriptStyle == style
					) { settings.transcriptStyle = style }
				}
			}
			.accessibilityElement(children: .contain)
			.accessibilityLabel(Text(.Onboarding.chatStyle))

			Form {
				Picker(.Onboarding.textSize, selection: $settings.textSize) {
					ForEach(OnboardingTextSize.allCases) { size in
						Text(size.title).tag(size)
					}
				}
				.pickerStyle(.segmented)

				Picker(.Onboarding.stepLookAndFeelAppearance, selection: $settings.appearance) {
					ForEach(PreferredAppearance.allCases, id: \.self) { appearance in
						Text(appearance.onboardingTitle).tag(appearance)
					}
				}
				.pickerStyle(.segmented)
			}
			.formStyle(.columns)
			.frame(maxWidth: 360)
		}
		.frame(maxWidth: .infinity, alignment: .center)
	}
}

/// One line of the mock transcript the appearance step previews.
struct OnboardingAppearancePreviewMessage {
	let nickname: LocalizedStringResource
	let message: LocalizedStringResource
}

private struct OnboardingStylePreview: View {
	let style: OnboardingTranscriptStyle
	let fontSize: CGFloat
	let isSelected: Bool
	let select: () -> Void

	/// The same short exchange under both styles, so the preview shows the
	/// layout rather than a difference in what was said.
	static let previewMessages: [OnboardingAppearancePreviewMessage] = [
		OnboardingAppearancePreviewMessage(
			nickname: .Onboarding.stepLookAndFeelAlice,
			message: .Onboarding.goodMorningEveryone
		),
		OnboardingAppearancePreviewMessage(
			nickname: .Onboarding.stepLookAndFeelBob,
			message: .Onboarding.morningAnyoneTriedTheNewBuild
		),
		OnboardingAppearancePreviewMessage(
			nickname: .Onboarding.stepLookAndFeelYou,
			message: .Onboarding.yesItWorksWellSoFar
		),
	]

	private var usesBubbles: Bool {
		style == .bubbles
	}

	var body: some View {
		let messages = Array(Self.previewMessages.enumerated())

		Button(action: select) {
			VStack(spacing: 8) {
				ZStack(alignment: .topTrailing) {
					VStack(spacing: 6) {
						ForEach(messages, id: \.offset) { index, message in
							previewRow(message, outgoing: index == 2)
						}
					}
					.padding(12)
					.frame(maxWidth: .infinity, minHeight: 150, alignment: .top)
					.background(.background, in: RoundedRectangle(cornerRadius: 10))
					.overlay {
						RoundedRectangle(cornerRadius: 10)
							.stroke(
								isSelected ? Color.accentColor : Color.secondary.opacity(0.3),
								lineWidth: isSelected ? 2 : 1
							)
					}

					if isSelected {
						Image(systemName: "checkmark.circle.fill")
							.foregroundStyle(.tint)
							.padding(8)
					}
				}

				Text(style.title).font(.headline)
				Text(style.summary)
					.font(.caption)
					.foregroundStyle(.secondary)
			}
		}
		.buttonStyle(.plain)
		.frame(maxWidth: .infinity)
		.accessibilityElement(children: .ignore)
		.accessibilityLabel(Text(style.title))
		.accessibilityAddTraits(isSelected ? [.isSelected] : [])
	}

	@ViewBuilder
	private func previewRow(_ message: OnboardingAppearancePreviewMessage, outgoing: Bool) -> some View {
		if usesBubbles {
			HStack {
				if outgoing {
					Spacer(minLength: 30)
				}
				VStack(alignment: .leading, spacing: 1) {
					if outgoing == false {
						Text(message.nickname)
							.font(.system(size: max(9, fontSize - 2), weight: .semibold))
							.foregroundStyle(.secondary)
					}
					Text(message.message)
						.font(.system(size: fontSize))
						.foregroundStyle(outgoing ? Color.white : Color.primary)
				}
				.padding(.horizontal, 9)
				.padding(.vertical, 5)
				.background(outgoing ? Color.accentColor : Color.secondary.opacity(0.16))
				.clipShape(RoundedRectangle(cornerRadius: 11))
				if outgoing == false {
					Spacer(minLength: 30)
				}
			}
		} else {
			HStack(alignment: .firstTextBaseline, spacing: 5) {
				Text(.Onboarding.stepLookAndFeel)
					.font(.system(size: max(9, fontSize - 2), design: .monospaced))
					.foregroundStyle(.tertiary)
				/* The angle brackets are how the lines style marks a nickname,
				 so they are punctuation around the name rather than copy. */
				Text(verbatim: "<\(String(localized: message.nickname))>")
					.font(.system(size: fontSize, weight: .semibold))
					.foregroundStyle(outgoing ? Color.accentColor : Color.primary)
				Text(message.message)
					.font(.system(size: fontSize))
					.lineLimit(1)
				Spacer(minLength: 0)
			}
		}
	}
}

private struct OnboardingNotificationsView: View {
	@Bindable var model: OnboardingModel
	@Bindable var settings: OnboardingSettings

	var body: some View {
		VStack(alignment: .leading, spacing: 12) {
			Toggle(.Onboarding.notifyMeWhenSomeoneMentionsMe, isOn: $settings.notifyOnHighlight)
			Toggle(
				.Onboarding.notifyMeAboutPrivateMessages,
				isOn: $settings.notifyOnPrivateMessage
			)
			Toggle(.Onboarding.playSounds, isOn: $settings.playSounds)

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
		.frame(maxWidth: 440, alignment: .leading)
		.frame(maxWidth: .infinity, alignment: .center)
		.padding(.top, 30)
		.task { await model.refreshNotificationPermission() }
	}
}

private struct OnboardingNetworkView: View {
	@Bindable var settings: OnboardingSettings
	@Bindable var picker: NetworkPickerModel
	let confirm: () -> Void

	var body: some View {
		VStack(alignment: .leading, spacing: 10) {
			NetworkPickerView(model: picker, confirm: confirm)

			VStack(alignment: .leading, spacing: 6) {
				Text(.Onboarding.suggestedChannels)
				if picker.suggestedChannels.isEmpty {
					Text(.Onboarding.chooseANetworkToSeeSuggested)
						.font(.callout)
						.foregroundStyle(.secondary)
				} else {
					ForEach(picker.suggestedChannels, id: \.self) { channel in
						Toggle(channel, isOn: $picker.selectedChannels.containing(channel))
					}
				}
			}

			Toggle(.Onboarding.connectWhenFinished, isOn: $settings.connectWhenFinished)
		}
		.padding(.bottom, 10)
	}
}

private struct OnboardingSummaryView: View {
	let model: OnboardingModel

	private var nothingChosen: String {
		String(localized: .Onboarding.summaryNothingChosen)
	}

	var body: some View {
		Form {
			LabeledContent(.Onboarding.summaryNickname, value: nicknameSummary)
			LabeledContent(.Onboarding.summaryChatStyle, value: chatStyleSummary)
			LabeledContent(.Onboarding.summaryTextSize, value: textSizeSummary)
			LabeledContent(.Onboarding.summaryAppearance, value: appearanceSummary)
			LabeledContent(.Onboarding.summaryNotifications, value: notificationSummary)
			LabeledContent(.Onboarding.summaryNetwork, value: networkSummary)
			LabeledContent(.Onboarding.summaryChannels, value: channelSummary)
		}
		.formStyle(.columns)
		.frame(maxWidth: 460)
		.frame(maxWidth: .infinity, alignment: .center)
	}

	private var nicknameSummary: String {
		model.acceptedIdentity?.nickname ?? nothingChosen
	}

	private var chatStyleSummary: String {
		guard let appearance = model.acceptedAppearance else { return nothingChosen }
		return String(localized: appearance.transcriptStyle.title)
	}

	private var textSizeSummary: String {
		guard let appearance = model.acceptedAppearance else { return nothingChosen }
		return String(localized: appearance.textSize.title)
	}

	private var appearanceSummary: String {
		guard let appearance = model.acceptedAppearance else { return nothingChosen }
		return String(localized: appearance.preferredAppearance.onboardingTitle)
	}

	private var networkSummary: String {
		model.settings.clientConfig?.connectionName ?? nothingChosen
	}

	private var notificationSummary: String {
		guard let notifications = model.acceptedNotifications else {
			return nothingChosen
		}

		let kinds = [
			notifications.highlight ? String(localized: .Onboarding.summaryMentions) : nil,
			notifications.privateMessage ? String(localized: .Onboarding.summaryPrivateMessages) : nil,
			notifications.sounds ? String(localized: .Onboarding.summarySounds) : nil,
		].compactMap(\.self)

		return kinds.isEmpty ? nothingChosen : kinds.formatted(.list(type: .and))
	}

	private var channelSummary: String {
		let channels = model.settings.channelsToJoin
		return channels.isEmpty ? nothingChosen : channels.formatted(.list(type: .and))
	}
}

private extension Binding where Value == Set<String> {
	/// Presents one member of the set as the `Bool` a `Toggle` binds to.
	func containing(_ member: String) -> Binding<Bool> {
		Binding<Bool>(
			get: { wrappedValue.contains(member) },
			set: { isSelected in
				if isSelected {
					wrappedValue.insert(member)
				} else {
					wrappedValue.remove(member)
				}
			}
		)
	}
}
