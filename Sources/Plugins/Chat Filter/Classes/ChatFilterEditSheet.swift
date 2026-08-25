/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2015 - 2018 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *  * Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *  * Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *  * Neither the name of Textual, "Codeux Software, LLC", nor the
 *    names of its contributors may be used to endorse or promote products
 *    derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 *********************************************************************** */

import AppKit

private enum ChatFilterEditSection: Int {
	case general, channels, events, sender, notes, advanced
}

@objc(TPI_ChatFilterEditFilterSheet)
@objcMembers
@MainActor
final class ChatFilterEditSheet: TDCSheetBase {
	private var filter: MutableChatFilter
	private var autoCompletedTokens: [String] = []

	@IBOutlet private var contentViewTabView: NSTabView!
	@IBOutlet private var filterAgeLimitTextField: NSTextField!
	@IBOutlet private var filterMatchTextField: NSTextField!
	@IBOutlet private var filterSenderMatchTextField: NSTextField!
	@IBOutlet private var filterTitleTextField: NSTextField!
	@IBOutlet private var filterNotesTextField: NSTextField!
	@IBOutlet private var filterActionFloodControlIntervalTextField: NSTextField!
	@IBOutlet private var filterEventNumericTextField: TVCValidatedTextField!
	@IBOutlet private var filterForwardToDestinationTextField: TVCValidatedTextField!
	@IBOutlet private var filterActionTokenField: TVCAutoExpandingTokenField!
	@IBOutlet private var filterActionTokenChannelName: NSTokenField!
	@IBOutlet private var filterActionTokenLocalNickname: NSTokenField!
	@IBOutlet private var filterActionTokenNetworkName: NSTokenField!
	@IBOutlet private var filterActionTokenOriginalMessage: NSTokenField!
	@IBOutlet private var filterActionTokenSenderAddress: NSTokenField!
	@IBOutlet private var filterActionTokenSenderHostmask: NSTokenField!
	@IBOutlet private var filterActionTokenSenderNickname: NSTokenField!
	@IBOutlet private var filterActionTokenSenderUsername: NSTokenField!
	@IBOutlet private var filterActionTokenServerAddress: NSTokenField!
	@IBOutlet private var filterLimitedToHostView: NSView!
	@IBOutlet private var filterLimitedToSelectionHostView: NSView!
	@IBOutlet private var filterAgeLimitComparatorButton: NSPopUpButton!
	@IBOutlet private var filterLimitToNoLimitButton: NSButton!
	@IBOutlet private var filterLimitToOnlyChannelsButton: NSButton!
	@IBOutlet private var filterLimitToOnlyPrivateMessagesButton: NSButton!
	@IBOutlet private var filterLimitToSpecificItemsButton: NSButton!
	@IBOutlet private var filterIgnoreContentCheck: NSButton!
	@IBOutlet private var filterIgnoreOperatorsCheck: NSButton!
	@IBOutlet private var filterLogMatchCheck: NSButton!
	@IBOutlet private var filterEventPlainTextMessageCheck: NSButton!
	@IBOutlet private var filterEventActionMessageCheck: NSButton!
	@IBOutlet private var filterEventNoticeMessageCheck: NSButton!
	@IBOutlet private var filterEventUserJoinedChannelCheck: NSButton!
	@IBOutlet private var filterEventUserLeftChannelCheck: NSButton!
	@IBOutlet private var filterEventUserKickedFromChannelCheck: NSButton!
	@IBOutlet private var filterEventUserDisconnectedCheck: NSButton!
	@IBOutlet private var filterEventUserChangedNicknameCheck: NSButton!
	@IBOutlet private var filterEventChannelTopicReceivedCheck: NSButton!
	@IBOutlet private var filterEventChannelTopicChangedCheck: NSButton!
	@IBOutlet private var filterEventChannelModeReceivedCheck: NSButton!
	@IBOutlet private var filterEventChannelModeChangedCheck: NSButton!
	@IBOutlet private var filterLimitedToMyselfCheck: NSButton!
	@IBOutlet private var filterLimitToSelectionOutlineView: TVCChannelSelectionViewController!

