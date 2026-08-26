/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\\_\\__|\\__,_|\\__,_|_|
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

@objc(TLONicknameCompletionStatus)
@MainActor
public final class NicknameCompletionStatus: NSObject {
	private struct Candidate {
		let displayValue: String
		let comparisonValue: String
	}

	private weak var window: (any NicknameCompletionWindow)?
	private var completedValue: String?
	private var completedValueCompletionSuffix: String?
	private var currentTextViewStringValue: String?
	private var cachedSearchPattern: String?
	private var cachedSearchPatternPrefixCharacter: String?
	private var cachedCompletionSuffix: String?
	private var selectionRangeAfterLastCompletion = NSRange(location: NSNotFound, length: 0)
	private var rangeOfTextSelection = NSRange(location: NSNotFound, length: 0)
	private var rangeOfSearchPattern = NSRange(location: 0, length: 0)
	private var rangeOfCompletionSuffix = NSRange(location: 0, length: 0)
	private var selectionIndexOfLastCompletion = NSNotFound
	private var completionIsMovingForward = false
	private var isCompletingChannelName = false
	private var isCompletingCommand = false
	private var isCompletingNickname = false
	private var searchPatternIsAtStart = false
	private var searchPatternIsAtEnd = false
	private var completionCacheIsConstructed = false

	@available(*, unavailable)
	override public convenience init() {
		fatalError("Use init(window:)")
	}

	@objc(initWithWindow:)
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

	@objc(completeNickname:)
	public func completeNickname(_ movingForward: Bool) {
		performCompletion(movingForward: movingForward)
	}

	@objc public func clear() {
		clearCache()

		currentTextViewStringValue = nil
		rangeOfTextSelection = NSRange(location: NSNotFound, length: 0)
		selectionRangeAfterLastCompletion = NSRange(location: NSNotFound, length: 0)
		completionIsMovingForward = false
	}

	private func performCompletion(movingForward: Bool) {
		guard let textView = window?.inputTextField as? TextViewWithIRCFormatter else {
			return
		}

		textView.window?.makeFirstResponder(textView)

		let selectedRange = textView.selectedRange()

		guard selectedRange.location != NSNotFound else {
			return
		}

		var canContinuePreviousScan = true

		if selectionIndexOfLastCompletion == NSNotFound || selectionRangeAfterLastCompletion.location == NSNotFound
			|| (rangeOfTextSelection.location == NSNotFound && rangeOfSearchPattern.location == 0
				&& rangeOfSearchPattern.length == 0)
			|| selectedRange != selectionRangeAfterLastCompletion
		{
			canContinuePreviousScan = false
		}

		let textValue = textView.string

		if currentTextViewStringValue?.isEmpty != false || currentTextViewStringValue != textValue {
			canContinuePreviousScan = false
		}

		currentTextViewStringValue = textValue
		completionIsMovingForward = movingForward

		if !canContinuePreviousScan {
			rangeOfTextSelection = selectedRange
			constructCache()
		}

		guard completionCacheIsConstructed, performCompletionStepOne() else {
			return
		}

		performCompletionStepTwo()
		performCompletionStepThree()
		performCompletionStepFour()
	}

	private func performCompletionStepOne() -> Bool {
		let searchPatternIsEmpty = cachedSearchPattern?.isEmpty != false

		guard !searchPatternIsEmpty || isCompletingNickname else {
			return false
		}

		var candidates = completionCandidates(searchPatternIsEmpty: searchPatternIsEmpty)

		if isCompletingChannelName || isCompletingCommand {
			candidates = candidates.map {
				Candidate(displayValue: $0.displayValue, comparisonValue: $0.displayValue.lowercased())
			}
		}

		if !searchPatternIsEmpty {
			let searchPattern = cachedSearchPattern?.lowercased() ?? ""
			candidates = candidates.filter { $0.comparisonValue.hasPrefix(searchPattern) }
		}

		guard !candidates.isEmpty else {
			return false
		}

		let selectedIndex: Int = if selectionIndexOfLastCompletion == NSNotFound || selectionIndexOfLastCompletion >=
			candidates.count
		{
			0
		} else if completionIsMovingForward {
			(selectionIndexOfLastCompletion + 1) % candidates.count
		} else if selectionIndexOfLastCompletion == 0 {
			candidates.count - 1
		} else {
			selectionIndexOfLastCompletion - 1
		}

		selectionIndexOfLastCompletion = selectedIndex
		completedValue = (cachedSearchPatternPrefixCharacter ?? "") + candidates[selectedIndex].displayValue

		return true
	}

