/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2015 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import SwiftUI

struct ChatFilterChannelOption: Identifiable {
	let id: String
	let name: String
}

struct ChatFilterClientOption: Identifiable {
	let id: String
	let name: String
	let channels: [ChatFilterChannelOption]
}

private enum ChatFilterEditorTab: Hashable {
	case filter
	case channels
	case events
	case sender
	case notes
	case advanced
}

private struct ChatFilterEventOption: Identifiable {
	let event: ChatFilterEvent
	let title: LocalizedStringResource

	var id: UInt {
		event.rawValue
	}

	static let all: [Self] = [
		Self(event: .plainTextMessage, title: .TPIChatFilterEditFilterSheet.plainTextMessageEvent),
		Self(event: .actionMessage, title: .TPIChatFilterEditFilterSheet.actionMessageEvent),
		Self(event: .noticeMessage, title: .TPIChatFilterEditFilterSheet.noticeMessageEvent),
		Self(event: .userJoinedChannel, title: .TPIChatFilterEditFilterSheet.userJoinedChannelEvent),
		Self(event: .userLeftChannel, title: .TPIChatFilterEditFilterSheet.userLeftChannelEvent),
		Self(event: .userKickedFromChannel, title: .TPIChatFilterEditFilterSheet.userKickedFromChannelEvent),
		Self(event: .userDisconnected, title: .TPIChatFilterEditFilterSheet.userDisconnectedEvent),
		Self(event: .userChangedNickname, title: .TPIChatFilterEditFilterSheet.userChangedNicknameEvent),
		Self(event: .channelTopicReceived, title: .TPIChatFilterEditFilterSheet.channelTopicReceivedEvent),
		Self(event: .channelTopicChanged, title: .TPIChatFilterEditFilterSheet.channelTopicChangedEvent),
		Self(event: .channelModeReceived, title: .TPIChatFilterEditFilterSheet.channelModeReceivedEvent),
		Self(event: .channelModeChanged, title: .TPIChatFilterEditFilterSheet.channelModeChangedEvent),
	]
}

private struct ChatFilterActionPlaceholder: Identifiable {
	let id: String
	let title: LocalizedStringResource

	static let all: [Self] = [
		Self(id: "%_channelName_%", title: .TPIChatFilterEditFilterSheet.tokenChannelName),
		Self(id: "%_localNickname_%", title: .TPIChatFilterEditFilterSheet.tokenLocalNickname),
		Self(id: "%_networkName_%", title: .TPIChatFilterEditFilterSheet.tokenNetworkName),
		Self(id: "%_originalMessage_%", title: .TPIChatFilterEditFilterSheet.tokenOriginalMessage),
		Self(id: "%_senderNickname_%", title: .TPIChatFilterEditFilterSheet.tokenSenderNickname),
		Self(id: "%_senderUsername_%", title: .TPIChatFilterEditFilterSheet.tokenSenderUsername),
		Self(id: "%_senderAddress_%", title: .TPIChatFilterEditFilterSheet.tokenSenderAddress),
		Self(id: "%_senderHostmask_%", title: .TPIChatFilterEditFilterSheet.tokenSenderHostmask),
		Self(id: "%_serverAddress_%", title: .TPIChatFilterEditFilterSheet.tokenServerAddress),
		Self(id: "%_Parameter_0_%", title: .TPIChatFilterEditFilterSheet.tokenParameter1),
		Self(id: "%_Parameter_1_%", title: .TPIChatFilterEditFilterSheet.tokenParameter2),
		Self(id: "%_Parameter_2_%", title: .TPIChatFilterEditFilterSheet.tokenParameter3),
		Self(id: "%_Parameter_3_%", title: .TPIChatFilterEditFilterSheet.tokenParameter4),
		Self(id: "%_Parameter_4_%", title: .TPIChatFilterEditFilterSheet.tokenParameter5),
		Self(id: "%_Parameter_5_%", title: .TPIChatFilterEditFilterSheet.tokenParameter6),
		Self(id: "%_Parameter_6_%", title: .TPIChatFilterEditFilterSheet.tokenParameter7),
		Self(id: "%_Parameter_7_%", title: .TPIChatFilterEditFilterSheet.tokenParameter8),
		Self(id: "%_Parameter_8_%", title: .TPIChatFilterEditFilterSheet.tokenParameter9),
	]
}

struct ChatFilterEditorView: View {
	@State private var filter: ChatFilter
	@State private var selectedTab: ChatFilterEditorTab = .filter