	dynamic var filterIgnoreOperatorsCheckEnabled = true
	dynamic var filterIgnoreOperatorsCheckValue: Bool {
		get { filterIgnoreOperatorsCheckEnabled && filter.filterIgnoreOperators }
		set { filter.filterIgnoreOperators = newValue }
	}

	@objc(initWithFilter:)
	init(filter: ChatFilter?) {
		self.filter = filter?.mutableCopy() as? MutableChatFilter ?? MutableChatFilter()
		super.init(window: nil)
		prepareInitialState()
	}

	@available(*, unavailable)
	required init?(coder _: NSCoder) {
		fatalError("init(coder:) is unavailable")
	}

	private func prepareInitialState() {
		Bundle(for: Self.self).loadNibNamed("TPI_ChatFilterEditFilterSheet", owner: self, topLevelObjects: nil)
		populateTokenFields()
		setupTextFieldRules()
		loadFilter()
		updateUIState()
		toggleOkButton()
		filterLimitToSelectionOutlineView.attach(to: filterLimitedToSelectionHostView)
	}

	func start() {
		startSheet()
	}

	private func loadFilter() {
		filterMatchTextField.stringValue = filter.filterMatch
		setTokens(filter.filterAction, in: filterActionTokenField)
		filterAgeLimitComparatorButton.selectItem(withTag: Int(filter.filterAgeComparator))
		filterAgeLimitTextField.integerValue = Int(filter.filterAgeLimit)
		filterActionFloodControlIntervalTextField.integerValue = Int(filter.filterActionFloodControlInterval)
		filterTitleTextField.stringValue = filter.filterTitle
		filterNotesTextField.stringValue = filter.filterNotes
		filterSenderMatchTextField.stringValue = filter.filterSenderMatch
		filterForwardToDestinationTextField.stringValue = filter.filterForwardToDestination
		filterIgnoreContentCheck.state = state(filter.filterIgnoreContent)
		filterIgnoreOperatorsCheck.state = state(filter.filterIgnoreOperators)
		filterLogMatchCheck.state = state(filter.filterLogMatch)
		filterLimitedToMyselfCheck.state = state(filter.filterLimitedToMyself)

		for (button, event) in eventButtons {
			button.state = state(filter.isEventTypeEnabled(event))
		}
		filterEventNumericTextField.stringValue = filter.filterEventsNumerics.joined(separator: ", ")
		filterLimitToSelectionOutlineView.selectedClientIds = filter.filterLimitedToClientsIDs
		filterLimitToSelectionOutlineView.selectedChannelIds = filter.filterLimitedToChannelsIDs
	}

	private func saveFilter() {
		filter.filterMatch = filterMatchTextField.stringValue
		filter.filterAction = stringValue(for: filterActionTokenField)
		filter.filterAgeComparator = UInt(filterAgeLimitComparatorButton.selectedTag())
		filter.filterAgeLimit = UInt(max(0, filterAgeLimitTextField.integerValue))
		filter.filterActionFloodControlInterval = UInt(max(0, filterActionFloodControlIntervalTextField.integerValue))
		filter.filterTitle = filterTitleTextField.stringValue
		filter.filterNotes = filterNotesTextField.stringValue
		filter.filterSenderMatch = filterSenderMatchTextField.stringValue
		filter.filterForwardToDestination = filterForwardToDestinationTextField.stringValue
		filter.filterIgnoreOperators = filterIgnoreOperatorsCheck.state == .on
		filter.filterIgnoreContent = filterIgnoreContentCheck.state == .on
		filter.filterLogMatch = filterLogMatchCheck.state == .on
		filter.filterLimitedToMyself = filterLimitedToMyselfCheck.state == .on
		filter.filterEvents = compileEvents().rawValue
		filter.filterEventsNumerics = compileNumerics() ?? []
		filter.filterLimitedToClientsIDs = filterLimitToSelectionOutlineView.selectedClientIds
		filter.filterLimitedToChannelsIDs = filterLimitToSelectionOutlineView.selectedChannelIds
	}

