/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import AppKit

@MainActor
protocol NicknameCompletionWindow: AnyObject {
	var inputTextField: MainWindowTextView! { get }
	var selectedClient: IRCClient? { get }
	var selectedChannel: IRCChannel? { get }
}

extension MainWindow: NicknameCompletionWindow {}

private enum CompletionKind: Sendable {
	case nickname
	case channelName
	case command
}

private struct CompletionRequest {
	let kind: CompletionKind
	let searchPattern: String
	let prefix: String
	let isAtStart: Bool
	let searchRange: NSRange
	var suffixRange: NSRange
	let originalSuffix: String

	init?(textValue: String, selection: NSRange) {
		guard selection.location != NSNotFound else {
			return nil
		}

		let text = textValue as NSString
		var searchStart = 0

		if selection.location > 0 {
			for index in stride(from: selection.location - 1, through: 0, by: -1) {
				let character = text.character(at: index)

				if Self.isWordDelimiter(character) {
					searchStart = index + 1
					break
				}
			}
		}

		let range = NSRange(location: searchStart, length: selection.location - searchStart)
		var pattern = text.substring(with: range)
		let atStart = searchStart == 0
		let resolvedKind: CompletionKind
		let resolvedPrefix: String

		if atStart, pattern.hasPrefix("/") {
			resolvedKind = .command
			resolvedPrefix = "/"
			pattern.removeFirst()
		} else if pattern.hasPrefix("@") {
			resolvedKind = .nickname
			resolvedPrefix = "@"
			pattern.removeFirst()
		} else if pattern.hasPrefix("#") {
			resolvedKind = .channelName
			resolvedPrefix = ""
		} else {
			resolvedKind = .nickname
			resolvedPrefix = ""
		}

		let completionSuffixRange = Self.completionSuffixRange(
			in: text,
			selection: selection,
			kind: resolvedKind
		)

		kind = resolvedKind
		searchPattern = pattern
		prefix = resolvedPrefix
		isAtStart = atStart
		searchRange = range
		suffixRange = completionSuffixRange
		originalSuffix = completionSuffixRange.length == 0 ? "" : text.substring(with: completionSuffixRange)
	}

	private static func completionSuffixRange(
		in text: NSString,
		selection: NSRange,
		kind: CompletionKind
	) -> NSRange {
		guard selection.length == 0 else {
			return selection
		}

		let start = selection.location
		var range = NSRange(location: start, length: 0)

		if kind == .nickname,
		   let preferredSuffix = Preferences.Input.tabCompletionSuffix.storedValue,
		   preferredSuffix.isEmpty == false
		{
			let searchRange = NSRange(location: start, length: text.length - start)
			let suffixRange = text.range(of: preferredSuffix, options: [], range: searchRange)

			if suffixRange.location != NSNotFound, suffixRange.length < 30 {
				let beforeSuffix = NSRange(location: start, length: suffixRange.location - start)
				let whitespace = text.rangeOfCharacter(from: .whitespaces, options: [], range: beforeSuffix)

				if whitespace.location == NSNotFound {
					range.length = NSMaxRange(suffixRange) - start
				}
			}
		}

		if range.length == 0,
		   Preferences.Input.tabCompletionCutForward.value,
		   start < text.length
		{
			for index in start ..< text.length where isSuffixDelimiter(text.character(at: index)) {
				range.length = index - start
				return range
			}

			range.length = text.length - start
		}

		return range
	}

	private static func isWordDelimiter(_ character: UniChar) -> Bool {
		(CharacterSet.whitespaces as NSCharacterSet).characterIsMember(character) || character == 0x2C
	}

	private static func isSuffixDelimiter(_ character: UniChar) -> Bool {
		isWordDelimiter(character) || character == 0x3A
	}
}

private struct CompletionSession {
	var request: CompletionRequest
	var currentText: String
	var selectionAfterCompletion: NSRange?
	var selectedCandidateIndex: Int?

	func canContinue(text: String, selection: NSRange) -> Bool {
		selectedCandidateIndex != nil &&
			selectionAfterCompletion == selection &&
			currentText.isEmpty == false &&
			currentText == text
	}

	mutating func selectCandidate(count: Int, movingForward: Bool) -> Int {
		let selectedIndex: Int = if let previous = selectedCandidateIndex, previous < count {
			if movingForward {
				(previous + 1) % count
			} else {
				previous == 0 ? count - 1 : previous - 1
			}
		} else {
			0
		}

		selectedCandidateIndex = selectedIndex
		return selectedIndex
	}
}

@MainActor
public final class NicknameCompletionStatus: NSObject {
	private struct Candidate {
		let displayValue: String
		let comparisonValue: String
	}

	private weak var window: (any NicknameCompletionWindow)?
	private var session: CompletionSession?

	@available(*, unavailable)
	override public convenience init() {
		fatalError("Use init(window:)")
	}

	public init(window: MainWindow) {
		self.window = window

		super.init()

		clear()
	}

