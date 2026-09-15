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

import CocoaExtensions
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
		Self(event: .plainTextMessage, title: .ChatFilterEditor.plainTextMessageEvent),
		Self(event: .actionMessage, title: .ChatFilterEditor.actionMessageEvent),
		Self(event: .noticeMessage, title: .ChatFilterEditor.noticeMessageEvent),
		Self(event: .userJoinedChannel, title: .ChatFilterEditor.userJoinedChannelEvent),
		Self(event: .userLeftChannel, title: .ChatFilterEditor.userLeftChannelEvent),
		Self(event: .userKickedFromChannel, title: .ChatFilterEditor.userKickedFromChannelEvent),
		Self(event: .userDisconnected, title: .ChatFilterEditor.userDisconnectedEvent),
		Self(event: .userChangedNickname, title: .ChatFilterEditor.userChangedNicknameEvent),
		Self(event: .channelTopicReceived, title: .ChatFilterEditor.channelTopicReceivedEvent),
		Self(event: .channelTopicChanged, title: .ChatFilterEditor.channelTopicChangedEvent),
		Self(event: .channelModeReceived, title: .ChatFilterEditor.channelModeReceivedEvent),
		Self(event: .channelModeChanged, title: .ChatFilterEditor.channelModeChangedEvent),
	]
}

private struct ChatFilterActionPlaceholder: Identifiable {
	let id: String
	let title: LocalizedStringResource

	static let all: [Self] = [
		Self(id: "%_channelName_%", title: .ChatFilterEditor.tokenChannelName),
		Self(id: "%_localNickname_%", title: .ChatFilterEditor.tokenLocalNickname),
		Self(id: "%_networkName_%", title: .ChatFilterEditor.tokenNetworkName),
		Self(id: "%_originalMessage_%", title: .ChatFilterEditor.tokenOriginalMessage),
		Self(id: "%_senderNickname_%", title: .ChatFilterEditor.tokenSenderNickname),
		Self(id: "%_senderUsername_%", title: .ChatFilterEditor.tokenSenderUsername),
		Self(id: "%_senderAddress_%", title: .ChatFilterEditor.tokenSenderAddress),
		Self(id: "%_senderHostmask_%", title: .ChatFilterEditor.tokenSenderHostmask),
		Self(id: "%_serverAddress_%", title: .ChatFilterEditor.tokenServerAddress),
		Self(id: "%_Parameter_0_%", title: .ChatFilterEditor.tokenParameter1),
		Self(id: "%_Parameter_1_%", title: .ChatFilterEditor.tokenParameter2),
		Self(id: "%_Parameter_2_%", title: .ChatFilterEditor.tokenParameter3),
		Self(id: "%_Parameter_3_%", title: .ChatFilterEditor.tokenParameter4),
		Self(id: "%_Parameter_4_%", title: .ChatFilterEditor.tokenParameter5),
		Self(id: "%_Parameter_5_%", title: .ChatFilterEditor.tokenParameter6),
		Self(id: "%_Parameter_6_%", title: .ChatFilterEditor.tokenParameter7),
		Self(id: "%_Parameter_7_%", title: .ChatFilterEditor.tokenParameter8),
		Self(id: "%_Parameter_8_%", title: .ChatFilterEditor.tokenParameter9),
	]
}

/** What a match pattern is: whether it compiles at all, and whether its shape
 can backtrack for a long time.

 Compiling is the expensive half, and a `body` pass asks several questions
 about two patterns, so this is computed when a pattern changes rather than
 each time the sheet is drawn. */
private struct ChatFilterPatternValidation: Equatable {
	var error: String?

	init(pattern: String = "") {
		guard pattern.isEmpty == false else { return }

		do {
			_ = try NSRegularExpression(pattern: pattern)
		} catch let failure {
			error = String(
				localized: .ChatFilterEditor.regularExpressionInvalid(failure.localizedDescription)
			)
			return
		}

		guard RegularExpression.hasNestedQuantifier(pattern) else { return }

		error = String(localized: .ChatFilterEditor.regularExpressionNestedQuantifier)
	}
}

