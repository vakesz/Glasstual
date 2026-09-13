/* *********************************************************************
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import SwiftUI

struct OnboardingView: View {
	@Bindable var session: OnboardingSession
	let applicationIcon: Image
	let dismiss: () -> Void

	/// Sliding a full panel across the window is exactly the motion Reduce
	/// Motion asks applications to stop making.
	@Environment(\.accessibilityReduceMotion) private var reduceMotion

	private var model: OnboardingModel {
		session.model
	}

	var body: some View {
		VStack(spacing: 0) {
			header

			Group {
				if session.isCompleting {
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
		.animation(reduceMotion ? nil : .snappy(duration: 0.2), value: session.isCompleting)
		.onExitCommand(perform: setUpLater)
		.alert(
			Text(verbatim: OnboardingStrings.Window.connectionUnavailable),
			isPresented: $session.isCompletionFailurePresented
		) {
			Button(PromptStrings.Action.confirmation, role: .cancel) {}
		} message: {
			Text(verbatim: OnboardingStrings.Window.connectionUnavailableRecovery)
		}
	}

	private var header: some View {
		VStack(spacing: 6) {
			applicationIcon
				.resizable()
				.scaledToFit()
				.frame(width: 72, height: 72)
				.accessibilityHidden(true)

			Text(verbatim: model.currentStep.title)
				.font(.largeTitle.weight(.bold))
				.contentTransition(.numericText())

			Text(verbatim: model.currentStep.subtitle)
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
			Button(OnboardingStrings.Window.setUpLaterButton, action: setUpLater)
				.buttonStyle(.link)

			Button(OnboardingStrings.Window.skipButton) { model.skip() }
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

			Button(OnboardingStrings.Window.backButton, action: model.moveBack)
				.disabled(model.isFirstStep)
				.opacity(model.isFirstStep ? 0 : 1)
				.keyboardShortcut(.leftArrow, modifiers: .command)

			Button(model.primaryButtonTitle, action: advance)
				.keyboardShortcut(.defaultAction)
				.disabled(model.isCurrentStepValid == false)
		}
		.disabled(session.isCompleting)
		.padding(16)
	}

	private func advance() {
		guard model.advance() else { return }

		Task {
			if await session.finish() {
				dismiss()
			}
		}
	}

	private func setUpLater() {
		session.setUpLater()
		dismiss()
	}
}

private struct OnboardingCompletionProgress: View {
	var body: some View {
		ProgressView {
			Text(verbatim: OnboardingStrings.Summary.settingUp)
		}
		.progressViewStyle(.circular)
		.controlSize(.large)
		.frame(maxWidth: .infinity, maxHeight: .infinity)
	}
}

private struct OnboardingPageIndicator: View {
	let currentStep: Int
	let stepCount: Int
	let accessibilityDescription: String

	var body: some View {
		HStack(spacing: 8) {
			ForEach(0 ..< stepCount, id: \.self) { step in
				Circle()
					.fill(step == currentStep ? Color.accentColor : Color.secondary.opacity(0.25))
					.frame(width: 7, height: 7)
			}
		}
		.accessibilityElement(children: .ignore)
		.accessibilityLabel(Text(verbatim: accessibilityDescription))
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
				label: OnboardingStrings.Identity.nicknameLabel,
				problem: model.nicknameProblem
			) {
				TextField(OnboardingStrings.Identity.nicknamePlaceholder, text: $settings.nickname)
					.focused($focusedField, equals: .nickname)
					.accessibilityIdentifier("onboarding-nickname")
			}

			OnboardingValidatedRow(
				label: OnboardingStrings.Identity.realNameLabel,
				problem: model.realNameProblem
			) {
				TextField(OnboardingStrings.Identity.realNamePlaceholder, text: $settings.realName)
					.focused($focusedField, equals: .realName)
					.accessibilityIdentifier("onboarding-real-name")
			}

			OnboardingValidatedRow(
				label: OnboardingStrings.Identity.alternateNicknameLabel,
				problem: model.alternateNicknameProblem
			) {
				TextField(
					OnboardingStrings.Identity.optionalPlaceholder,
					text: $settings.alternateNickname
				)
				.focused($focusedField, equals: .alternateNickname)
				.accessibilityIdentifier("onboarding-alternate-nickname")

				Text(verbatim: OnboardingStrings.Identity.alternateNicknameHelp)
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
			.accessibilityLabel(Text(verbatim: OnboardingStrings.Appearance.previewAccessibilityLabel))

			Form {
				Picker(OnboardingStrings.Appearance.textSizeLabel, selection: $settings.textSize) {
					ForEach(OnboardingTextSize.allCases) { size in
						Text(verbatim: size.title).tag(size)
					}
				}
				.pickerStyle(.segmented)

				Picker(OnboardingStrings.Appearance.interfaceStyleLabel, selection: $settings.appearance) {
					ForEach(PreferredAppearance.allCases, id: \.self) { appearance in
						Text(verbatim: OnboardingStrings.Appearance.interfaceStyleTitle(appearance))
							.tag(appearance)
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

private struct OnboardingStylePreview: View {
	let style: OnboardingTranscriptStyle
	let fontSize: CGFloat
	let isSelected: Bool
	let select: () -> Void

	private var usesBubbles: Bool {
		style == .bubbles
	}

	var body: some View {
		let messages = Array(OnboardingStrings.Appearance.previewMessages.enumerated())

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

				Text(verbatim: style.title).font(.headline)
				Text(verbatim: style.summary)
					.font(.caption)
					.foregroundStyle(.secondary)
			}
		}
		.buttonStyle(.plain)
		.frame(maxWidth: .infinity)
		.accessibilityElement(children: .ignore)
		.accessibilityLabel(Text(verbatim: style.title))
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
						Text(verbatim: message.nickname)
							.font(.system(size: max(9, fontSize - 2), weight: .semibold))
							.foregroundStyle(.secondary)
					}
					Text(verbatim: message.message)
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
				Text(verbatim: OnboardingStrings.Appearance.previewTime)
					.font(.system(size: max(9, fontSize - 2), design: .monospaced))
					.foregroundStyle(.tertiary)
				Text(verbatim: "<\(message.nickname)>")
					.font(.system(size: fontSize, weight: .semibold))
					.foregroundStyle(outgoing ? Color.accentColor : Color.primary)
				Text(verbatim: message.message)
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
			Toggle(OnboardingStrings.Notifications.mentionCheckbox, isOn: $settings.notifyOnHighlight)
			Toggle(
				OnboardingStrings.Notifications.privateMessageCheckbox,
				isOn: $settings.notifyOnPrivateMessage
			)
			Toggle(OnboardingStrings.Notifications.soundCheckbox, isOn: $settings.playSounds)

			Label {
				Text(verbatim: model.notificationPermissionMessage)
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
				Text(verbatim: OnboardingStrings.FirstNetwork.suggestedChannelsLabel)
				if picker.suggestedChannels.isEmpty {
					Text(verbatim: OnboardingStrings.FirstNetwork.suggestedChannelsPlaceholder)
						.font(.callout)
						.foregroundStyle(.secondary)
				} else {
					ForEach(picker.suggestedChannels, id: \.self) { channel in
						Toggle(channel, isOn: $picker.selectedChannels.containing(channel))
					}
				}
			}

			Toggle(OnboardingStrings.FirstNetwork.connectWhenFinished, isOn: $settings.connectWhenFinished)
		}
		.padding(.bottom, 10)
	}
}

private struct OnboardingSummaryView: View {
	let model: OnboardingModel

	var body: some View {
		Form {
			LabeledContent(
				OnboardingStrings.Summary.nicknameLabel,
				value: model.acceptedIdentity?.nickname ?? OnboardingStrings.Summary.nothingChosen
			)
			LabeledContent(
				OnboardingStrings.Summary.chatStyleLabel,
				value: model.acceptedAppearance?.transcriptStyle.title ?? OnboardingStrings.Summary.nothingChosen
			)
			LabeledContent(
				OnboardingStrings.Summary.textSizeLabel,
				value: model.acceptedAppearance?.textSize.title ?? OnboardingStrings.Summary.nothingChosen
			)
			LabeledContent(
				OnboardingStrings.Summary.appearanceLabel,
				value: model.acceptedAppearance.map {
					OnboardingStrings.Appearance.interfaceStyleTitle($0.preferredAppearance)
				} ?? OnboardingStrings.Summary.nothingChosen
			)
			LabeledContent(
				OnboardingStrings.Summary.notificationsLabel,
				value: notificationSummary
			)
			LabeledContent(
				OnboardingStrings.Summary.networkLabel,
				value: model.settings.clientConfig?.connectionName ?? OnboardingStrings.Summary.nothingChosen
			)
			LabeledContent(
				OnboardingStrings.Summary.channelsLabel,
				value: channelSummary
			)
		}
		.formStyle(.columns)
		.frame(maxWidth: 460)
		.frame(maxWidth: .infinity, alignment: .center)
	}

	private var notificationSummary: String {
		guard let notifications = model.acceptedNotifications else {
			return OnboardingStrings.Summary.nothingChosen
		}

		let kinds = [
			notifications.highlight ? OnboardingStrings.Summary.mentions : nil,
			notifications.privateMessage ? OnboardingStrings.Summary.privateMessages : nil,
			notifications.sounds ? OnboardingStrings.Summary.sounds : nil,
		].compactMap(\.self)

		return kinds.isEmpty
			? OnboardingStrings.Summary.nothingChosen
			: kinds.formatted(.list(type: .and))
	}

	private var channelSummary: String {
		let channels = model.settings.channelsToJoin
		return channels.isEmpty
			? OnboardingStrings.Summary.nothingChosen
			: channels.formatted(.list(type: .and))
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
