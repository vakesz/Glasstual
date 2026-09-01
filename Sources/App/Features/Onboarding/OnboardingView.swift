/* *********************************************************************
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
import SwiftUI

struct OnboardingView: View {
	@Bindable var model: OnboardingModel
	let continueAction: () -> Void
	let backAction: () -> Void
	let skipAction: () -> Void

	var body: some View {
		VStack(spacing: 0) {
			VStack(spacing: 6) {
				Image(nsImage: NSApp.applicationIconImage)
					.resizable()
					.scaledToFit()
					.frame(width: 72, height: 72)
					.accessibilityHidden(true)

				Text(verbatim: model.currentStep.title)
					.font(.system(size: 26, weight: .bold))
					.contentTransition(.numericText())

				Text(verbatim: model.currentStep.subtitle)
					.foregroundStyle(.secondary)
					.multilineTextAlignment(.center)
					.frame(maxWidth: 560)
			}
			.padding(.top, 24)
			.padding(.bottom, 14)

			Group {
				switch model.currentStep {
				case .identity:
					OnboardingIdentityView(settings: model.settings)
				case .appearance:
					OnboardingAppearanceView(settings: model.settings)
				case .notifications:
					OnboardingNotificationsView(model: model, settings: model.settings)
				case .network:
					OnboardingNetworkView(
						settings: model.settings,
						picker: model.networkPicker,
						confirm: continueAction
					)
				}
			}
			.id(model.currentStep)
			.transition(.opacity.combined(with: .move(edge: .trailing)))
			.frame(maxWidth: .infinity, maxHeight: .infinity)
			.padding(.horizontal, 32)

			Divider()

			HStack {
				if model.currentStep.isSkippable {
					Button(OnboardingStrings.Window.skipButton, action: skipAction)
						.buttonStyle(.link)
				}

				Spacer()

				OnboardingPageIndicator(
					currentStep: model.currentStep.rawValue,
					stepCount: OnboardingStep.allCases.count,
					accessibilityDescription: model.progressDescription
				)

				Spacer()

				Button(OnboardingStrings.Window.backButton, action: backAction)
					.disabled(model.isFirstStep)
					.opacity(model.isFirstStep ? 0 : 1)
					.keyboardShortcut(.leftArrow, modifiers: .command)

				Button(model.primaryButtonTitle, action: continueAction)
					.keyboardShortcut(.defaultAction)
			}
			.padding(16)
		}
		.frame(width: 720, height: 700)
		.animation(.snappy(duration: 0.2), value: model.currentStep)
		.onExitCommand(perform: skipAction)
		.alert(model.currentStep.title, isPresented: $model.isValidationPresented) {
			Button(PromptStrings.Action.confirmation, role: .cancel) {}
		} message: {
			Text(verbatim: model.validationMessage)
		}
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

private struct OnboardingIdentityView: View {
	@Bindable var settings: OnboardingSettings
	@FocusState private var focusedField: Field?

	private enum Field {
		case nickname
		case realName
		case alternateNickname
	}

	var body: some View {
		Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 12) {
			GridRow {
				Text(verbatim: OnboardingStrings.Identity.nicknameLabel)
					.gridColumnAlignment(.trailing)
				TextField(
					OnboardingStrings.Identity.nicknamePlaceholder,
					text: $settings.nickname
				)
				.focused($focusedField, equals: .nickname)
			}

			GridRow {
				Text(verbatim: OnboardingStrings.Identity.realNameLabel)
				TextField(
					OnboardingStrings.Identity.realNamePlaceholder,
					text: $settings.realName
				)
				.focused($focusedField, equals: .realName)
			}

			GridRow {
				Text(verbatim: OnboardingStrings.Identity.alternateNicknameLabel)
				TextField(
					OnboardingStrings.Identity.optionalPlaceholder,
					text: $settings.alternateNickname
				)
				.focused($focusedField, equals: .alternateNickname)
			}

			GridRow {
				Color.clear.frame(width: 1, height: 1)
				Text(verbatim: OnboardingStrings.Identity.alternateNicknameHelp)
					.font(.callout)
					.foregroundStyle(.secondary)
					.fixedSize(horizontal: false, vertical: true)
			}
		}
		.frame(width: 460)
		.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
		.padding(.top, 30)
		.onAppear { focusedField = .nickname }
	}
}

private struct OnboardingAppearanceView: View {
	@Bindable var settings: OnboardingSettings

	var body: some View {
		VStack(spacing: 18) {
			HStack(spacing: 18) {
				OnboardingStylePreview(
					styleName: "Bubbles",
					title: OnboardingStrings.Appearance.bubblesTitle,
					description: OnboardingStrings.Appearance.bubblesDescription,
					fontSize: OnboardingSettings.fontSize(for: settings.textSize),
					isSelected: settings.styleName == "Bubbles"
				) { settings.styleName = "Bubbles" }

				OnboardingStylePreview(
					styleName: "Lines",
					title: OnboardingStrings.Appearance.linesTitle,
					description: OnboardingStrings.Appearance.linesDescription,
					fontSize: OnboardingSettings.fontSize(for: settings.textSize),
					isSelected: settings.styleName == "Lines"
				) { settings.styleName = "Lines" }
			}
			.accessibilityElement(children: .contain)
			.accessibilityLabel(Text(verbatim: OnboardingStrings.Appearance.previewAccessibilityLabel))
			Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 12) {
				GridRow {
					Text(verbatim: OnboardingStrings.Appearance.textSizeLabel)
						.gridColumnAlignment(.trailing)
					Picker("", selection: $settings.textSize) {
						ForEach(OnboardingTextSize.allCases) { size in
							Text(verbatim: size.title).tag(size)
						}
					}
					.labelsHidden()
					.pickerStyle(.segmented)
					.frame(width: 240)
				}

				GridRow {
					Text(verbatim: OnboardingStrings.Appearance.interfaceStyleLabel)
					Picker("", selection: $settings.appearance) {
						Text(verbatim: OnboardingStrings.Appearance.interfaceStyleTitles[0])
							.tag(TXPreferredAppearance.inherited)
						Text(verbatim: OnboardingStrings.Appearance.interfaceStyleTitles[1])
							.tag(TXPreferredAppearance.light)
						Text(verbatim: OnboardingStrings.Appearance.interfaceStyleTitles[2])
							.tag(TXPreferredAppearance.dark)
					}
					.labelsHidden()
					.pickerStyle(.segmented)
					.frame(width: 240)
				}
			}
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
	}
}

private struct OnboardingStylePreview: View {
	let styleName: String
	let title: String
	let description: String
	let fontSize: CGFloat
	let isSelected: Bool
	let select: () -> Void

	private var usesBubbles: Bool {
		styleName == "Bubbles"
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

				Text(verbatim: title).font(.headline)
				Text(verbatim: description)
					.font(.caption)
					.foregroundStyle(.secondary)
			}
		}
		.buttonStyle(.plain)
		.frame(maxWidth: .infinity)
		.accessibilityElement(children: .ignore)
		.accessibilityLabel(Text(verbatim: title))
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
		.frame(width: 440)
		.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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

			HStack(alignment: .firstTextBaseline, spacing: 8) {
				Text(verbatim: OnboardingStrings.FirstNetwork.suggestedChannelsLabel)
				if picker.suggestedChannels.isEmpty {
					Text(verbatim: OnboardingStrings.FirstNetwork.suggestedChannelsPlaceholder)
						.font(.callout)
						.foregroundStyle(.secondary)
				} else {
					ForEach(picker.suggestedChannels, id: \.self) { channel in
						Toggle(
							channel,
							isOn: Binding(
								get: { picker.selectedChannels.contains(channel) },
								set: { selected in
									if selected {
										picker.selectedChannels.insert(channel)
									} else {
										picker.selectedChannels.remove(channel)
									}
								}
							)
						)
					}
				}
			}

			Toggle(OnboardingStrings.FirstNetwork.connectWhenFinished, isOn: $settings.connectWhenFinished)
		}
		.padding(.bottom, 10)
	}
}
