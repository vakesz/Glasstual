// Copyright (c) 2015 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import SwiftUI

struct MessageRuleChannelOption: Identifiable {
	let id: String
	let name: String
}

struct MessageRuleSessionOption: Identifiable {
	let id: String
	let name: String
	let channels: [MessageRuleChannelOption]

	/// The connections and their channels, as the editor lists them for a rule
	/// limited to specific conversations.
	static func current() -> [MessageRuleSessionOption] {
		(AppServices.chatSession?.sessions ?? []).map { session in
			MessageRuleSessionOption(
				id: session.uniqueIdentifier,
				name: session.networkName ?? session.serverAddress ?? session.userNickname,
				channels: session.conversationList.filter(\.isChannel).map {
					MessageRuleChannelOption(id: $0.uniqueIdentifier, name: $0.name)
				}
			)
		}
	}
}

private enum RuleEditorTab: Hashable {
	case rule
	case channels
	case events
	case sender
	case notes
	case advanced
}

private struct RuleEventOption: Identifiable {
	let event: MessageRuleEvent
	let title: LocalizedStringResource

	var id: UInt {
		event.rawValue
	}

	static let all: [Self] = [
		Self(event: .plainTextMessage, title: .Rules.plainTextMessageEvent),
		Self(event: .actionMessage, title: .Rules.actionMessageEvent),
		Self(event: .noticeMessage, title: .Rules.noticeMessageEvent),
		Self(event: .userJoinedChannel, title: .Rules.userJoinedChannelEvent),
		Self(event: .userLeftChannel, title: .Rules.userLeftChannelEvent),
		Self(event: .userKickedFromChannel, title: .Rules.userKickedFromChannelEvent),
		Self(event: .userDisconnected, title: .Rules.userDisconnectedEvent),
		Self(event: .userChangedNickname, title: .Rules.userChangedNicknameEvent),
		Self(event: .channelTopicReceived, title: .Rules.channelTopicReceivedEvent),
		Self(event: .channelTopicChanged, title: .Rules.channelTopicChangedEvent),
		Self(event: .channelModeReceived, title: .Rules.channelModeReceivedEvent),
		Self(event: .channelModeChanged, title: .Rules.channelModeChangedEvent),
	]
}

private struct RuleActionPlaceholder: Identifiable {
	let id: String
	let title: LocalizedStringResource

	static let all: [Self] = [
		Self(id: "%_channelName_%", title: .Rules.tokenChannelName),
		Self(id: "%_localNickname_%", title: .Rules.tokenLocalNickname),
		Self(id: "%_networkName_%", title: .Rules.tokenNetworkName),
		Self(id: "%_originalMessage_%", title: .Rules.tokenOriginalMessage),
		Self(id: "%_senderNickname_%", title: .Rules.tokenSenderNickname),
		Self(id: "%_senderUsername_%", title: .Rules.tokenSenderUsername),
		Self(id: "%_senderAddress_%", title: .Rules.tokenSenderAddress),
		Self(id: "%_senderHostmask_%", title: .Rules.tokenSenderHostmask),
		Self(id: "%_serverAddress_%", title: .Rules.tokenServerAddress),
		Self(id: "%_Parameter_0_%", title: .Rules.tokenParameter1),
		Self(id: "%_Parameter_1_%", title: .Rules.tokenParameter2),
		Self(id: "%_Parameter_2_%", title: .Rules.tokenParameter3),
		Self(id: "%_Parameter_3_%", title: .Rules.tokenParameter4),
		Self(id: "%_Parameter_4_%", title: .Rules.tokenParameter5),
		Self(id: "%_Parameter_5_%", title: .Rules.tokenParameter6),
		Self(id: "%_Parameter_6_%", title: .Rules.tokenParameter7),
		Self(id: "%_Parameter_7_%", title: .Rules.tokenParameter8),
		Self(id: "%_Parameter_8_%", title: .Rules.tokenParameter9),
	]
}

struct RuleEditorView: View {
	@State private var model: RuleEditorModel
	@State private var selectedTab: RuleEditorTab = .rule

	let sessions: [MessageRuleSessionOption]
	let onSave: (MessageRule) -> Void
	let onCancel: () -> Void

	init(
		rule: MessageRule,
		sessions: [MessageRuleSessionOption],
		onSave: @escaping (MessageRule) -> Void,
		onCancel: @escaping () -> Void
	) {
		_model = State(initialValue: RuleEditorModel(rule: rule))
		self.sessions = sessions
		self.onSave = onSave
		self.onCancel = onCancel
	}

