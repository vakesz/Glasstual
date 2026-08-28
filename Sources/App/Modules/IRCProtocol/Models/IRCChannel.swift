/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
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
import GlasstualPluginKit
import os
import Synchronization

public extension Notification.Name {
	static let ircChannelConfigurationWasUpdated = Notification.Name(
		"IRCChannelConfigurationWasUpdatedNotification"
	)
}

/// Swift source keeps the historic public name while the implementation uses a
/// concise native type name. Objective-C continues to see `IRCChannel` through
/// the runtime name below.
public typealias IRCChannel = Channel

@objc(IRCChannel)
open class Channel: TreeItem, ChannelMemberListing, ChannelMemberListPrivateProtocol {
	private static let logger = Logger(
		subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
		category: "IRCChannel"
	)

	private static let terminationLogger = Logger(
		subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
		category: "Termination"
	)

	public private(set) var config: ChannelConfig {
		didSet { refreshDescription() }
	}

	@objc public var topic: String? {
		didSet {
			guard topic != oldValue else {
				return
			}

			viewController?.setTopic(topic)
		}
	}

	public var status: ChannelStatus = .parted {
		didSet {
			guard status != oldValue else {
				return
			}

			performActionOnStatusChange()
		}
	}

	/// Compatibility getter for Objective-C plug-ins that still declare the
	/// historic `IRCChannelStatus` enum in their bridging header.
	@objc(status)
	public var objectiveCStatusRawValue: UInt {
		status.rawValue
	}

	@objc public var directChatConnection: DirectChatConnection?
	@objc public var sentInitialWhoRequest = false
	@objc public var channelModesReceived = false
	@objc public var channelNamesReceived = false
	@objc public var errorOnLastJoinAttempt = false
	@objc public private(set) var channelJoinTime: TimeInterval = 0
	@objc public private(set) var modeInfo: ChannelModeState?
	@objc public private(set) var memberInfo: ChannelMemberList?
	/** Whether a logging session banner has been written and not yet closed. A line
	 counter cannot express this: writing the banner is itself a write. */
	@objc public private(set) var logFileSessionIsOpen = false

	private var logFile: FileLogger?
	private var statusChangedByAction = false

	/// The Objective-C declarations remain visible until their consumers are
	/// migrated. Both values refer to this same Objective-C runtime object.
	private var legacyChannel: IRCChannel {
		self
	}

	@available(*, unavailable)
	override public init() {
		fatalError("Use init(config:)")
	}

	public init(config: ChannelConfig) {
		self.config = config

		super.init()

		refreshDescription()
		self.config.writeSecretKeyToKeychain()
	}

	public func updateConfig(_ config: ChannelConfig) {
		updateConfig(config, fireChangedNotification: true, updateStoredChannelList: true)
	}

	public func updateConfig(_ config: ChannelConfig, fireChangedNotification: Bool) {
		updateConfig(
			config,
			fireChangedNotification: fireChangedNotification,
			updateStoredChannelList: true
		)
	}

