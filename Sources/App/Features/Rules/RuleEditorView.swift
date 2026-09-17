// Copyright (c) 2015 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import SwiftUI

struct MessageRuleChannelOption: Identifiable {
	let id: String
	let name: String
}

struct MessageRuleClientOption: Identifiable {
	let id: String
	let name: String
	let channels: [MessageRuleChannelOption]

	/// The connections and their channels, as the editor lists them for a rule
	/// limited to specific conversations.
	static func current() -> [MessageRuleClientOption] {
		(AppServices.clientDirectory?.clientList ?? []).map { client in
			MessageRuleClientOption(
				id: client.uniqueIdentifier,
				name: client.networkName ?? client.serverAddress ?? client.userNickname,
				channels: client.channelList.filter(\.isChannel).map {
					MessageRuleChannelOption(id: $0.uniqueIdentifier, name: $0.name)
				}
			)
		}
	}
}

private enum RuleEditorTab: Hashable {
	case filter
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
		Self(event: .plainTextMessage, title: .RuleEditor.plainTextMessageEvent),
		Self(event: .actionMessage, title: .RuleEditor.actionMessageEvent),
		Self(event: .noticeMessage, title: .RuleEditor.noticeMessageEvent),
		Self(event: .userJoinedChannel, title: .RuleEditor.userJoinedChannelEvent),
		Self(event: .userLeftChannel, title: .RuleEditor.userLeftChannelEvent),
		Self(event: .userKickedFromChannel, title: .RuleEditor.userKickedFromChannelEvent),
		Self(event: .userDisconnected, title: .RuleEditor.userDisconnectedEvent),
		Self(event: .userChangedNickname, title: .RuleEditor.userChangedNicknameEvent),
		Self(event: .channelTopicReceived, title: .RuleEditor.channelTopicReceivedEvent),
		Self(event: .channelTopicChanged, title: .RuleEditor.channelTopicChangedEvent),
		Self(event: .channelModeReceived, title: .RuleEditor.channelModeReceivedEvent),
		Self(event: .channelModeChanged, title: .RuleEditor.channelModeChangedEvent),
	]
}

private struct RuleActionPlaceholder: Identifiable {
	let id: String
	let title: LocalizedStringResource

	static let all: [Self] = [
		Self(id: "%_channelName_%", title: .RuleEditor.tokenChannelName),
		Self(id: "%_localNickname_%", title: .RuleEditor.tokenLocalNickname),
		Self(id: "%_networkName_%", title: .RuleEditor.tokenNetworkName),
		Self(id: "%_originalMessage_%", title: .RuleEditor.tokenOriginalMessage),
		Self(id: "%_senderNickname_%", title: .RuleEditor.tokenSenderNickname),
		Self(id: "%_senderUsername_%", title: .RuleEditor.tokenSenderUsername),
		Self(id: "%_senderAddress_%", title: .RuleEditor.tokenSenderAddress),
		Self(id: "%_senderHostmask_%", title: .RuleEditor.tokenSenderHostmask),
		Self(id: "%_serverAddress_%", title: .RuleEditor.tokenServerAddress),
		Self(id: "%_Parameter_0_%", title: .RuleEditor.tokenParameter1),
		Self(id: "%_Parameter_1_%", title: .RuleEditor.tokenParameter2),
		Self(id: "%_Parameter_2_%", title: .RuleEditor.tokenParameter3),
		Self(id: "%_Parameter_3_%", title: .RuleEditor.tokenParameter4),
		Self(id: "%_Parameter_4_%", title: .RuleEditor.tokenParameter5),
		Self(id: "%_Parameter_5_%", title: .RuleEditor.tokenParameter6),
		Self(id: "%_Parameter_6_%", title: .RuleEditor.tokenParameter7),
		Self(id: "%_Parameter_7_%", title: .RuleEditor.tokenParameter8),
		Self(id: "%_Parameter_8_%", title: .RuleEditor.tokenParameter9),
	]
}

/** Whether a match pattern compiles.

 Compiling is expensive and a `body` pass asks about two patterns, so this is
 computed when a pattern changes rather than each time the sheet is drawn. How
 long a pattern takes to run is bounded at match time by
 `RegularExpression.matchBudget` instead. */
private struct RulePatternValidation: Equatable {
	var error: String?

	init(pattern: String = "") {
		guard pattern.isEmpty == false else { return }

		do {
			_ = try NSRegularExpression(pattern: pattern)
		} catch let failure {
			error = String(
				localized: .RuleEditor.regularExpressionInvalid(failure.localizedDescription)
			)
		}
	}
}

