// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
import os

extension Notification.Name {
	static let conversationConfigWasUpdated = Notification.Name(
		"Glasstual.conversationConfigWasUpdated"
	)
}

class Conversation: ChatItem {
	private static let logger = Logger(
		subsystem: LogSubsystem.current,
		category: "Conversation"
	)

	private static let terminationLogger = Logger(
		subsystem: LogSubsystem.current,
		category: "Termination"
	)

	private(set) var config: ConversationConfig

	var topic: String? {
		didSet {
			guard topic != oldValue else {
				return
			}

			presentation?.setTopic(topic)
		}
	}

	var status: ConversationStatus = .parted {
		didSet {
			guard status != oldValue else {
				return
			}
			if status != .joined {
				associatedSession?.typingSender.remove(in: self)
			}

			performActionOnStatusChange()
		}
	}

	var directChatConnection: DirectChatSession?
	var sentInitialWhoRequest = false
	var channelModesReceived = false
	var channelNamesReceived = false
	var errorOnLastJoinAttempt = false
	/** When the local user joined, on the server's clock where `server-time`
	 supplies one and on this Mac's otherwise. `nil` until the channel is joined.

	 A bouncer or a server replays the tail of a conversation right after the
	 JOIN, so this is the reference point `JoinBurstPolicy` measures that
	 burst against. */
	private(set) var joinedAt: Date?
	private(set) var modeInfo: ChannelModeState?
	private(set) var memberInfo: ConversationMembers?

	private var statusChangedByAction = false

	@available(*, unavailable)
	override init() {
		fatalError("Use init(config:)")
	}

	init(config: ConversationConfig) {
		self.config = config

		super.init()

		persistSecretKey()
	}

	func updateConfig(_ config: ConversationConfig) {
		updateConfig(config, fireChangedNotification: true, updateStoredConversationList: true)
	}

	func updateConfig(
		_ config: ConversationConfig,
		fireChangedNotification: Bool,
		updateStoredConversationList: Bool
	) {
		if config == self.config {
			return
		}

		/* A direct conversation, a console view and a direct chat are named after
		 their peer, so a rename is an ordinary configuration change for them and
		 goes through here like any other. A #channel's name is the server's: a
		 configuration under a different one belongs to a different channel. */
		guard self.config.type == config.type,
		      self.config.uniqueIdentifier == config.uniqueIdentifier,
		      isChannel == false || self.config.name == config.name
		else {
			Self.logger.error("Tried to load configuration for incorrect conversation")
			return
		}

		if self.config.name != config.name {
			associatedSession?.typingSender.remove(in: self)
		}
		self.config = config
		persistSecretKey()

		if updateStoredConversationList {
			associatedSession?.updateStoredConversationList()
		}

		if fireChangedNotification {
			NotificationCenter.default.post(
				name: .conversationConfigWasUpdated,
				object: self
			)
		}
	}

	var configurationDictionary: [String: PropertyListValue] {
		PropertyListModel.encode(config)
	}

	override var uniqueIdentifier: String {
		config.uniqueIdentifier
	}

	override var name: String {
		get { config.name }
		set {
			// A #channel cannot be renamed locally, and `updateConfig` would
			// refuse the attempt loudly where this has always been a no-op.
			guard isChannel == false else { return }

			var renamed = config
			renamed.name = newValue
			updateConfig(renamed)
		}
	}

	/** The key to JOIN with: an edit the user has not committed yet, and
	 otherwise whatever the session resolved for this channel.

	 The session holds every secret it has read, so the channel does not keep a
	 second copy of its own; ``ServerSession/resolveSecretKey(for:)`` is what puts one
	 there for a channel that arrives after the connection opened. */
	var secretKey: String? {
		config.pendingSecretKey.value(orStored: associatedSession?.sessionCredentials.password(for: config.keychainItem))
	}

	/// Writes an uncommitted key edit to the keychain, and tells the session
	/// about it once the write has been acknowledged.
	private func persistSecretKey() {
		let edits = config.pendingKeychainEdits
		guard edits.isEmpty == false else { return }

		KeychainPersistence.shared.persist(edits) { [weak self] committed in
			guard let self else { return }
			let acknowledged = committed.filter { config.pendingKeychainEdits[$0.key] == $0.value }
			associatedSession?.sessionCredentials.apply(acknowledged)
			config.acknowledgeKeychainEdits(acknowledged)
		}
	}