	let clients: [ChatFilterClientOption]
	let onSave: (ChatFilter) -> Void
	let onCancel: () -> Void

	init(
		filter: ChatFilter,
		clients: [ChatFilterClientOption],
		onSave: @escaping (ChatFilter) -> Void,
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
					.tabItem { Text(String(localized: .TPIChatFilterEditFilterSheet.filterTab)) }
					.tag(ChatFilterEditorTab.filter)
				channelsForm
					.tabItem { Text(String(localized: .TPIChatFilterEditFilterSheet.channelsTab)) }
					.tag(ChatFilterEditorTab.channels)
				eventsForm
					.tabItem { Text(String(localized: .TPIChatFilterEditFilterSheet.eventsTab)) }
					.tag(ChatFilterEditorTab.events)
				senderForm
					.tabItem { Text(String(localized: .TPIChatFilterEditFilterSheet.senderTab)) }
					.tag(ChatFilterEditorTab.sender)
				notesForm
					.tabItem { Text(String(localized: .TPIChatFilterEditFilterSheet.notesTab)) }
					.tag(ChatFilterEditorTab.notes)
				advancedForm
					.tabItem { Text(String(localized: .TPIChatFilterEditFilterSheet.advancedTab)) }
					.tag(ChatFilterEditorTab.advanced)
			}
			.padding(20)

			Divider()