	init(window: any NicknameCompletionWindow) {
		self.window = window

		super.init()

		clear()
	}

	public func completeNickname(_ movingForward: Bool) {
		guard let textView = window?.inputTextField as? TextViewWithIRCFormatter else {
			return
		}

		textView.window?.makeFirstResponder(textView)

		let selection = textView.selectedRange()
		let text = textView.string

		if session?.canContinue(text: text, selection: selection) != true {
			guard let request = CompletionRequest(textValue: text, selection: selection) else {
				clear()
				return
			}

			session = CompletionSession(request: request, currentText: text)
		}

		guard var session,
		      let completedValue = completedValue(for: &session, movingForward: movingForward)
		else {
			return
		}

		NSSpellChecker.shared.ignoreWord(completedValue, inSpellDocumentWithTag: textView.spellCheckerDocumentTag)
		apply(completedValue, in: textView, session: &session)
		self.session = session
	}

	public func clear() {
		session = nil
	}

	private func completedValue(for session: inout CompletionSession, movingForward: Bool) -> String? {
		let request = session.request
		let searchPatternIsEmpty = request.searchPattern.isEmpty

		guard searchPatternIsEmpty == false || request.kind == .nickname else {
			return nil
		}

		var candidates = completionCandidates(for: request)

		if request.kind == .channelName || request.kind == .command {
			candidates = candidates.map {
				Candidate(displayValue: $0.displayValue, comparisonValue: $0.displayValue.lowercased())
			}
		}
		if !searchPatternIsEmpty {
			let searchPattern = request.searchPattern.lowercased()
			candidates = candidates.filter { $0.comparisonValue.hasPrefix(searchPattern) }
		}

		guard !candidates.isEmpty else {
			return nil
		}

		let index = session.selectCandidate(count: candidates.count, movingForward: movingForward)
		return request.prefix + candidates[index].displayValue
	}

	private func completionCandidates(for request: CompletionRequest) -> [Candidate] {
		if request.kind == .command {
			var commands = CommandIndex.localCommandList().map { $0.lowercased() }
			let pluginManager = SharedApplication.sharedPluginManager()

			commands.append(contentsOf: pluginManager.supportedUserInputCommands)
			commands.append(contentsOf: pluginManager.supportedAppleScriptCommands)
			commands.sort { $0.localizedCompare($1) == .orderedAscending }

			return commands.map { Candidate(displayValue: $0, comparisonValue: $0) }
		}

		guard let client = window?.selectedClient else {
			return []
		}

		if request.kind == .channelName {
			let selectedChannel = window?.selectedChannel
			var names: [String] = []

			if let selectedChannel {
				names.append(selectedChannel.name)
			}

			for channel in client.channelList where channel !== selectedChannel {
				names.append(channel.name)
			}

			return names.map { Candidate(displayValue: $0, comparisonValue: $0) }
		}

		guard request.kind == .nickname, let channel = window?.selectedChannel else {
			return []
		}

		/* Decay once, here: doing it inside the comparator mutated the values the
		 sort was ordering by. A member is a value, so the decay is written back
		 through the channel rather than seen through a shared reference. */
		channel.decayMemberConversations()

		return nicknameCandidates(
			from: channel.channelMembers,
			client: client,
			searchPatternIsEmpty: request.searchPattern.isEmpty
		)
	}

	/// The member whose conversation weight is strictly greater than at least
	/// one other member's, if any.
	///
	/// `nil` when every member carries the same weight: there is then no
	/// "most highly weighted" user and the alphabetical order stands alone.
	/// Weights are read once each because reading one decays it.
	private func mostWeightedMember(of members: [ChannelUser]) -> ChannelUser? {
		let weighted = members.map { (member: $0, weight: $0.totalWeight) }

		guard let heaviest = weighted.reduce(nil, { best, next -> (member: ChannelUser, weight: Double)? in
			guard let best else {
				return next
			}

			return next.weight > best.weight ? next : best
		}) else {
			return nil
		}

		guard weighted.contains(where: { $0.weight < heaviest.weight }) else {
			return nil
		}

		return heaviest.member
	}