	private var eventButtons: [(NSButton, ChatFilterEvent)] {
		[
			(filterEventPlainTextMessageCheck, .plainTextMessage),
			(filterEventActionMessageCheck, .actionMessage),
			(filterEventNoticeMessageCheck, .noticeMessage),
			(filterEventUserJoinedChannelCheck, .userJoinedChannel),
			(filterEventUserLeftChannelCheck, .userLeftChannel),
			(filterEventUserKickedFromChannelCheck, .userKickedFromChannel),
			(filterEventUserDisconnectedCheck, .userDisconnected),
			(filterEventUserChangedNicknameCheck, .userChangedNickname),
			(filterEventChannelTopicReceivedCheck, .channelTopicReceived),
			(filterEventChannelTopicChangedCheck, .channelTopicChanged),
			(filterEventChannelModeReceivedCheck, .channelModeReceived),
			(filterEventChannelModeChangedCheck, .channelModeChanged),
		]
	}

	private func compileEvents() -> ChatFilterEvent {
		eventButtons.reduce(into: ChatFilterEvent()) { events, pair in
			if pair.0.state == .on {
				events.insert(pair.1)
			}
		}
	}

	private func compileNumerics() -> [String]? {
		var result: [String] = []
		for rawValue in filterEventNumericTextField.value.components(separatedBy: ",") {
			let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
			if value.isEmpty {
				continue
			}
			let normalized: String
			if value.allSatisfy(\.isNumber), value.count <= 3 {
				normalized = String(Int(value) ?? 0)
			} else if value.allSatisfy({ $0.isLetter || $0.isNumber }), value.count <= 20 {
				normalized = value.uppercased()
			} else {
				return nil
			}
			if !result.contains(normalized) {
				result.append(normalized)
			}
		}
		return result
	}

	override func ok(_ sender: Any?) {
		guard validate() else { return }
		saveFilter()
		let selector = NSSelectorFromString("chatFilterEditFilterSheet:onOk:")
		if let delegate, delegate.responds(to: selector) {
			_ = delegate.perform(selector, with: self, with: filter.copy())
		}
		super.ok(sender)
	}

	private func validate() -> Bool {
		validate(filterEventNumericTextField, section: .events) &&
			validate(filterForwardToDestinationTextField, section: .advanced)
	}

	private func validate(_ field: TVCValidatedTextField, section: ChatFilterEditSection) -> Bool {
		guard !field.valueIsValid else { return true }
		contentViewTabView.selectTabViewItem(at: section.rawValue)
		DispatchQueue.main.async { field.showValidationErrorPopover() }
		return false
	}

	func windowWillClose(_: Notification) {
		NotificationCenter.default.removeObserver(self)
		let selector = NSSelectorFromString("chatFilterEditFilterSheetWillClose:")
		if let delegate, delegate.responds(to: selector) {
			_ = delegate.perform(selector, with: self)
		}
	}

	private func populateTokenFields() {
		filterActionTokenField.tokenizingCharacterSet = CharacterSet()
		filterActionTokenField.completionDelay = 0.2
		let fields: [(NSTokenField, String)] = [
			(filterActionTokenChannelName, "%_channelName_%"),
			(filterActionTokenLocalNickname, "%_localNickname_%"),
			(filterActionTokenNetworkName, "%_networkName_%"),
			(filterActionTokenOriginalMessage, "%_originalMessage_%"),
			(filterActionTokenSenderNickname, "%_senderNickname_%"),
			(filterActionTokenSenderUsername, "%_senderUsername_%"),
			(filterActionTokenSenderAddress, "%_senderAddress_%"),
			(filterActionTokenSenderHostmask, "%_senderHostmask_%"),
			(filterActionTokenServerAddress, "%_serverAddress_%"),
		]
		for (field, token) in fields {
			field.objectValue = [ChatFilterActionToken(token: token)]
		}
	}

	func tokenField(_: NSTokenField, readFrom pasteboard: NSPasteboard) -> [Any]? {
		tokens(from: pasteboard.string(forType: .string))
	}

	func tokenField(_: NSTokenField, writeRepresentedObjects objects: [Any], to pasteboard: NSPasteboard) -> Bool {
		pasteboard.clearContents()
		return pasteboard.setString(objects.map(String.init(describing:)).joined(), forType: .string)
	}

