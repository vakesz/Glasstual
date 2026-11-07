// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit

@MainActor
protocol NicknameCompletionWindow: AnyObject {
	var inputTextField: InputField! { get }
	var selectedSession: ServerSession? { get }
	var selectedConversation: Conversation? { get }
}

extension MainWindow: NicknameCompletionWindow {}

@MainActor
final class NicknameCompletion {
	private struct Candidate {
		let displayValue: String
		let comparisonValue: String
	}

	private weak var window: (any NicknameCompletionWindow)?
	private var session: CompletionSession?

	init(window: any NicknameCompletionWindow) {
		self.window = window
	}

	func completeNickname(_ movingForward: Bool) {
		guard let textView = window?.inputTextField else {
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

	func clear() {
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
			var commands = CommandIndex.candidates(
				includingDeveloperCommands: SettingsKeys.Commands.developerMode.value,
				scriptCommands: AppServices.scripts.commandNames
			).map(\.name)
			commands.sort { $0.localizedCompare($1) == .orderedAscending }

			return commands.map { Candidate(displayValue: $0, comparisonValue: $0) }
		}

		guard let session = window?.selectedSession else {
			return []
		}

		if request.kind == .channelName {
			let selectedConversation = window?.selectedConversation
			var names: [String] = []

			if let selectedConversation {
				names.append(selectedConversation.name)
			}

			for channel in session.conversationList where channel !== selectedConversation {
				names.append(channel.name)
			}

			return names.map { Candidate(displayValue: $0, comparisonValue: $0) }
		}

		guard request.kind == .nickname, let channel = window?.selectedConversation else {
			return []
		}

		/* Decay once, here: doing it inside the comparator mutated the values the
		 sort was ordering by. A member is a value, so the decay is written back
		 through the channel rather than seen through a shared reference. */
		channel.decayMemberConversations()

		return nicknameCandidates(
			from: channel.memberList,
			session: session,
			searchPatternIsEmpty: request.searchPattern.isEmpty
		)
	}

	/// The member whose conversation weight is strictly greater than at least
	/// one other member's, if any.
	///
	/// `nil` when every member carries the same weight: there is then no
	/// "most highly weighted" user and the alphabetical order stands alone.
	/// Weights have already been decayed before candidate construction.
	private func mostWeightedMember(of members: [Member]) -> Member? {
		let weighted = members.map { (member: $0, weight: $0.totalWeight) }

		guard let heaviest = weighted.reduce(nil, { best, next -> (member: Member, weight: Double)? in
			guard let best else {
				return next
			}

			return next.weight > best.weight ? next : best
		}), weighted.contains(where: { $0.weight < heaviest.weight }) else {
			return nil
		}

		return heaviest.member
	}

	private func nicknameCandidates(
		from members: [Member],
		session: ServerSession,
		searchPatternIsEmpty: Bool
	) -> [Candidate] {
		let sortedMembers: [Member]
		let priorityMember: Member?

		if searchPatternIsEmpty {
			/* With no search pattern the list reads alphabetically and only
			 the single most highly weighted user is lifted to the top — and
			 only when one user genuinely outweighs the others. */
			sortedMembers = members.sorted { left, right in
				left.user.nickname.caseInsensitiveCompare(right.user.nickname) == .orderedAscending
			}
			priorityMember = mostWeightedMember(of: members)
		} else {
			/* With a search pattern the whole list is ordered by conversation
			 weight, so there is no separate priority candidate. The ordering is
			 the one the member list uses: `sortedByConversationWeight` reads the
			 staff setting once and hands it to the pure comparator, rather
			 than fetching it on every one of the n log n comparisons. */
			sortedMembers = Member.sortedByConversationWeight(
				members,
				favoringServerStaff: session.environment.settings.memberListSortFavorsServerStaff
			)
			priorityMember = nil
		}

		var candidates: [Candidate] = []
		var comparisonValues: Set<String> = []
		let trimmedCharacters = CharacterSet(charactersIn: "^[]-_`{}\\")
		let includeTrimmedNicknames = !searchPatternIsEmpty

		func addNickname(_ nickname: String, includeTrimmedVariant: Bool) {
			let comparisonValue = nickname.lowercased()
			candidates.append(Candidate(displayValue: nickname, comparisonValue: comparisonValue))
			comparisonValues.insert(comparisonValue)

			guard includeTrimmedVariant,
			      let trimmedNickname = trimNickname(nickname, using: trimmedCharacters),
			      !trimmedNickname.isEmpty,
			      nickname != trimmedNickname
			else {
				return
			}

			let trimmedComparisonValue = trimmedNickname.lowercased()

			if comparisonValues.insert(trimmedComparisonValue).inserted {
				candidates.append(Candidate(displayValue: nickname, comparisonValue: trimmedComparisonValue))
			}
		}

		if let priorityMember {
			addNickname(priorityMember.user.nickname, includeTrimmedVariant: includeTrimmedNicknames)
		}

		for member in sortedMembers where member.id != priorityMember?.id {
			addNickname(member.user.nickname, includeTrimmedVariant: includeTrimmedNicknames)
		}

		/* None of these is in the channel, so none of them belongs in the cycle
		 the reader walks by pressing Tab on an empty word: that offered
		 "NickServ" and the application's own name between two people who are
		 actually in the room. Once something has been typed they are worth
		 completing -- a service name and the network's name are both things one
		 addresses -- so they join the list only then. */
		guard searchPatternIsEmpty == false else {
			return candidates
		}

		for nickname in ["NickServ", "RootServ", "OperServ", "HostServ", "ChanServ", "MemoServ"] {
			addNickname(nickname, includeTrimmedVariant: false)
		}

		addNickname(ApplicationInfo.applicationName(), includeTrimmedVariant: false)

		if let networkName = session.supportInfo.networkName {
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
			let userCompletionSuffix = SettingsKeys.Input.tabCompletionSuffix.storedValue ?? ""

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
				if !SettingsKeys.Input.tabCompletionNoWhitespace.value {
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
		in textView: FormattedTextView,
		session: inout CompletionSession
	) {
		let request = session.request
		var replacementRange = NSRange(
			location: request.searchRange.location,
			length: request.searchRange.length + request.suffixRange.length
		)
		let replacementValue = completedValue + (completionSuffix(for: session) ?? "")

		/* The session records the text and selection the completion produced, so
		 a refused edit has to end the session rather than record an edit that
		 never happened: the next Tab would replace a range computed from it. */
		guard textView.shouldChangeText(in: replacementRange, replacementString: replacementValue) else {
			clear()
			return
		}

		textView.replaceCharacters(in: replacementRange, with: replacementValue)
		textView.didChangeText()

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