	private func nicknameCandidates(
		from members: [ChannelUser],
		client: IRCClient,
		searchPatternIsEmpty: Bool
	) -> [Candidate] {
		let sortedMembers: [ChannelUser]
		let priorityMember: ChannelUser?

		if searchPatternIsEmpty {
			/* With no search pattern the list reads alphabetically and only
			 the single most highly weighted user is lifted to the top — and
			 only when one user genuinely outweighs the others. */
			sortedMembers = members.sorted { left, right in
				left.user.nickname.caseInsensitiveCompare(right.user.nickname) == .orderedAscending
			}
			priorityMember = mostWeightedMember(of: members)
		} else {
			/* With a search pattern the whole list is already ordered by
			 conversation weight, so there is no separate priority candidate. */
			sortedMembers = members.sorted { $0.compare(usingWeights: $1) == .orderedAscending }
			priorityMember = nil
		}

		var candidates: [Candidate] = []
		let trimmedCharacters = CharacterSet(charactersIn: "^[]-_`{}\\")
		let includeTrimmedNicknames = !searchPatternIsEmpty

		func addNickname(_ nickname: String, includeTrimmedVariant: Bool) {
			candidates.append(Candidate(displayValue: nickname, comparisonValue: nickname.lowercased()))

			guard includeTrimmedVariant,
			      let trimmedNickname = trimNickname(nickname, using: trimmedCharacters),
			      !trimmedNickname.isEmpty,
			      nickname != trimmedNickname
			else {
				return
			}

			let comparisonValue = trimmedNickname.lowercased()

			if !candidates.contains(where: { $0.comparisonValue == comparisonValue }) {
				candidates.append(Candidate(displayValue: nickname, comparisonValue: comparisonValue))
			}
		}

		if let priorityMember {
			addNickname(priorityMember.user.nickname, includeTrimmedVariant: includeTrimmedNicknames)
		}

		for member in sortedMembers where member.id != priorityMember?.id {
			addNickname(member.user.nickname, includeTrimmedVariant: includeTrimmedNicknames)
		}

		for nickname in ["NickServ", "RootServ", "OperServ", "HostServ", "ChanServ", "MemoServ"] {
			addNickname(nickname, includeTrimmedVariant: false)
		}

		addNickname(ApplicationInfo.applicationNameWithoutVersion(), includeTrimmedVariant: false)

		if let networkName = client.supportInfo.networkName {
			addNickname(networkName, includeTrimmedVariant: false)
		}

		return candidates
	}

	private func completionSuffix(for session: CompletionSession) -> String? {
		let request = session.request
		let whitespace = CharacterSet.whitespaces
		var newCompletionSuffix: String?
		var whitespaceAlreadyInPosition = request.originalSuffix.unicodeScalars.last.map(whitespace.contains) ?? false
		let whitespaceContainedByCachedSuffix = whitespaceAlreadyInPosition

		if !whitespaceAlreadyInPosition {
			let text = session.currentText as NSString
			// text.length, not length - 1: the last character index is a valid
			// place for whitespace to already be, and excluding it appended a
			// second space at the end of the line.
			let maximumCompletionSuffixEndPoint = text.length
			let nextCharacterInRange = NSMaxRange(request.suffixRange)

			if nextCharacterInRange < maximumCompletionSuffixEndPoint,
			   (whitespace as NSCharacterSet).characterIsMember(text.character(at: nextCharacterInRange))
			{
				whitespaceAlreadyInPosition = true
			}
		}

		if request.kind == .nickname, request.isAtStart {
			let userCompletionSuffix = Preferences.Input.tabCompletionSuffix.storedValue ?? ""

			if whitespaceAlreadyInPosition {
				if userCompletionSuffix.unicodeScalars.last.map(whitespace.contains) == true {
					if !whitespaceContainedByCachedSuffix, userCompletionSuffix.utf16.count > 1 {
						newCompletionSuffix = String(userCompletionSuffix.dropLast())
					} else if whitespaceContainedByCachedSuffix {
						newCompletionSuffix = userCompletionSuffix
					}
				} else {
					newCompletionSuffix = userCompletionSuffix
				}
			} else if userCompletionSuffix.isEmpty {
				if !Preferences.Input.tabCompletionNoWhitespace.value {
					newCompletionSuffix = " "
				}
			} else {
				newCompletionSuffix = userCompletionSuffix
			}
		} else if !whitespaceAlreadyInPosition {
			newCompletionSuffix = " "
		}

		return newCompletionSuffix
	}

	private func apply(
		_ completedValue: String,
		in textView: TextViewWithIRCFormatter,
		session: inout CompletionSession
	) {
		let request = session.request
		var replacementRange = NSRange(
			location: request.searchRange.location,
			length: request.searchRange.length + request.suffixRange.length
		)
		let replacementValue = completedValue + (completionSuffix(for: session) ?? "")

		if textView.shouldChangeText(in: replacementRange, replacementString: replacementValue) {
			textView.replaceCharacters(in: replacementRange, with: replacementValue)
			textView.didChangeText()
		}

		replacementRange.length = replacementValue.utf16.count

		let newSelectionRange = NSRange(location: NSMaxRange(replacementRange), length: 0)
		textView.scrollRangeToVisible(newSelectionRange)
		textView.setSelectedRange(newSelectionRange)
		session.selectionAfterCompletion = newSelectionRange
		session.request.suffixRange = NSRange(
			location: NSMaxRange(request.searchRange),
			length: replacementRange.length - request.searchRange.length
		)
		session.currentText = textView.string
	}

	private func trimNickname(_ nickname: String, using characterSet: CharacterSet) -> String? {
		let text = nickname as NSString

		for index in 0 ..< text.length
			where !(characterSet as NSCharacterSet).characterIsMember(text.character(at: index))
		{
			return text.substring(from: index)
		}

		return nil
	}
}