	func tokenField(_: NSTokenField, styleForRepresentedObject object: Any) -> NSTokenField.TokenStyle {
		object is ChatFilterActionToken ? .rounded : .none
	}

	func tokenField(_: NSTokenField, displayStringForRepresentedObject object: Any) -> String? {
		(object as? ChatFilterActionToken)?.title ?? object as? String
	}

	func tokenField(_ tokenField: NSTokenField, representedObjectForEditingString editingString: String) -> Any? {
		guard tokenField === filterActionTokenField else { return editingString }
		return autoCompletedTokens
			.first(where: { $0.range(of: editingString, options: [.anchored, .caseInsensitive]) != nil })
			.flatMap(ChatFilterActionToken.init(title:)) ?? editingString
	}

	func tokenField(
		_ tokenField: NSTokenField,
		completionsForSubstring substring: String,
		indexOfToken _: Int,
		indexOfSelectedItem _: UnsafeMutablePointer<Int>?
	) -> [Any]? {
		guard tokenField === filterActionTokenField else { return nil }
		autoCompletedTokens = ChatFilterActionToken.titles.filter {
			$0.range(of: substring, options: [.anchored, .caseInsensitive]) != nil
		}
		return autoCompletedTokens
	}

	func performFilterActionTokenCompletion() {}

	private func stringValue(for field: NSTokenField) -> String {
		(field.objectValue as? [Any] ?? []).map(String.init(describing:)).joined()
	}

	private func setTokens(_ string: String, in field: NSTokenField) {
		field.objectValue = tokens(from: string)
	}

	private func tokens(from value: String?) -> [Any] {
		guard let value, !value.isEmpty else { return value.map { [$0] } ?? [] }
		let expression = try? NSRegularExpression(pattern: "%_([a-zA-Z0-9_]+)_%")
		let range = NSRange(value.startIndex..., in: value)
		var result: [Any] = []
		var cursor = value.startIndex
		for match in expression?.matches(in: value, range: range) ?? [] {
			guard let tokenRange = Range(match.range, in: value) else { continue }
			if cursor < tokenRange.lowerBound {
				result.append(String(value[cursor ..< tokenRange.lowerBound]))
			}
			let token = String(value[tokenRange])
			result.append(ChatFilterActionToken.allTokens.contains(token) ? ChatFilterActionToken(token: token) : token)
			cursor = tokenRange.upperBound
		}
		if cursor < value.endIndex {
			result.append(String(value[cursor...]))
		}
		return result.isEmpty ? [value] : result
	}

	func control(_: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
		guard commandSelector == #selector(NSResponder.insertNewline(_:)), textView.selectedRange().length == 0,
		      textView.textStorage?.editedRange.length ?? 0 <= 1
		else { return false }
		textView.insertNewlineIgnoringFieldEditor(self)
		return true
	}

	func controlTextDidChange(_: Notification) {
		toggleOkButton()
	}

	func validatedTextFieldTextDidChange(_: Any?) {
		toggleOkButton()
	}

	private func toggleOkButton() {
		let hasOutcome = filterIgnoreContentCheck.state == .on ||
			!filterForwardToDestinationTextField.stringValue.isEmpty || !filterActionTokenField.stringValue.isEmpty
		okButton?.isEnabled = !filterTitleTextField.stringValue.isEmpty && hasOutcome
	}

	private func setupTextFieldRules() {
		for field in [filterForwardToDestinationTextField, filterEventNumericTextField] {
			field?.textDidChangeCallback = self
			field?.performValidationWhenEmpty = false
			field?.stringValueIsInvalidOnEmpty = false
			field?.stringValueUsesOnlyFirstToken = false
		}
		filterForwardToDestinationTextField.stringValueIsTrimmed = true
		filterForwardToDestinationTextField.validationBlock = { [weak self] value in
			guard let self else { return nil }
			if value.count > 125 {
				return localized("m0u-tw")
			}
			let allowed = value.allSatisfy { $0.isLetter || $0.isNumber || "-_ ".contains($0) }
			return allowed ? nil : localized("5kd-jt")
		}
		filterEventNumericTextField.validationBlock = { [weak self] _ in
			guard let self else { return nil }
			return compileNumerics() == nil ? localized("9ri-sd") : nil
		}
	}