struct RuleEditorView: View {
	@State private var filter: MessageRule
	@State private var selectedTab: RuleEditorTab = .filter
	@State private var matchValidation = RulePatternValidation()
	@State private var senderValidation = RulePatternValidation()

	let clients: [MessageRuleClientOption]
	let onSave: (MessageRule) -> Void
	let onCancel: () -> Void

	init(
		filter: MessageRule,
		clients: [MessageRuleClientOption],
		onSave: @escaping (MessageRule) -> Void,
		onCancel: @escaping () -> Void
	) {
		_filter = State(initialValue: filter)
		self.clients = clients
		self.onSave = onSave
		self.onCancel = onCancel
	}

	var body: some View {
		VStack(spacing: 0) {
			TabView(selection: $selectedTab) {
				generalForm
					.tabItem { Text(String(localized: .RuleEditor.filterTab)) }
					.tag(RuleEditorTab.filter)
				channelsForm
					.tabItem { Text(String(localized: .RuleEditor.channelsTab)) }
					.tag(RuleEditorTab.channels)
				eventsForm
					.tabItem { Text(String(localized: .RuleEditor.eventsTab)) }
					.tag(RuleEditorTab.events)
				senderForm
					.tabItem { Text(String(localized: .RuleEditor.senderTab)) }
					.tag(RuleEditorTab.sender)
				notesForm
					.tabItem { Text(String(localized: .RuleEditor.notesTab)) }
					.tag(RuleEditorTab.notes)
				advancedForm
					.tabItem { Text(String(localized: .RuleEditor.advancedTab)) }
					.tag(RuleEditorTab.advanced)
			}
			.padding(20)

			Divider()

			HStack {
				Spacer()
				Button(String(localized: .RuleEditor.cancelButton), action: onCancel)
					.keyboardShortcut(.cancelAction)
				Button(String(localized: .RuleEditor.saveButton)) {
					save()
				}
				.keyboardShortcut(.defaultAction)
				.disabled(canSave == false)
			}
			.padding(16)
		}
		.frame(width: 680, height: 560)
		.onChange(of: filter.match, initial: true) { _, pattern in
			matchValidation = RulePatternValidation(pattern: pattern)
		}
		.onChange(of: filter.senderMatch, initial: true) { _, pattern in
			senderValidation = RulePatternValidation(pattern: pattern)
		}
	}

	private var generalForm: some View {
		Form {
			TextField(String(localized: .RuleEditor.filterTitleLabel), text: $filter.title)
			TextField(String(localized: .RuleEditor.filterMatchLabel), text: $filter.match)
			validationMessage(matchError)
			Text(Self.patternLimitsExplanation)
				.font(.caption)
				.foregroundStyle(.secondary)

			Section(String(localized: .RuleEditor.filterActionSection)) {
				TextEditor(text: $filter.action)
					.font(.body.monospaced())
					.frame(minHeight: 110)
				Menu(String(localized: .RuleEditor.insertPlaceholderButton)) {
					ForEach(RuleActionPlaceholder.all) { placeholder in
						Button(String(localized: placeholder.title)) {
							filter.action.append(placeholder.id)
						}
					}
				}
			}
		}
		.formStyle(.grouped)
	}