	var autoJoin: Bool {
		get { config.autoJoin }
		set {
			guard isChannel, newValue != config.autoJoin else {
				return
			}

			config.autoJoin = newValue
		}
	}

	override var isChannel: Bool {
		config.type == .channel
	}

	override var isDirect: Bool {
		config.type == .direct
	}

	var isConsole: Bool {
		config.type == .console
	}

	var isDirectChat: Bool {
		config.type == .directChat
	}

	var isDirectForZNCUser: Bool {
		isDirect && associatedSession?.nicknameIsZNCUser(name) == true
	}

	var type: ConversationKind {
		config.type
	}

	var logFilePath: URL? {
		guard let writePath = TranscriptPath.write(for: self) else {
			return nil
		}

		return URL(fileURLWithPath: writePath)
	}

	var lastLine: ChatLine? {
		presentation?.lastPrintedLine()
	}

	func settingsChanged(_ action: SettingsReloadAction) {
		if action.contains(.settingsChanged),
		   chatSettings.displayPublicMessageCountOnDockBadge == false, isChannel
		{
			dockUnreadCount = 0
		}

		if action.contains(.memberListSortOrder) {
			memberInfo?.sortMembers()
		}

		if action.contains(.logTranscripts) {
			reopenLogFileIfNeeded()
		}

		if action.contains(.scrollbackVisibleLimit) {
			transcriptController?.changeScrollbackLimit()
		}
	}

	private func performActionOnStatusChange() {
		if statusChangedByAction {
			statusChangedByAction = false
			return
		}

		switch status {
		case .joined:
			activate()
		case .parted:
			deactivate()
		default:
			break
		}
	}

	func resetStatus(_ newStatus: ConversationStatus) {
		guard newStatus != .joining else {
			return
		}

		channelModesReceived = false
		channelNamesReceived = false
		errorOnLastJoinAttempt = false
		sentInitialWhoRequest = false
		joinedAt = nil
		modeInfo = nil
		status = newStatus
		statusChangedByAction = false
		topic = nil
		clearMembers()
		memberInfo = nil
	}

	/** Marks the conversation joined.

	 `date` is when the join happened rather than when this runs, so a JOIN
	 carrying `server-time` records the server's clock. */
	func activate(at date: Date = Date()) {
		statusChangedByAction = true
		resetStatus(.joined)
		/* Recorded before anything that can leave early: the conversation is open
		 whether or not it has a session to talk to, and noteConversationActivated
		 below already asks the server what has been read in it. */
		joinedAt = date

		guard let session = associatedSession else {
			return
		}

		if isConsole == false {
			memberInfo = ConversationMembers(conversation: self)

			if isSelectedConversation, let output = associatedSession?.output {
				output.assignMemberList(to: self)
				output.updateMemberListVisibilityForSelection()
			}
		}

		if isChannel {
			modeInfo = ChannelModeState(channel: self)
		}

		if isDirect || isDirectChat {
			let peerNickname: String = if isDirectChat {
				directChatConnection?.peerNickname ?? String(name.dropFirst())
			} else {
				name
			}

			addUser(session.findUserOrCreate(peerNickname))
			addUser(session.findUserOrCreate(session.userNickname))
		}

		if isChannel || isDirect {
			session.noteConversationActivated(self)
		}
	}

	func deactivate() {
		statusChangedByAction = true
		resetStatus(.parted)
	}

	/** Takes the conversation out of use.

	 The two ways a conversation ends — the user removed it, or the application
	 is quitting — differ only in what becomes of the stored key and of the local
	 data. What happens to the conversation itself is one path, so that a change
	 to it cannot apply to only one of them. */
	@MainActor
	private func tearDown(as reason: ChatItemTeardown, destroysSecretKey: Bool) {
		statusChangedByAction = true
		resetStatus(.terminated)
		closeDirectChatConnection()
		closeLogFile()

		if destroysSecretKey {
			KeychainPersistence.shared.persist([config.keychainItem: .cleared])
		}

		presentation?.tearDown(reason)
	}