			HStack {
				Spacer()
				Button(String(localized: .TPIChatFilterEditFilterSheet.cancelButton), action: onCancel)
					.keyboardShortcut(.cancelAction)
				Button(String(localized: .TPIChatFilterEditFilterSheet.saveButton)) {
					save()
				}
				.keyboardShortcut(.defaultAction)
				.disabled(canSave == false)
			}
			.padding(16)
		}
		.frame(width: 680, height: 560)
	}

	private var generalForm: some View {
		Form {
			TextField(String(localized: .TPIChatFilterEditFilterSheet.filterTitleLabel), text: $filter.title)
			TextField(String(localized: .TPIChatFilterEditFilterSheet.filterMatchLabel), text: $filter.match)
			validationMessage(matchError)

			Section(String(localized: .TPIChatFilterEditFilterSheet.filterActionSection)) {
				TextEditor(text: $filter.action)
					.font(.body.monospaced())
					.frame(minHeight: 110)
				Menu(String(localized: .TPIChatFilterEditFilterSheet.insertPlaceholderButton)) {
					ForEach(ChatFilterActionPlaceholder.all) { placeholder in
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
			Picker(String(localized: .TPIChatFilterEditFilterSheet.limitFilterLabel), selection: $filter.destination) {
				ForEach(ChatFilterDestination.allCases) { destination in
					Text(destinationTitle(destination)).tag(destination)
				}
			}
			.pickerStyle(.radioGroup)

			if filter.destination == .specificItems {
				Section(String(localized: .TPIChatFilterEditFilterSheet.specificItemsSection)) {
					if clients.isEmpty {
						ContentUnavailableView(
							String(localized: .TPIChatFilterEditFilterSheet.noConnectedServersTitle),
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
			Section(String(localized: .TPIChatFilterEditFilterSheet.standardEventsSection)) {
				LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading) {
					ForEach(ChatFilterEventOption.all) { option in
						Toggle(String(localized: option.title), isOn: eventBinding(option.event))
							.toggleStyle(.checkbox)
							.disabled(eventIsAvailable(option.event) == false)
					}
				}
			}

			Section(String(localized: .TPIChatFilterEditFilterSheet.additionalCommandsSection)) {
				TextField(
					String(localized: .TPIChatFilterEditFilterSheet.additionalCommandsPlaceholder),
					text: additionalCommands
				)
				validationMessage(commandsError)
				Text(String(localized: .TPIChatFilterEditFilterSheet.additionalCommandsExplanation))
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
					String(localized: .TPIChatFilterEditFilterSheet.ignoreOperatorsToggle),
					isOn: $filter.ignoresOperators
				)
				.disabled(hasMessageEvent == false)
				Toggle(
					String(localized: .TPIChatFilterEditFilterSheet.onlyMyMessagesToggle),
					isOn: $filter.isLimitedToMyself
				)
			}

			TextField(String(localized: .TPIChatFilterEditFilterSheet.senderMatchLabel), text: $filter.senderMatch)
				.disabled(filter.isLimitedToMyself)
			validationMessage(senderMatchError)

			Section(String(localized: .TPIChatFilterEditFilterSheet.membershipAgeSection)) {
				Picker(
					String(localized: .TPIChatFilterEditFilterSheet.ageComparatorLabel),
					selection: $filter.ageComparator
				) {
					Text(String(localized: .TPIChatFilterEditFilterSheet.lessThanOption))
						.tag(ChatFilterAgeComparator.lessThan)
					Text(String(localized: .TPIChatFilterEditFilterSheet.greaterThanOption))
						.tag(ChatFilterAgeComparator.greaterThan)
				}
				TextField(
					String(localized: .TPIChatFilterEditFilterSheet.ageSecondsLabel),
					value: $filter.ageLimit,
					format: .number
				)
				Text(String(localized: .TPIChatFilterEditFilterSheet.zeroDisablesExplanation))
					.font(.caption)
					.foregroundStyle(.secondary)
			}
		}
		.formStyle(.grouped)
	}

	private var notesForm: some View {
		Form {
			Section(String(localized: .TPIChatFilterEditFilterSheet.notesSection)) {
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
					String(localized: .TPIChatFilterEditFilterSheet.hideOriginalMessageToggle),
					isOn: $filter.ignoresContent
				)
				Toggle(String(localized: .TPIChatFilterEditFilterSheet.logFilterMatchToggle), isOn: $filter.logsMatch)
			}

			Section(String(localized: .TPIChatFilterEditFilterSheet.forwardDestinationSection)) {
				TextField(
					String(localized: .TPIChatFilterEditFilterSheet.forwardDestinationLabel),
					text: $filter.forwardDestination
				)
				validationMessage(forwardDestinationError)
			}

			Section(String(localized: .TPIChatFilterEditFilterSheet.floodControlSection)) {
				TextField(
					String(localized: .TPIChatFilterEditFilterSheet.floodControlSecondsLabel),
					value: $filter.actionFloodControlInterval,
					format: .number
				)
				Text(String(localized: .TPIChatFilterEditFilterSheet.zeroDisablesExplanation))
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
		regularExpressionError(filter.match)
	}

	private var senderMatchError: String? {
		filter.isLimitedToMyself ? nil : regularExpressionError(filter.senderMatch)
	}

	private var commandsError: String? {
		normalizedCommands(from: filter.additionalCommands.joined(separator: ", ")) == nil
			? String(localized: .TPIChatFilterEditFilterSheet.commandsInvalid)
			: nil
	}

	private var forwardDestinationError: String? {
		let destination = filter.forwardDestination.trimmingCharacters(in: .whitespacesAndNewlines)
		guard destination.isEmpty == false else { return nil }
		if destination.count > 125 {
			return String(localized: .TPIChatFilterEditFilterSheet.destinationTooLong)
		}
		let isValid = destination.allSatisfy { $0.isLetter || $0.isNumber || "-_ ".contains($0) }
		return isValid ? nil : String(localized: .TPIChatFilterEditFilterSheet.destinationInvalid)
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

	private func eventBinding(_ event: ChatFilterEvent) -> Binding<Bool> {
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

	private func eventIsAvailable(_ event: ChatFilterEvent) -> Bool {
		filter.destination != .privateMessages ||
			[ChatFilterEvent.plainTextMessage, .actionMessage, .noticeMessage].contains(event)
	}

	private func clientSelection(_ client: ChatFilterClientOption) -> some View {
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

	private func clientSelectionSymbol(_ client: ChatFilterClientOption) -> String {
		if filter.limitedClientIDs.contains(client.id) {
			return "checkmark.square"
		}
		if client.channels.contains(where: { filter.limitedChannelIDs.contains($0.id) }) {
			return "minus.square"
		}
		return "square"
	}

	private func channelSelection(
		_ channel: ChatFilterChannelOption,
		in client: ChatFilterClientOption
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

	private func destinationTitle(_ destination: ChatFilterDestination) -> String {
		let resource: LocalizedStringResource = switch destination {
		case .unrestricted: .TPIChatFilterEditFilterSheet.unrestrictedDestination
		case .channels: .TPIChatFilterEditFilterSheet.channelsDestination
		case .privateMessages: .TPIChatFilterEditFilterSheet.privateMessagesDestination
		case .specificItems: .TPIChatFilterEditFilterSheet.specificItemsDestination
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

	private func regularExpressionError(_ pattern: String) -> String? {
		guard pattern.isEmpty == false else { return nil }
		do {
			_ = try NSRegularExpression(pattern: pattern)
			return nil
		} catch {
			return String(localized: .TPIChatFilterEditFilterSheet.regularExpressionInvalid(error.localizedDescription))
		}
	}

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