struct ChatFilterEditorView: View {
	@State private var filter: ChatFilter
	@State private var selectedTab: ChatFilterEditorTab = .filter
	@State private var matchValidation = ChatFilterPatternValidation()
	@State private var senderValidation = ChatFilterPatternValidation()

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
					.tabItem { Text(String(localized: .ChatFilterEditor.filterTab)) }
					.tag(ChatFilterEditorTab.filter)
				channelsForm
					.tabItem { Text(String(localized: .ChatFilterEditor.channelsTab)) }
					.tag(ChatFilterEditorTab.channels)
				eventsForm
					.tabItem { Text(String(localized: .ChatFilterEditor.eventsTab)) }
					.tag(ChatFilterEditorTab.events)
				senderForm
					.tabItem { Text(String(localized: .ChatFilterEditor.senderTab)) }
					.tag(ChatFilterEditorTab.sender)
				notesForm
					.tabItem { Text(String(localized: .ChatFilterEditor.notesTab)) }
					.tag(ChatFilterEditorTab.notes)
				advancedForm
					.tabItem { Text(String(localized: .ChatFilterEditor.advancedTab)) }
					.tag(ChatFilterEditorTab.advanced)
			}
			.padding(20)

			Divider()

			HStack {
				Spacer()
				Button(String(localized: .ChatFilterEditor.cancelButton), action: onCancel)
					.keyboardShortcut(.cancelAction)
				Button(String(localized: .ChatFilterEditor.saveButton)) {
					save()
				}
				.keyboardShortcut(.defaultAction)
				.disabled(canSave == false)
			}
			.padding(16)
		}
		.frame(width: 680, height: 560)
		.onChange(of: filter.match, initial: true) { _, pattern in
			matchValidation = ChatFilterPatternValidation(pattern: pattern)
		}
		.onChange(of: filter.senderMatch, initial: true) { _, pattern in
			senderValidation = ChatFilterPatternValidation(pattern: pattern)
		}
	}

	private var generalForm: some View {
		Form {
			TextField(String(localized: .ChatFilterEditor.filterTitleLabel), text: $filter.title)
			TextField(String(localized: .ChatFilterEditor.filterMatchLabel), text: $filter.match)
			validationMessage(matchError)
			Text(Self.patternLimitsExplanation)
				.font(.caption)
				.foregroundStyle(.secondary)

			Section(String(localized: .ChatFilterEditor.filterActionSection)) {
				TextEditor(text: $filter.action)
					.font(.body.monospaced())
					.frame(minHeight: 110)
				Menu(String(localized: .ChatFilterEditor.insertPlaceholderButton)) {
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
			Picker(String(localized: .ChatFilterEditor.limitFilterLabel), selection: $filter.destination) {
				ForEach(ChatFilterDestination.allCases) { destination in
					Text(destinationTitle(destination)).tag(destination)
				}
			}
			.pickerStyle(.radioGroup)

			if filter.destination == .specificItems {
				Section(String(localized: .ChatFilterEditor.specificItemsSection)) {
					if clients.isEmpty {
						ContentUnavailableView(
							String(localized: .ChatFilterEditor.noConnectedServersTitle),
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
			Section(String(localized: .ChatFilterEditor.standardEventsSection)) {
				LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading) {
					ForEach(ChatFilterEventOption.all) { option in
						Toggle(String(localized: option.title), isOn: eventBinding(option.event))
							.toggleStyle(.checkbox)
							.disabled(eventIsAvailable(option.event) == false)
					}
				}
			}

			Section(String(localized: .ChatFilterEditor.additionalCommandsSection)) {
				TextField(
					String(localized: .ChatFilterEditor.additionalCommandsPlaceholder),
					text: additionalCommands
				)
				validationMessage(commandsError)
				Text(String(localized: .ChatFilterEditor.additionalCommandsExplanation))
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
					String(localized: .ChatFilterEditor.ignoreOperatorsToggle),
					isOn: $filter.ignoresOperators
				)
				.disabled(hasMessageEvent == false)
				Toggle(
					String(localized: .ChatFilterEditor.onlyMyMessagesToggle),
					isOn: $filter.isLimitedToMyself
				)
			}

			TextField(String(localized: .ChatFilterEditor.senderMatchLabel), text: $filter.senderMatch)
				.disabled(filter.isLimitedToMyself)
			validationMessage(senderMatchError)
			Text(Self.patternLimitsExplanation)
				.font(.caption)
				.foregroundStyle(.secondary)

			Section(String(localized: .ChatFilterEditor.membershipAgeSection)) {
				Picker(
					String(localized: .ChatFilterEditor.ageComparatorLabel),
					selection: $filter.ageComparator
				) {
					Text(String(localized: .ChatFilterEditor.lessThanOption))
						.tag(ChatFilterAgeComparator.lessThan)
					Text(String(localized: .ChatFilterEditor.greaterThanOption))
						.tag(ChatFilterAgeComparator.greaterThan)
				}
				TextField(
					String(localized: .ChatFilterEditor.ageSecondsLabel),
					value: $filter.ageLimit,
					format: .number
				)
				Text(String(localized: .ChatFilterEditor.zeroDisablesExplanation))
					.font(.caption)
					.foregroundStyle(.secondary)
			}
		}
		.formStyle(.grouped)
	}

	private var notesForm: some View {
		Form {
			Section(String(localized: .ChatFilterEditor.notesSection)) {
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
					String(localized: .ChatFilterEditor.hideOriginalMessageToggle),
					isOn: $filter.ignoresContent
				)
				.toggleStyle(.checkbox)
				Toggle(String(localized: .ChatFilterEditor.logFilterMatchToggle), isOn: $filter.logsMatch)
					.toggleStyle(.checkbox)
			}

			Section(String(localized: .ChatFilterEditor.forwardDestinationSection)) {
				TextField(
					String(localized: .ChatFilterEditor.forwardDestinationLabel),
					text: $filter.forwardDestination
				)
				validationMessage(forwardDestinationError)
			}

			Section(String(localized: .ChatFilterEditor.floodControlSection)) {
				TextField(
					String(localized: .ChatFilterEditor.floodControlSecondsLabel),
					value: $filter.actionFloodControlInterval,
					format: .number
				)
				Text(String(localized: .ChatFilterEditor.zeroDisablesExplanation))
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
			? String(localized: .ChatFilterEditor.commandsInvalid)
			: nil
	}

	private var forwardDestinationError: String? {
		let destination = filter.forwardDestination.trimmingCharacters(in: .whitespacesAndNewlines)
		guard destination.isEmpty == false else { return nil }
		if destination.count > 125 {
			return String(localized: .ChatFilterEditor.destinationTooLong)
		}
		let isValid = destination.allSatisfy { $0.isLetter || $0.isNumber || "-_ ".contains($0) }
		return isValid ? nil : String(localized: .ChatFilterEditor.destinationInvalid)
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
		case .unrestricted: .ChatFilterEditor.unrestrictedDestination
		case .channels: .ChatFilterEditor.channelsDestination
		case .privateMessages: .ChatFilterEditor.privateMessagesDestination
		case .specificItems: .ChatFilterEditor.specificItemsDestination
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
		localized: .ChatFilterEditor.regularExpressionLimitsExplanation(
			ChatFilterEngine.subjectByteLimit.formatted(.number)
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