	@MainActor func prepareForRemoval(preservingLocalData: Bool) {
		associatedSession?.output?.closeSheets(forConversationId: uniqueIdentifier)
		if !preservingLocalData {
			associatedSession?.output?.destroyInputHistory(for: self)
		}

		tearDown(
			as: preservingLocalData ? .preservingRemoval : .permanentRemoval,
			destroysSecretKey: !preservingLocalData
		)
	}

	@MainActor
	func prepareForApplicationTermination() {
		let conversationIdentifier = uniqueIdentifier
		let viewIdentifier = presentation?.presentationIdentifier ?? ""
		Self.terminationLogger.debug("Preparing conversation: <\(conversationIdentifier, privacy: .public)>")
		Self.terminationLogger.debug("Preparing view controller: <\(viewIdentifier, privacy: .public)>")

		tearDown(as: .applicationTermination, destroysSecretKey: isDirect)
	}

	func closeDirectChatConnection() {
		guard let connection = directChatConnection else {
			return
		}

		directChatConnection = nil
		connection.close()
	}

	@MainActor
	func print(_ chatLine: ChatLine) {
		print(chatLine, completionBlock: nil)
	}

	@MainActor
	func print(
		_ chatLine: ChatLine,
		completionBlock: PrintedLineCompletion?
	) {
		presentation?.print(chatLine, completionBlock: completionBlock)
		writeToLogFile(chatLine)
	}

	func addUser(_ user: User) {
		memberInfo?.addUser(user)
	}

	func addMember(_ member: Member) {
		memberInfo?.addMember(member)
	}

	func removeMember(withNickname nickname: String) {
		memberInfo?.removeMember(withNickname: nickname)
	}

	func changeMember(_ nickname: String, mode: ChannelModeSymbol, value: Bool) {
		memberInfo?.changeMember(nickname, mode: mode, value: value)
	}

	/** Records conversation activity against the member `nickname` names.

	 A member is a value the list owns, so activity is reported to the list
	 rather than written through a member the caller happens to be holding. */
	func recordConversation(
		with nickname: String,
		direction: MemberConversationDirection
	) {
		memberInfo?.updateMember(withNickname: nickname) { member in
			switch direction {
			case .outgoing: member.outgoingConversation()
			case .incoming: member.incomingConversation()
			case .mention: member.conversation()
			}
		}
	}

	/// Applies time decay to every member's conversation weights. Call once
	/// before ordering by weight, never from inside a comparator.
	func decayMemberConversations() {
		memberInfo?.decayConversations()
	}

	/// Applies a single protocol unit immediately, publishing its final member list once.
	func withMemberPresentationUpdates(_ body: () throws -> Void) rethrows {
		let list = memberInfo
		list?.beginPresentationUpdates()
		defer { list?.endPresentationUpdates() }
		try body()
	}

	func clearMembers() {
		memberInfo?.clearMembers()
	}

	var numberOfMembers: UInt {
		memberInfo?.numberOfMembers ?? 0
	}

	/// Empty rather than absent when the conversation has no member list yet: a
	/// channel nobody has joined has no members, which is not a different
	/// answer from "no members".
	var memberList: [Member] {
		memberInfo?.memberList ?? []
	}

	func memberExists(_ nickname: String) -> Bool {
		memberInfo?.memberExists(nickname) ?? false
	}

	func findMember(_ nickname: String) -> Member? {
		memberInfo?.findMember(nickname)
	}

	func sortMembers() {
		memberInfo?.sortMembers()
	}

	private var isSelectedConversation: Bool {
		self === associatedSession?.output?.selectedItem
	}

	override var isActive: Bool {
		status == .joined
	}

	override var isSession: Bool {
		false
	}

	override var numberOfChildren: Int {
		0
	}

	override func child(at _: Int) -> ChatItem? {
		nil
	}

	override var label: String {
		if let label = config.label, label.isEmpty == false {
			return label
		}

		return name
	}

	override var associatedConversation: Conversation? {
		self
	}
}