	var body: some View {
		VStack(spacing: 0) {
			TabView(selection: $selectedTab) {
				generalForm
					.tabItem { Text(String(localized: .Rules.filterTab)) }
					.tag(RuleEditorTab.rule)
				channelsForm
					.tabItem { Text(String(localized: .Rules.channelsTab)) }
					.tag(RuleEditorTab.channels)
				eventsForm
					.tabItem { Text(String(localized: .Rules.eventsTab)) }
					.tag(RuleEditorTab.events)
				senderForm
					.tabItem { Text(String(localized: .Rules.senderTab)) }
					.tag(RuleEditorTab.sender)
				notesForm
					.tabItem { Text(String(localized: .Rules.notesTab)) }
					.tag(RuleEditorTab.notes)
				advancedForm
					.tabItem { Text(String(localized: .Rules.advancedTab)) }
					.tag(RuleEditorTab.advanced)
			}
			.padding(SheetMetrics.margin)

			Divider()

			HStack {
				Spacer()
				Button(String(localized: .Rules.cancelButton), action: onCancel)
					.keyboardShortcut(.cancelAction)
				Button(String(localized: .Rules.saveButton), action: save)
					.keyboardShortcut(.defaultAction)
					.disabled(model.canSave == false)
			}
			.padding(UISpacing.loose)
		}
		.frame(width: 680, height: 560)
	}

	private func save() {
		guard let submitted = model.ruleForSubmission() else { return }
		onSave(submitted)
	}

	private var generalForm: some View {
		Form {
			TextField(String(localized: .Rules.filterTitleLabel), text: $model.rule.title)
			TextField(String(localized: .Rules.filterMatchLabel), text: $model.rule.match)
			validationMessage(model.matchError)
			Text(Self.patternLimitsExplanation)
				.font(.caption)
				.foregroundStyle(.secondary)

			Section(String(localized: .Rules.filterActionSection)) {
				TextEditor(text: $model.rule.action)
					.font(.body.monospaced())
					.frame(minHeight: 110)
					.accessibilityLabel(.Rules.filterActionSection)
				Menu(String(localized: .Rules.insertPlaceholderButton)) {
					ForEach(RuleActionPlaceholder.all) { placeholder in
						Button(String(localized: placeholder.title)) {
							model.rule.action.append(placeholder.id)
						}
					}
				}
			}
		}
		.formStyle(.grouped)
	}

	private var channelsForm: some View {
		Form {
			Picker(String(localized: .Rules.limitFilterLabel), selection: $model.rule.destination) {
				ForEach(MessageRuleDestination.allCases) { destination in
					Text(destinationTitle(destination)).tag(destination)
				}
			}
			.pickerStyle(.radioGroup)

			if model.rule.destination == .specificItems {
				Section(String(localized: .Rules.specificItemsSection)) {
					if sessions.isEmpty {
						ContentUnavailableView(
							String(localized: .Rules.noConnectedServersTitle),
							systemImage: "network.slash"
						)
						.frame(minHeight: 180)
					} else {
						List(sessions) { session in
							sessionSelection(session)
							ForEach(session.channels) { channel in
								Toggle(channel.name, isOn: channelSelection(channel, in: session))
									.toggleStyle(.checkbox)
									.disabled(model.rule.limitedSessionIDs.contains(session.id))
									.padding(.leading, 22)
							}
						}
						.listStyle(.inset(alternatesRowBackgrounds: true))
						.frame(minHeight: 220)
					}
				}
			}
		}
		.formStyle(.grouped)
	}