	private func updateUIState() {
		updateSenderMatchState()
		updateEventState()
		updateOperatorState()
		updateDestinationButtons()
		filterLimitedToHostView.isHidden = filter.filterLimitedToValue != ChatFilterDestination.specificItems.rawValue
	}

	private func updateEventState() {
		let enabled = filter.filterLimitedToValue != ChatFilterDestination.privateMessages.rawValue
		for button in eventButtons.dropFirst(3).map(\.0) {
			button.isEnabled = enabled
		}
	}

	private func updateOperatorState() {
		filterIgnoreOperatorsCheckEnabled = [filterEventPlainTextMessageCheck, filterEventActionMessageCheck,
		                                     filterEventNoticeMessageCheck].contains { $0?.state == .on }
		willChangeValue(forKey: "filterIgnoreOperatorsCheckValue")
		didChangeValue(forKey: "filterIgnoreOperatorsCheckValue")
	}

	private func updateSenderMatchState() {
		filterSenderMatchTextField.isEnabled = filterLimitedToMyselfCheck.state == .off
	}

	private func updateDestinationButtons() {
		let value = filter.filterLimitedToValue
		filterLimitToNoLimitButton.state = state(value == ChatFilterDestination.unrestricted.rawValue)
		filterLimitToOnlyChannelsButton.state = state(value == ChatFilterDestination.channels.rawValue)
		filterLimitToOnlyPrivateMessagesButton.state = state(value == ChatFilterDestination.privateMessages.rawValue)
		filterLimitToSpecificItemsButton.state = state(value == ChatFilterDestination.specificItems.rawValue)
	}

	@IBAction func filterLimitedToMyselfChanged(_: Any?) {
		updateSenderMatchState()
	}

	@IBAction func filterEventTypeChanged(_: Any?) {
		updateOperatorState()
	}

	@IBAction func filterLimitedToMatrixChanged(_ sender: Any?) {
		filter.filterLimitedToValue = UInt((sender as? NSControl)?.tag ?? 0)
		updateUIState()
	}

	@IBAction func filterIgnoreContentCheckChanged(_: Any?) {
		toggleOkButton()
	}

	private func state(_ value: Bool) -> NSControl.StateValue {
		value ? .on : .off
	}

	private func localized(_ key: String) -> String {
		Bundle(for: Self.self).localizedString(forKey: key, value: key, table: "TPI_ChatFilterEditFilterSheet")
	}
}

@objc(TPI_ChatFilterFilterActionToken)
private final class ChatFilterActionToken: NSObject {
	let token: String
	init(token: String) {
		self.token = token
	}

	convenience init?(title: String) {
		guard let index = Self.titles.firstIndex(of: title) else { return nil }
		self.init(token: Self.allTokens[index])
	}

	var title: String? {
		guard let index = Self.allTokens.firstIndex(of: token) else { return nil }
		return Self.titles[index]
	}

	override var description: String {
		token
	}

	static let allTokens = [
		"%_channelName_%", "%_localNickname_%", "%_networkName_%", "%_originalMessage_%",
		"%_senderNickname_%", "%_senderUsername_%", "%_senderAddress_%", "%_senderHostmask_%",
		"%_serverAddress_%", "%_Parameter_0_%", "%_Parameter_1_%", "%_Parameter_2_%",
		"%_Parameter_3_%", "%_Parameter_4_%", "%_Parameter_5_%", "%_Parameter_6_%",
		"%_Parameter_7_%", "%_Parameter_8_%",
	]

	static var titles: [String] {
		let keys = ["90e-tj", "tbc-wc", "840-f9", "sch-hi", "k82-6i", "2sk-ui", "xt2-bv", "je5-u2",
		            "9xy-vf", "kph-dc", "8bd-nt", "4vk-v8", "kvz-ej", "2pa-ju", "jen-7o", "t5v-4o", "vyf-el", "0x4-ib"]
		let bundle = Bundle(for: ChatFilterEditSheet.self)
		return keys.map { bundle.localizedString(forKey: $0, value: $0, table: "TPI_ChatFilterEditFilterSheet") }
	}
}
