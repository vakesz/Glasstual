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

import CocoaExtensions
import Foundation
import os

extension Notification.Name {
	static let ircChannelConfigurationWasUpdated = Notification.Name(
		"IRCChannelConfigurationWasUpdatedNotification"
	)
}

class Channel: ChatItem {
	private static let logger = Logger(
		subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
		category: "IRCChannel"
	)

	private static let terminationLogger = Logger(
		subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
		category: "Termination"
	)

	private(set) var config: ChannelConfig

	var topic: String? {
		didSet {
			guard topic != oldValue else {
				return
			}

			presentation?.setTopic(topic)
		}
	}

	var status: ChannelStatus = .parted {
		didSet {
			guard status != oldValue else {
				return
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
	private(set) var memberInfo: ChannelMemberList?
	/** Whether a logging session banner has been written and not yet closed. A line
	 counter cannot express this: writing the banner is itself a write. */
	private(set) var logFileSessionIsOpen = false

	private var logFile: FileLogger?
	private var statusChangedByAction = false
	private var cachedSecretKey: String?
	private var credentialLoadTask: Task<Void, Never>?

	@available(*, unavailable)
	override init() {
		fatalError("Use init(config:)")
	}

	init(config: ChannelConfig) {
		self.config = config

		super.init()

		persistSecretKey()
	}

	func updateConfig(_ config: ChannelConfig) {
		updateConfig(config, fireChangedNotification: true, updateStoredChannelList: true)
	}

	func updateConfig(_ config: ChannelConfig, fireChangedNotification: Bool) {
		updateConfig(
			config,
			fireChangedNotification: fireChangedNotification,
			updateStoredChannelList: true
		)
	}

	func updateConfig(
		_ config: ChannelConfig,
		fireChangedNotification: Bool,
		updateStoredChannelList: Bool
	) {
		if config == self.config {
			return
		}

		guard self.config.type == config.type,
		      self.config.channelName == config.channelName,
		      self.config.uniqueIdentifier == config.uniqueIdentifier
		else {
			Self.logger.error("Tried to load configuration for incorrect channel")
			return
		}

		self.config = config
		persistSecretKey()

		if updateStoredChannelList {
			associatedClient?.updateStoredChannelList()
		}

		if fireChangedNotification {
			NotificationCenter.default.post(
				name: .ircChannelConfigurationWasUpdated,
				object: self
			)
		}
	}

	var configurationDictionary: [String: PropertyListValue] {
		PropertyListModel.encode(config)
	}

	func copy(with _: NSZone? = nil) -> Any {
		self
	}

	override var uniqueIdentifier: String {
		config.uniqueIdentifier
	}

	override var name: String {
		get { config.channelName }
		set {
			guard isChannel == false, newValue != config.channelName else {
				return
			}

			config.channelName = newValue

			// A rename changes what the on-disk channel list and every
			// name-keyed lookup resolve to, so persist it and tell observers
			// exactly as updateConfig(_:) does. updateConfig cannot be used
			// here: it refuses a configuration whose channelName differs.
			associatedClient?.updateStoredChannelList()
			NotificationCenter.default.post(
				name: .ircChannelConfigurationWasUpdated,
				object: self
			)
		}
	}

	var secretKey: String? {
		let stored: String? = if let client = associatedClient, client.sessionCredentials.hasResolved(config.keychainItem) {
			client.sessionCredentials.password(for: config.keychainItem)
		} else {
			cachedSecretKey
		}
		return config.pendingSecretKey.value(orStored: stored)
	}

	private func persistSecretKey() {
		credentialLoadTask?.cancel()
		let edits = config.pendingKeychainEdits
		let item = config.keychainItem
		if !edits.isEmpty {
			cachedSecretKey = config.pendingSecretKey.value(orStored: cachedSecretKey)
			KeychainPersistence.shared.persist(edits) { [weak self] committed in
				guard let self else { return }
				let acknowledged = committed.filter { config.pendingKeychainEdits[$0.key] == $0.value }
				associatedClient?.sessionCredentials.apply(acknowledged)
				config.acknowledgeKeychainEdits(acknowledged)
			}
		} else {
			credentialLoadTask = Task { [weak self] in
				let stored = await KeychainSecretLoader.passwords(for: [item])
				guard !Task.isCancelled, let self, config.keychainItem == item, config.pendingSecretKey == .unchanged else { return }
				cachedSecretKey = stored[item]
				credentialLoadTask = nil
			}
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

	override var isPrivateMessage: Bool {
		config.type == .privateMessage
	}

	var isUtility: Bool {
		config.type == .utility
	}

	var isDirectChat: Bool {
		config.type == .directChat
	}

	var isPrivateMessageForZNCUser: Bool {
		isPrivateMessage && associatedClient?.nicknameIsZNCUser(name) == true
	}

	var type: ChannelType {
		config.type
	}

	var channelTypeString: String {
		switch type {
		case .channel:
			"channel"
		case .privateMessage:
			"query"
		case .utility:
			"utility"
		case .directChat:
			"direct-chat"
		@unknown default:
			"unknown"
		}
	}

	var logFilePath: URL? {
		guard let writePath = FileLogger.writePath(for: self) else {
			return nil
		}

		return URL(fileURLWithPath: writePath)
	}

	var lastLine: LogLine? {
		presentation?.lastPrintedLine()
	}

	func preferencesChanged() {
		if clientPreferences.displayPublicMessageCountOnDockBadge == false, isChannel {
			dockUnreadCount = 0
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

	func resetStatus(_ newStatus: ChannelStatus) {
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

	/** Marks the channel joined.

	 `date` is when the join happened rather than when this runs, so a JOIN
	 carrying `server-time` records the server's clock. */
	func activate(at date: Date = Date()) {
		statusChangedByAction = true
		resetStatus(.joined)
		/* Recorded before anything that can leave early: the channel is joined
		 whether or not it has a client to talk to, and noteChannelActivated
		 below already asks the server what has been read in it. */
		joinedAt = date

		guard let client = associatedClient else {
			return
		}

		if isUtility == false {
			memberInfo = ChannelMemberList(channel: self)

			if isSelectedChannel, let output = associatedClient?.output {
				output.assignMemberList(to: self)
				output.updateMemberListVisibilityForSelection()
			}
		}

		if isChannel {
			modeInfo = ChannelModeState(channel: self)
		}

		if isPrivateMessage || isDirectChat {
			let peerNickname: String = if isDirectChat {
				directChatConnection?.peerNickname ?? String(name.dropFirst())
			} else {
				name
			}

			addUser(client.findUserOrCreate(peerNickname))
			addUser(client.findUserOrCreate(client.userNickname))
		}

		if isChannel || isPrivateMessage {
			client.noteChannelActivated(self)
		}
	}

	func deactivate() {
		statusChangedByAction = true
		resetStatus(.parted)
	}

	@MainActor func prepareForRemoval(preservingLocalData: Bool) {
		statusChangedByAction = true
		credentialLoadTask?.cancel()
		credentialLoadTask = nil
		resetStatus(.terminated)
		closeDirectChatConnection()
		closeLogFile()

		associatedClient?.output?.closeSheets(forChannelId: uniqueIdentifier)
		if !preservingLocalData {
			KeychainPersistence.shared.persist([config.keychainItem: .cleared])
			associatedClient?.output?.destroyInputHistory(for: self)
		}
		presentation?.tearDown(preservingLocalData ? .preservingRemoval : .permanentRemoval)
	}

	@MainActor
	func prepareForApplicationTermination() {
		let channelIdentifier = uniqueIdentifier
		Self.terminationLogger.debug("Preparing channel: <\(channelIdentifier, privacy: .public)>")
		statusChangedByAction = true
		credentialLoadTask?.cancel()
		credentialLoadTask = nil
		resetStatus(.terminated)
		closeDirectChatConnection()
		closeLogFile()

		if isPrivateMessage {
			KeychainPersistence.shared.persist([config.keychainItem: .cleared])
		}

		let viewIdentifier = presentation?.presentationIdentifier ?? ""
		Self.terminationLogger.debug("Preparing view controller: <\(viewIdentifier, privacy: .public)>")
		presentation?.tearDown(.applicationTermination)
	}

	func closeDirectChatConnection() {
		guard let connection = directChatConnection else {
			return
		}

		directChatConnection = nil
		connection.close()
	}

	func reopenLogFileIfNeeded() {
		if clientPreferences.logToDiskIsEnabled, isUtility == false {
			logFile?.reopenIfNeeded()
		} else {
			closeLogFile()
		}
	}

	func closeLogFile() {
		logFileWriteSessionEnd()
		logFile?.close()
		// The shared file-command stream retains the pending banner and close.
		logFile = nil
	}

	func logFileWriteSessionBegin() {
		guard logFileSessionIsOpen == false else { return }

		/* Set before writing: the banner is written through writeToLogFile. */
		logFileSessionIsOpen = true
		associatedClient?.logFileRecordSessionChanged(true, in: self)
	}

	func logFileWriteSessionEnd() {
		guard logFileSessionIsOpen else { return }

		associatedClient?.logFileRecordSessionChanged(false, in: self)
		logFileSessionIsOpen = false
	}

	func writeToLogFile(_ logLine: LogLine) {
		guard isUtility == false, clientPreferences.logToDiskIsEnabled else {
			return
		}

		logFileWriteSessionBegin()
		openedLogFile().writeLogLine(logLine)
	}

	/** The session banner is written through `writeToLogFile`, which opens the
	 session, which writes the banner: the optimizer inlines that cycle, and a
	 lazy assignment left inside the read of the same property made it produce
	 SIL its own verifier rejects (Xcode 27 beta 6). Resolving the logger into a
	 local first keeps the read and the write apart. */
	private func openedLogFile() -> FileLogger {
		if let logFile {
			return logFile
		}
		let opened = FileLogger(channel: self)
		logFile = opened
		return opened
	}

	@MainActor
	func print(_ logLine: LogLine) {
		print(logLine, completionBlock: nil)
	}

	@MainActor
	func print(
		_ logLine: LogLine,
		completionBlock: PrintedLineCompletion?
	) {
		presentation?.print(logLine, completionBlock: completionBlock)
		writeToLogFile(logLine)
	}

	func addUser(_ user: User) {
		memberInfo?.addUser(user)
	}

	func addMember(_ member: ChannelUser) {
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
		direction: ChannelConversationDirection
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

	/// Empty rather than absent when the channel has no member list yet: a
	/// channel nobody has joined has no members, which is not a different
	/// answer from "no members".
	var memberList: [ChannelUser] {
		memberInfo?.memberList ?? []
	}

	var channelMembers: [ChannelUser] {
		memberList
	}

	func memberExists(_ nickname: String) -> Bool {
		memberInfo?.memberExists(nickname) ?? false
	}

	func findMember(_ nickname: String) -> ChannelUser? {
		memberInfo?.findMember(nickname)
	}

	func sortMembers() {
		memberInfo?.sortMembers()
	}

	private var isSelectedChannel: Bool {
		self === associatedClient?.output?.selectedItem
	}

	override var isActive: Bool {
		status == .joined
	}

	override var isClient: Bool {
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

	override var associatedChannel: Channel? {
		self
	}
}