	private var eventsForm: some View {
		Form {
			Section(String(localized: .Rules.standardEventsSection)) {
				LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading) {
					ForEach(RuleEventOption.all) { option in
						Toggle(String(localized: option.title), isOn: eventBinding(option.event))
							.toggleStyle(.checkbox)
							.disabled(model.eventIsAvailable(option.event) == false)
					}
				}
			}

			Section(String(localized: .Rules.additionalCommandsSection)) {
				TextField(
					String(localized: .Rules.additionalCommandsPlaceholder),
					text: additionalCommands
				)
				validationMessage(model.commandsError)
				Text(String(localized: .Rules.additionalCommandsExplanation))
					.font(.caption)
					.foregroundStyle(.secondary)
			}
		}
		.formStyle(.grouped)
	}

	private var senderForm: some View {
		Form {
			Section {
				Toggle(
					String(localized: .Rules.ignoreOperatorsToggle),
					isOn: $model.rule.ignoresOperators
				)
				.disabled(model.hasMessageEvent == false)
				Toggle(
					String(localized: .Rules.onlyMyMessagesToggle),
					isOn: $model.rule.isLimitedToMyself
				)
			}

			TextField(String(localized: .Rules.senderMatchLabel), text: $model.rule.senderMatch)
				.disabled(model.rule.isLimitedToMyself)
			validationMessage(model.senderMatchError)
			Text(Self.patternLimitsExplanation)
				.font(.caption)
				.foregroundStyle(.secondary)

			Section(String(localized: .Rules.membershipAgeSection)) {
				Picker(
					String(localized: .Rules.ageComparatorLabel),
					selection: $model.rule.ageComparator
				) {
					Text(String(localized: .Rules.lessThanOption))
						.tag(MessageRuleAgeComparator.lessThan)
					Text(String(localized: .Rules.greaterThanOption))
						.tag(MessageRuleAgeComparator.greaterThan)
				}
				TextField(
					String(localized: .Rules.ageSecondsLabel),
					value: $model.rule.ageLimit,
					format: .number
				)
				Text(String(localized: .Rules.zeroDisablesExplanation))
					.font(.caption)
					.foregroundStyle(.secondary)
			}
		}
		.formStyle(.grouped)
	}

	private var notesForm: some View {
		Form {
			Section(String(localized: .Rules.notesSection)) {
				TextEditor(text: $model.rule.notes)
					.frame(minHeight: 300)
					.accessibilityLabel(.Rules.notesSection)
			}
		}
		.formStyle(.grouped)
	}

	private var advancedForm: some View {
		Form {
			Section {
				Toggle(
					String(localized: .Rules.hideOriginalMessageToggle),
					isOn: $model.rule.ignoresContent
				)
				.toggleStyle(.checkbox)
				Toggle(String(localized: .Rules.logFilterMatchToggle), isOn: $model.rule.logsMatch)
					.toggleStyle(.checkbox)
			}

			Section(String(localized: .Rules.forwardDestinationSection)) {
				TextField(
					String(localized: .Rules.forwardDestinationLabel),
					text: $model.rule.forwardDestination
				)
				validationMessage(model.forwardDestinationError)
			}

			Section(String(localized: .Rules.floodControlSection)) {
				TextField(
					String(localized: .Rules.floodControlSecondsLabel),
					value: $model.rule.actionFloodControlInterval,
					format: .number
				)
				Text(String(localized: .Rules.zeroDisablesExplanation))
					.font(.caption)
					.foregroundStyle(.secondary)
			}
		}
		.formStyle(.grouped)
	}

	private var additionalCommands: Binding<String> {
		Binding(
			get: { model.rule.additionalCommands.joined(separator: ", ") },
			set: { model.rule.additionalCommands = $0.components(separatedBy: ",") }
		)
	}

	private func eventBinding(_ event: MessageRuleEvent) -> Binding<Bool> {
		Binding(
			get: { model.rule.events.contains(event) },
			set: { isEnabled in
				if isEnabled {
					model.rule.events.insert(event)
				} else {
					model.rule.events.remove(event)
				}
			}
		)
	}

	private func sessionSelection(_ session: MessageRuleSessionOption) -> some View {
		Button {
			if let index = model.rule.limitedSessionIDs.firstIndex(of: session.id) {
				model.rule.limitedSessionIDs.remove(at: index)
			} else {
				model.rule.limitedSessionIDs.append(session.id)
				let channelIDs = Set(session.channels.map(\.id))
				model.rule.limitedChannelIDs.removeAll { channelIDs.contains($0) }
			}
		} label: {
			HStack(spacing: 6) {
				Image(systemName: sessionSelectionSymbol(session))
					.accessibilityHidden(true)
				Text(session.name)
					.fontWeight(.semibold)
			}
			.frame(maxWidth: .infinity, alignment: .leading)
		}
		.buttonStyle(.plain)
		.accessibilityValue(sessionSelectionDescription(session))
	}

	private func sessionSelectionDescription(_ session: MessageRuleSessionOption) -> LocalizedStringResource {
		if model.rule.limitedSessionIDs.contains(session.id) {
			return .Rules.allChannelsSelected
		}
		if session.channels.contains(where: { model.rule.limitedChannelIDs.contains($0.id) }) {
			return .Rules.someChannelsSelected
		}
		return .Rules.noChannelsSelected
	}

	private func sessionSelectionSymbol(_ session: MessageRuleSessionOption) -> String {
		if model.rule.limitedSessionIDs.contains(session.id) {
			return "checkmark.square"
		}
		if session.channels.contains(where: { model.rule.limitedChannelIDs.contains($0.id) }) {
			return "minus.square"
		}
		return "square"
	}

	private func channelSelection(
		_ channel: MessageRuleChannelOption,
		in session: MessageRuleSessionOption
	) -> Binding<Bool> {
		Binding(
			get: {
				model.rule.limitedSessionIDs.contains(session.id) || model.rule.limitedChannelIDs.contains(channel.id)
			},
			set: { selected in
				guard model.rule.limitedSessionIDs.contains(session.id) == false else { return }
				if selected {
					if model.rule.limitedChannelIDs.contains(channel.id) == false {
						model.rule.limitedChannelIDs.append(channel.id)
					}
				} else {
					model.rule.limitedChannelIDs.removeAll { $0 == channel.id }
				}
			}
		)
	}

	private func destinationTitle(_ destination: MessageRuleDestination) -> String {
		let resource: LocalizedStringResource = switch destination {
		case .unrestricted: .Rules.unrestrictedDestination
		case .channels: .Rules.channelsDestination
		case .privateMessages: .Rules.privateMessagesDestination
		case .specificItems: .Rules.specificItemsDestination
		}
		return String(localized: resource)
	}

	@ViewBuilder
	private func validationMessage(_ message: String?) -> some View {
		if let message {
			Text(message)
				.font(.caption)
				.foregroundStyle(.red)
				.accessibilityLabel(message)
		}
	}

	/// What the two match fields promise: how much of a message a pattern sees,
	/// and that a pattern which can backtrack without bound is refused here
	/// rather than discovered when a peer sends the line that triggers it.
	private static let patternLimitsExplanation = String(
		localized: .Rules.regularExpressionLimitsExplanation(
			MessageRuleMatcher.subjectByteLimit.formatted(.number)
		)
	)
}