	private var channelsForm: some View {
		Form {
			Picker(String(localized: .RuleEditor.limitFilterLabel), selection: $filter.destination) {
				ForEach(MessageRuleDestination.allCases) { destination in
					Text(destinationTitle(destination)).tag(destination)
				}
			}
			.pickerStyle(.radioGroup)

			if filter.destination == .specificItems {
				Section(String(localized: .RuleEditor.specificItemsSection)) {
					if clients.isEmpty {
						ContentUnavailableView(
							String(localized: .RuleEditor.noConnectedServersTitle),
							systemImage: "network.slash"
						)
						.frame(minHeight: 180)
					} else {
						List(clients) { client in
							clientSelection(client)
							ForEach(client.channels) { channel in
								Toggle(channel.name, isOn: channelSelection(channel, in: client))
									.toggleStyle(.checkbox)
									.disabled(filter.limitedClientIDs.contains(client.id))
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
			Section(String(localized: .RuleEditor.standardEventsSection)) {
				LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading) {
					ForEach(RuleEventOption.all) { option in
						Toggle(String(localized: option.title), isOn: eventBinding(option.event))
							.toggleStyle(.checkbox)
							.disabled(eventIsAvailable(option.event) == false)
					}
				}
			}

			Section(String(localized: .RuleEditor.additionalCommandsSection)) {
				TextField(
					String(localized: .RuleEditor.additionalCommandsPlaceholder),
					text: additionalCommands
				)
				validationMessage(commandsError)
				Text(String(localized: .RuleEditor.additionalCommandsExplanation))
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
					String(localized: .RuleEditor.ignoreOperatorsToggle),
					isOn: $filter.ignoresOperators
				)
				.disabled(hasMessageEvent == false)
				Toggle(
					String(localized: .RuleEditor.onlyMyMessagesToggle),
					isOn: $filter.isLimitedToMyself
				)
			}

			TextField(String(localized: .RuleEditor.senderMatchLabel), text: $filter.senderMatch)
				.disabled(filter.isLimitedToMyself)
			validationMessage(senderMatchError)
			Text(Self.patternLimitsExplanation)
				.font(.caption)
				.foregroundStyle(.secondary)

			Section(String(localized: .RuleEditor.membershipAgeSection)) {
				Picker(
					String(localized: .RuleEditor.ageComparatorLabel),
					selection: $filter.ageComparator
				) {
					Text(String(localized: .RuleEditor.lessThanOption))
						.tag(MessageRuleAgeComparator.lessThan)
					Text(String(localized: .RuleEditor.greaterThanOption))
						.tag(MessageRuleAgeComparator.greaterThan)
				}
				TextField(
					String(localized: .RuleEditor.ageSecondsLabel),
					value: $filter.ageLimit,
					format: .number
				)
				Text(String(localized: .RuleEditor.zeroDisablesExplanation))
					.font(.caption)
					.foregroundStyle(.secondary)
			}
		}
		.formStyle(.grouped)
	}

	private var notesForm: some View {
		Form {
			Section(String(localized: .RuleEditor.notesSection)) {
				TextEditor(text: $filter.notes)
					.frame(minHeight: 300)
			}
		}
		.formStyle(.grouped)
	}

	private var advancedForm: some View {
		Form {
			Section {
				Toggle(
					String(localized: .RuleEditor.hideOriginalMessageToggle),
					isOn: $filter.ignoresContent
				)
				.toggleStyle(.checkbox)
				Toggle(String(localized: .RuleEditor.logFilterMatchToggle), isOn: $filter.logsMatch)
					.toggleStyle(.checkbox)
			}

			Section(String(localized: .RuleEditor.forwardDestinationSection)) {
				TextField(
					String(localized: .RuleEditor.forwardDestinationLabel),
					text: $filter.forwardDestination
				)
				validationMessage(forwardDestinationError)
			}

			Section(String(localized: .RuleEditor.floodControlSection)) {
				TextField(
					String(localized: .RuleEditor.floodControlSecondsLabel),
					value: $filter.actionFloodControlInterval,
					format: .number
				)
				Text(String(localized: .RuleEditor.zeroDisablesExplanation))
					.font(.caption)
					.foregroundStyle(.secondary)
			}
		}
		.formStyle(.grouped)
	}

	private var canSave: Bool {
		let title = filter.title.trimmingCharacters(in: .whitespacesAndNewlines)
		let action = filter.action.trimmingCharacters(in: .whitespacesAndNewlines)
		let destination = filter.forwardDestination.trimmingCharacters(in: .whitespacesAndNewlines)

		return title.isEmpty == false &&
			(filter.ignoresContent || action.isEmpty == false || destination.isEmpty == false) &&
			matchError == nil && senderMatchError == nil && commandsError == nil && forwardDestinationError == nil
	}

	private var hasMessageEvent: Bool {
		filter.events.isDisjoint(with: [.plainTextMessage, .actionMessage, .noticeMessage]) == false
	}

	private var matchError: String? {
		matchValidation.error
	}

	private var senderMatchError: String? {
		filter.isLimitedToMyself ? nil : senderValidation.error
	}

	private var commandsError: String? {
		normalizedCommands(from: filter.additionalCommands.joined(separator: ", ")) == nil
			? String(localized: .RuleEditor.commandsInvalid)
			: nil
	}

	private var forwardDestinationError: String? {
		let destination = filter.forwardDestination.trimmingCharacters(in: .whitespacesAndNewlines)
		guard destination.isEmpty == false else { return nil }
		if destination.count > 125 {
			return String(localized: .RuleEditor.destinationTooLong)
		}
		let isValid = destination.allSatisfy { $0.isLetter || $0.isNumber || "-_ ".contains($0) }
		return isValid ? nil : String(localized: .RuleEditor.destinationInvalid)
	}

	private var additionalCommands: Binding<String> {
		Binding(
			get: { filter.additionalCommands.joined(separator: ", ") },
			set: { filter.additionalCommands = $0.components(separatedBy: ",") }
		)
	}

	private func save() {
		guard canSave else { return }
		filter.title = filter.title.trimmingCharacters(in: .whitespacesAndNewlines)
		filter.action = filter.action.trimmingCharacters(in: .whitespacesAndNewlines)
		filter.forwardDestination = filter.forwardDestination.trimmingCharacters(in: .whitespacesAndNewlines)
		filter.additionalCommands = normalizedCommands(from: filter.additionalCommands.joined(separator: ", ")) ?? []
		if hasMessageEvent == false {
			filter.ignoresOperators = false
		}
		onSave(filter)
	}

	private func eventBinding(_ event: MessageRuleEvent) -> Binding<Bool> {
		Binding(
			get: { filter.events.contains(event) },
			set: { isEnabled in
				if isEnabled {
					filter.events.insert(event)
				} else {
					filter.events.remove(event)
				}
			}
		)
	}

	private func eventIsAvailable(_ event: MessageRuleEvent) -> Bool {
		filter.destination != .privateMessages ||
			[MessageRuleEvent.plainTextMessage, .actionMessage, .noticeMessage].contains(event)
	}

	private func clientSelection(_ client: MessageRuleClientOption) -> some View {
		Button {
			if let index = filter.limitedClientIDs.firstIndex(of: client.id) {
				filter.limitedClientIDs.remove(at: index)
			} else {
				filter.limitedClientIDs.append(client.id)
				let channelIDs = Set(client.channels.map(\.id))
				filter.limitedChannelIDs.removeAll { channelIDs.contains($0) }
			}
		} label: {
			HStack(spacing: 6) {
				Image(systemName: clientSelectionSymbol(client))
					.accessibilityHidden(true)
				Text(client.name)
					.fontWeight(.semibold)
			}
			.frame(maxWidth: .infinity, alignment: .leading)
		}
		.buttonStyle(.plain)
	}

	private func clientSelectionSymbol(_ client: MessageRuleClientOption) -> String {
		if filter.limitedClientIDs.contains(client.id) {
			return "checkmark.square"
		}
		if client.channels.contains(where: { filter.limitedChannelIDs.contains($0.id) }) {
			return "minus.square"
		}
		return "square"
	}

	private func channelSelection(
		_ channel: MessageRuleChannelOption,
		in client: MessageRuleClientOption
	) -> Binding<Bool> {
		Binding(
			get: {
				filter.limitedClientIDs.contains(client.id) || filter.limitedChannelIDs.contains(channel.id)
			},
			set: { selected in
				guard filter.limitedClientIDs.contains(client.id) == false else { return }
				if selected {
					if filter.limitedChannelIDs.contains(channel.id) == false {
						filter.limitedChannelIDs.append(channel.id)
					}
				} else {
					filter.limitedChannelIDs.removeAll { $0 == channel.id }
				}
			}
		)
	}

	private func destinationTitle(_ destination: MessageRuleDestination) -> String {
		let resource: LocalizedStringResource = switch destination {
		case .unrestricted: .RuleEditor.unrestrictedDestination
		case .channels: .RuleEditor.channelsDestination
		case .privateMessages: .RuleEditor.privateMessagesDestination
		case .specificItems: .RuleEditor.specificItemsDestination
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
		localized: .RuleEditor.regularExpressionLimitsExplanation(
			MessageRuleEngine.subjectByteLimit.formatted(.number)
		)
	)

	private func normalizedCommands(from value: String) -> [String]? {
		var result: [String] = []
		for rawValue in value.components(separatedBy: ",") {
			let command = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
			guard command.isEmpty == false else { continue }
			let normalized: String
			if command.allSatisfy(\.isNumber) {
				guard command.count <= 3, let numeric = Int(command), numeric > 0 else {
					return nil
				}
				normalized = String(format: "%03d", numeric)
			} else if command.allSatisfy({ $0.isLetter || $0.isNumber }), command.count <= 20 {
				normalized = command.uppercased()
			} else {
				return nil
			}
			if result.contains(normalized) == false {
				result.append(normalized)
			}
		}
		return result
	}
}