	private func completionCandidates(searchPatternIsEmpty: Bool) -> [Candidate] {
		if isCompletingCommand {
			var commands = IRCCommandIndex.localCommandList().map { $0.lowercased() }
			let pluginManager = TXSharedApplication.sharedPluginManager()

			commands.append(contentsOf: pluginManager.supportedUserInputCommands)
			commands.append(contentsOf: pluginManager.supportedAppleScriptCommands)
			commands.sort { $0.localizedCompare($1) == .orderedAscending }

			return commands.map { Candidate(displayValue: $0, comparisonValue: $0) }
		}

		guard let client = window?.selectedClient else {
			return []
		}

		if isCompletingChannelName {
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

		guard isCompletingNickname, let channel = window?.selectedChannel else {
			return []
		}

		let members = (channel.memberList ?? []).compactMap { member in
			(member as AnyObject) as? ChannelUser
		}

		return nicknameCandidates(
			from: members,
			client: client,
			searchPatternIsEmpty: searchPatternIsEmpty
		)
	}

	private func nicknameCandidates(
		from members: [ChannelUser],
		client: IRCClient,
		searchPatternIsEmpty: Bool
	) -> [Candidate] {
		var greatestWeightUser: ChannelUser?
		var noUserHadGreaterWeightThanOriginal = true
		let sortedMembers: [ChannelUser]

		if !searchPatternIsEmpty {
			sortedMembers = members.sorted { $0.compare(usingWeights: $1) == .orderedAscending }
			greatestWeightUser = sortedMembers.first
		} else {
			greatestWeightUser = members.first

			for member in members.dropFirst() {
				if let currentGreatest = greatestWeightUser, currentGreatest.totalWeight < member.totalWeight {
					greatestWeightUser = member
					noUserHadGreaterWeightThanOriginal = false
				}
			}

			sortedMembers = members.sorted { (left: ChannelUser, right: ChannelUser) -> Bool in
				left.user.nickname.caseInsensitiveCompare(right.user.nickname) == .orderedAscending
			}
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

		if !noUserHadGreaterWeightThanOriginal, let greatestWeightUser {
			addNickname(greatestWeightUser.user.nickname, includeTrimmedVariant: includeTrimmedNicknames)
		}

		for member in sortedMembers where noUserHadGreaterWeightThanOriginal || member !== greatestWeightUser {
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

	private func performCompletionStepTwo() {
		guard let completedValue, let textView = window?.inputTextField as? TextViewWithIRCFormatter else {
			return
		}

		NSSpellChecker.shared.ignoreWord(completedValue, inSpellDocumentWithTag: textView.spellCheckerDocumentTag)
	}

	private func performCompletionStepThree() {
		let whitespace = CharacterSet.whitespaces
		var newCompletionSuffix: String?
		var whitespaceAlreadyInPosition = cachedCompletionSuffix?.unicodeScalars.last.map(whitespace.contains) ?? false
		let whitespaceContainedByCachedSuffix = whitespaceAlreadyInPosition

		if !whitespaceAlreadyInPosition,
		   let currentTextViewStringValue
		{
			let text = currentTextViewStringValue as NSString
			let maximumCompletionSuffixEndPoint = text.length - 1
			let nextCharacterInRange = NSMaxRange(rangeOfCompletionSuffix)

			if nextCharacterInRange < maximumCompletionSuffixEndPoint,
			   (whitespace as NSCharacterSet).characterIsMember(text.character(at: nextCharacterInRange))
			{
				whitespaceAlreadyInPosition = true
			}
		}

		if isCompletingNickname, searchPatternIsAtStart {
			let userCompletionSuffix = TPCPreferences.tabCompletionSuffix() ?? ""

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
				if !TPCPreferences.tabCompletionDoNotAppendWhitespace() {
					newCompletionSuffix = " "
				}
			} else {
				newCompletionSuffix = userCompletionSuffix
			}
		} else if !whitespaceAlreadyInPosition {
			newCompletionSuffix = " "
		}

		completedValueCompletionSuffix = newCompletionSuffix
	}

	private func performCompletionStepFour() {
		guard let completedValue,
		      let textView = window?.inputTextField as? TextViewWithIRCFormatter
		else {
			return
		}

		var replacementRange = NSRange(
			location: rangeOfSearchPattern.location,
			length: rangeOfSearchPattern.length + rangeOfCompletionSuffix.length
		)
		let replacementValue = completedValue + (completedValueCompletionSuffix ?? "")

		if textView.shouldChangeText(in: replacementRange, replacementString: replacementValue) {
			textView.replaceCharacters(in: replacementRange, with: replacementValue)
			textView.didChangeText()
		}

		replacementRange.length = replacementValue.utf16.count

		let newSelectionRange = NSRange(location: NSMaxRange(replacementRange), length: 0)
		textView.scrollRangeToVisible(newSelectionRange)
		textView.setSelectedRange(newSelectionRange)
		selectionRangeAfterLastCompletion = newSelectionRange
		rangeOfCompletionSuffix = NSRange(
			location: NSMaxRange(rangeOfSearchPattern),
			length: replacementRange.length - rangeOfSearchPattern.length
		)

		currentTextViewStringValue = textView.string
		self.completedValue = nil
		completedValueCompletionSuffix = nil
	}

	private func constructCache() {
		clearCache()

		guard constructCachedSearchPattern(),
		      constructCachedSearchPatternPrefixCharacter(),
		      constructCachedCompletionSuffix()
		else {
			return
		}

		completionCacheIsConstructed = true
	}

	private func constructCachedSearchPattern() -> Bool {
		guard let currentTextViewStringValue else {
			return false
		}

		let text = currentTextViewStringValue as NSString
		var searchPatternStartingPoint = 0

		if rangeOfTextSelection.location > 0 {
			for index in stride(from: rangeOfTextSelection.location - 1, through: 0, by: -1) {
				let character = text.character(at: index)

				if (CharacterSet.whitespaces as NSCharacterSet).characterIsMember(character) || character == 0x2C {
					searchPatternStartingPoint = index + 1
					break
				}
			}
		}

		let searchPatternLength = rangeOfTextSelection.location - searchPatternStartingPoint
		rangeOfSearchPattern = NSRange(location: searchPatternStartingPoint, length: searchPatternLength)
		cachedSearchPattern = searchPatternLength == 0 ? "" : text.substring(with: rangeOfSearchPattern)
		searchPatternIsAtStart = searchPatternStartingPoint == 0

		return true
	}

	private func constructCachedSearchPatternPrefixCharacter() -> Bool {
		guard var searchPattern = cachedSearchPattern else {
			return false
		}

		let firstCharacter = (searchPattern as NSString).length > 0 ? (searchPattern as NSString).character(at: 0) : 0

		if searchPatternIsAtStart, firstCharacter == 0x2F {
			isCompletingCommand = true
			searchPattern = (searchPattern as NSString).substring(from: 1)
			cachedSearchPatternPrefixCharacter = "/"
		} else if firstCharacter == 0x40 {
			isCompletingNickname = true
			searchPattern = (searchPattern as NSString).substring(from: 1)
			cachedSearchPatternPrefixCharacter = "@"
		} else if firstCharacter == 0x23 {
			isCompletingChannelName = true
		} else {
			isCompletingNickname = true
		}

		cachedSearchPattern = searchPattern

		return true
	}

	private func constructCachedCompletionSuffix() -> Bool {
		guard let currentTextViewStringValue else {
			return false
		}

		let text = currentTextViewStringValue as NSString
		let totalTextLength = text.length
		let selectedRangeStartPoint = rangeOfTextSelection.location
		var completionSuffixRange: NSRange

		if rangeOfTextSelection.length > 0 {
			completionSuffixRange = rangeOfTextSelection
		} else {
			completionSuffixRange = NSRange(location: selectedRangeStartPoint, length: 0)

			if isCompletingNickname,
			   let userCompletionSuffix = TPCPreferences.tabCompletionSuffix(),
			   !userCompletionSuffix.isEmpty
			{
				let completionSearchRange = NSRange(
					location: selectedRangeStartPoint,
					length: totalTextLength - selectedRangeStartPoint
				)
				let completionRange = text.range(of: userCompletionSuffix, options: [], range: completionSearchRange)

				if completionRange.location != NSNotFound, completionRange.length < 30 {
					let whitespaceSearchRange = NSRange(
						location: selectedRangeStartPoint,
						length: completionRange.location - selectedRangeStartPoint
					)
					let whitespaceRange = text.rangeOfCharacter(
						from: .whitespaces, options: [], range: whitespaceSearchRange
					)

					if whitespaceRange.location == NSNotFound {
						completionSuffixRange.length = NSMaxRange(completionRange) - selectedRangeStartPoint
					}
				}
			}

			if completionSuffixRange.length == 0,
			   TPCPreferences.tabCompletionCutForwardToFirstWhitespace(),
			   selectedRangeStartPoint < totalTextLength
			{
				var foundDelimiter = false

				for index in selectedRangeStartPoint ..< totalTextLength {
					let character = text.character(at: index)

					if (CharacterSet.whitespaces as NSCharacterSet).characterIsMember(character) || character == 0x3A
						|| character == 0x2C
					{
						completionSuffixRange.length = index - selectedRangeStartPoint
						foundDelimiter = true
						break
					}
				}

				if !foundDelimiter {
					completionSuffixRange.length = totalTextLength - selectedRangeStartPoint
				}
			}
		}

		rangeOfCompletionSuffix = completionSuffixRange
		cachedCompletionSuffix = completionSuffixRange.length == 0 ? "" : text.substring(with: completionSuffixRange)
		searchPatternIsAtEnd = NSMaxRange(completionSuffixRange) == totalTextLength

		return true
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

	private func clearCache() {
		completedValue = nil
		completedValueCompletionSuffix = nil
		cachedSearchPattern = nil
		cachedSearchPatternPrefixCharacter = nil
		selectionIndexOfLastCompletion = NSNotFound
		cachedCompletionSuffix = nil
		rangeOfCompletionSuffix = NSRange(location: 0, length: 0)
		rangeOfSearchPattern = NSRange(location: 0, length: 0)
		completionCacheIsConstructed = false
		isCompletingChannelName = false
		isCompletingCommand = false
		isCompletingNickname = false
		searchPatternIsAtEnd = false
		searchPatternIsAtStart = false
	}
}