	public func updateConfig(
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
		self.config.writeSecretKeyToKeychain()

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

	@objc public var configurationDictionary: [String: Any] {
		PropertyListModel.encode(config)
	}

	@objc(copyWithZone:)
	public func copy(with _: NSZone? = nil) -> Any {
		self
	}

	/** `NSObject.description` is nonisolated, so it cannot read the main-actor
	 configuration the text is built from. The text is published here instead
	 whenever the configuration changes. */
	private let descriptionSnapshot = Mutex("<IRCChannel>")

	override open nonisolated var description: String {
		descriptionSnapshot.withLock { $0 }
	}

	override func associatedClientDidChange() {
		refreshDescription()
	}

	/// Republishes the text `description` returns.
	func refreshDescription() {
		let text = "<IRCChannel [\(associatedClient?.description ?? "")]: \(name)>"
		descriptionSnapshot.withLock { $0 = text }
	}

	override open var uniqueIdentifier: String {
		config.uniqueIdentifier
	}

	override open var name: String {
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

	@objc public var secretKey: String? {
		config.secretKey
	}

	@objc public var autoJoin: Bool {
		get { config.autoJoin }
		set {
			guard isChannel, newValue != config.autoJoin else {
				return
			}

			config.autoJoin = newValue
		}
	}

	override open var isChannel: Bool {
		config.type == .channel
	}

	override open var isPrivateMessage: Bool {
		config.type == .privateMessage
	}

	@objc public var isUtility: Bool {
		config.type == .utility
	}

	@objc public var isDirectChat: Bool {
		config.type == .directChat
	}

	@objc public var isPrivateMessageForZNCUser: Bool {
		isPrivateMessage && associatedClient?.nicknameIsZNCUser(name) == true
	}

	public var type: ChannelType {
		config.type
	}

	/// Compatibility getter for Objective-C plug-ins that still declare the
	/// historic `IRCChannelType` enum in their bridging header.
	@objc(type)
	public var objectiveCTypeRawValue: UInt {
		type.rawValue
	}

	@objc public var channelTypeString: String {
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

	@objc public var logFilePath: URL? {
		guard let writePath = FileLogger.writePath(for: self) else {
			return nil
		}

		return URL(fileURLWithPath: writePath)
	}

	@objc public var lastLine: LogLine? {
		(viewController as AnyObject as? LogController)?.lastLine()
	}

	@objc public func preferencesChanged() {
		if TextualPreferences.displayPublicMessageCountOnDockBadge() == false, isChannel {
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

	public func resetStatus(_ newStatus: ChannelStatus) {
		guard newStatus != .joining else {
			return
		}

		channelModesReceived = false
		channelNamesReceived = false
		errorOnLastJoinAttempt = false
		sentInitialWhoRequest = false
		channelJoinTime = 0
		modeInfo = nil
		status = newStatus
		statusChangedByAction = false
		topic = nil
		clearMembers()
		memberInfo = nil
	}

	@objc(resetStatus:)
	public func resetStatusFromObjectiveC(_ rawValue: UInt) {
		guard let status = ChannelStatus(rawValue: rawValue) else { return }
		resetStatus(status)
	}

	@objc open func activate() {
		statusChangedByAction = true
		resetStatus(.joined)

		guard let client = associatedClient else {
			return
		}

		if isUtility == false {
			memberInfo = ChannelMemberList(channel: legacyChannel)

			if isSelectedChannel, let mainWindow = AppController.shared.mainWindow {
				mainWindow.memberList?.assign(to: legacyChannel)
				mainWindow.updateMemberListVisibilityForSelection()
			}
		}

		if isChannel {
			client.postEvent(toViewController: "channelJoined", for: legacyChannel)
			modeInfo = ChannelModeState(channel: legacyChannel)
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

		channelJoinTime = Date().timeIntervalSince1970

		if isChannel || isPrivateMessage {
			client.noteChannelActivated(legacyChannel)
		}
	}

	@objc open func deactivate() {
		statusChangedByAction = true
		resetStatus(.parted)

		if isChannel {
			associatedClient?.postEvent(toViewController: "channelParted", for: legacyChannel)
		}
	}

	@MainActor @objc public func prepareForPermanentDestruction() {
		statusChangedByAction = true
		resetStatus(.terminated)
		closeDirectChatConnection()
		closeLogFile()
		config.destroySecretKeyKeychainItem()

		let descriptions = [
			"TDCChannelPropertiesSheet",
			"TDCChannelModifyTopicSheet",
			"TDCChannelModifyModesSheet",
			"TDCChannelBanListSheet",
		]
		let windows = SharedApplication.sharedWindowController().windows(fromWindowList: descriptions)

		for case let window as SheetBase in windows {
			guard let channelWindow = window as? TDCChannelPrototype,
			      channelWindow.channelId == self.uniqueIdentifier
			else {
				continue
			}

			window.close()
		}

		AppController.shared.mainWindow.inputHistoryManager().destroy(self)
		viewController?.prepareForPermanentDestruction()
	}

	@MainActor
	@objc public func prepareForApplicationTermination() {
		let channelIdentifier = uniqueIdentifier
		Self.terminationLogger.debug("Preparing channel: <\(channelIdentifier, privacy: .public)>")
		statusChangedByAction = true
		resetStatus(.terminated)
		closeDirectChatConnection()
		closeLogFile()

		if isPrivateMessage {
			config.destroySecretKeyKeychainItem()
		}

		let viewIdentifier = viewController?.uniqueIdentifier ?? ""
		Self.terminationLogger.debug("Preparing view controller: <\(viewIdentifier, privacy: .public)>")
		viewController?.prepareForApplicationTermination()
	}

	@objc public func closeDirectChatConnection() {
		guard let connection = directChatConnection else {
			return
		}

		directChatConnection = nil
		connection.close()
	}

	@objc public func reopenLogFileIfNeeded() {
		if TextualPreferences.logToDiskIsEnabled(), isUtility == false {
			logFile?.reopenIfNeeded()
		} else {
			closeLogFile()
		}
	}

	@objc public func closeLogFile() {
		logFile?.close()
		/* Leaving the handle in place made the lazy re-creation below unreachable, so
		 every later write went to a closed logger. */
		logFile = nil
	}

	@objc public func logFileWriteSessionBegin() {
		guard logFileSessionIsOpen == false else { return }

		/* Set before writing: the banner is written through writeToLogFile. */
		logFileSessionIsOpen = true
		associatedClient?.logFileRecordSessionChanged(true, in: legacyChannel)
	}

	@objc public func logFileWriteSessionEnd() {
		guard logFileSessionIsOpen else { return }

		associatedClient?.logFileRecordSessionChanged(false, in: legacyChannel)
		logFileSessionIsOpen = false
	}

	@objc(writeToLogLineToLogFile:)
	public func writeToLogFile(_ logLine: LogLine) {
		guard isUtility == false, TextualPreferences.logToDiskIsEnabled() else {
			return
		}

		logFileWriteSessionBegin()

		if logFile == nil {
			logFile = FileLogger(channel: legacyChannel)
		}

		logFile?.writeLogLine(logLine)
	}

	@MainActor
	@objc(print:)
	public func print(_ logLine: LogLine) {
		print(logLine, completionBlock: nil)
	}

	@MainActor
	@objc(print:completionBlock:)
	public func print(
		_ logLine: LogLine,
		completionBlock: LogControllerPrintOperationCompletion?
	) {
		viewController?.print(logLine, completionBlock: completionBlock)
		writeToLogFile(logLine)
	}

	@objc(addUser:)
	public func addUser(_ user: User) {
		memberInfo?.addUser(user)
	}

	@objc(addMember:)
	public func addMember(_ member: ChannelUser) {
		memberInfo?.addMember(member)
	}

	@objc(addMember:checkForDuplicates:)
	public func addMember(_ member: ChannelUser, checkForDuplicates: Bool) {
		memberInfo?.addMember(member, checkForDuplicates: checkForDuplicates)
	}

	@objc(removeMemberWithNickname:)
	public func removeMember(withNickname nickname: String) {
		memberInfo?.removeMember(withNickname: nickname)
	}

	@objc(removeMember:)
	public func removeMember(_ member: ChannelUser) {
		memberInfo?.removeMember(member)
	}

	@objc(resortMember:)
	public func resortMember(_ member: ChannelUser) {
		memberInfo?.resortMember(member)
	}

	@objc(replaceMember:withMember:)
	public func replaceMember(_ oldMember: ChannelUser, with newMember: ChannelUser) {
		memberInfo?.replaceMember(oldMember, with: newMember)
	}

	@objc(replaceMember:withMember:resort:)
	public func replaceMember(_ oldMember: ChannelUser, with newMember: ChannelUser, resort: Bool) {
		memberInfo?.replaceMember(oldMember, with: newMember, resort: resort)
	}

	@objc(replaceMember:withMember:resort:replaceInAllChannels:)
	public func replaceMember(
		_ oldMember: ChannelUser,
		with newMember: ChannelUser,
		resort: Bool,
		replaceInAllChannels: Bool
	) {
		memberInfo?.replaceMember(
			oldMember,
			with: newMember,
			resort: resort,
			replaceInAllChannels: replaceInAllChannels
		)
	}

	@objc(changeMember:mode:value:)
	public func changeMember(_ nickname: String, mode: String, value: Bool) {
		memberInfo?.changeMember(nickname, mode: mode, value: value)
	}

	@objc public func clearMembers() {
		memberInfo?.clearMembers()
	}

	@objc public var numberOfMembers: UInt {
		memberInfo?.numberOfMembers ?? 0
	}

	/// Empty rather than absent when the channel has no member list yet: a
	/// channel nobody has joined has no members, which is not a different
	/// answer from "no members".
	@objc open var memberList: [ChannelUser] {
		memberInfo?.memberList ?? []
	}

	open var channelMembers: [ChannelUser] {
		memberList
	}

	@objc(pasteboardDataForMembers:)
	public func pasteboardData(for members: [ChannelUser]) -> Data {
		memberInfo?.pasteboardData(for: members) ?? Data()
	}

	@objc(readNicknamesFromPasteboardData:withBlock:)
	public class func readNicknames(
		from pasteboardData: Data,
		with callback: (IRCChannel, [String]) -> Void
	) -> Bool {
		ChannelMemberList.readNicknames(from: pasteboardData, with: callback)
	}

	@objc(readMembersFromPasteboardData:withBlock:)
	public class func readMembers(
		from pasteboardData: Data,
		with callback: (IRCChannel, [ChannelUser]) -> Void
	) -> Bool {
		ChannelMemberList.readMembers(from: pasteboardData, with: callback)
	}

	@objc(memberExists:)
	public func memberExists(_ nickname: String) -> Bool {
		memberInfo?.memberExists(nickname) ?? false
	}

	@objc(findMember:)
	open func findMember(_ nickname: String) -> ChannelUser? {
		memberInfo?.findMember(nickname)
	}

	@objc public func sortMembers() {
		memberInfo?.sortMembers()
	}

	private var isSelectedChannel: Bool {
		self === AppController.shared.mainWindow.selectedItem
	}

	override open var isActive: Bool {
		status == .joined
	}

	override open var isClient: Bool {
		false
	}

	override open var numberOfChildren: Int {
		0
	}

	override open func child(at _: Int) -> TreeItem? {
		nil
	}

	override open var label: String {
		if let label = config.label, label.isEmpty == false {
			return label
		}

		return name
	}

	override open var associatedChannel: IRCChannel? {
		legacyChannel
	}
}
