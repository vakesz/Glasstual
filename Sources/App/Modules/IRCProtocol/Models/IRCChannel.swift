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

import Foundation
import os

public extension Notification.Name {
	static let ircChannelConfigurationWasUpdated = Notification.Name(
		"IRCChannelConfigurationWasUpdatedNotification"
	)
}

/// Swift source keeps the historic public name while the implementation uses a
/// concise native type name. Objective-C continues to see `IRCChannel` through
/// the runtime name below.
public typealias IRCChannel = Channel

private enum ChannelStatusChange {
	static let configurationNotification = Notification.Name.ircChannelConfigurationWasUpdated
}

private struct ChannelMainActorTransfer<Value>: @unchecked Sendable {
	let value: Value
}

@objc(IRCChannel)
open class Channel: TreeItem, IRCChannelMemberListPrototype, IRCChannelMemberListPrivatePrototype {
	private static let logger = Logger(
		subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
		category: "IRCChannel"
	)

	private static let terminationLogger = Logger(
		subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
		category: "Termination"
	)

	@objc public private(set) var config: ChannelConfig
	@objc public var topic: String? {
		didSet {
			guard topic != oldValue else {
				return
			}

			viewController?.setTopic(topic)
		}
	}

	@objc public var status: IRCChannelStatus = .parted {
		didSet {
			guard status != oldValue else {
				return
			}

			performActionOnStatusChange()
		}
	}

	@objc public var directChatConnection: DirectChatConnection?
	@objc public var sentInitialWhoRequest = false
	@objc public var channelModesReceived = false
	@objc public var channelNamesReceived = false
	@objc public var errorOnLastJoinAttempt = false
	@objc public private(set) var channelJoinTime: TimeInterval = 0
	@objc public private(set) var modeInfo: ChannelMode?
	@objc public private(set) var memberInfo: ChannelMemberList?
	@objc public private(set) var logFileSessionCount: UInt = 0

	private var logFile: FileLogger?
	private var statusChangedByAction = false

	/// The Objective-C declarations remain visible until their consumers are
	/// migrated. Both values refer to this same Objective-C runtime object.
	private var legacyChannel: IRCChannel {
		(self as AnyObject) as! IRCChannel
	}

	private var legacyTreeItem: IRCTreeItem {
		(self as AnyObject) as! IRCTreeItem
	}

	private func swiftMember(_ member: IRCChannelUser) -> ChannelUser {
		(member as AnyObject) as! ChannelUser
	}

	private func legacyMember(_ member: ChannelUser) -> IRCChannelUser {
		(member as AnyObject) as! IRCChannelUser
	}

	@available(*, unavailable)
	override public init() {
		fatalError("Use init(config:)")
	}

	@objc(initWithConfigDictionary:)
	public convenience init(configDictionary: [String: Any]) {
		self.init(config: ChannelConfig(dictionary: configDictionary))
	}

	@objc(initWithConfig:)
	public init(config: ChannelConfig) {
		self.config = config

		super.init()

		config.writeSecretKeyToKeychain()
	}

	@objc(updateConfig:)
	public func updateConfig(_ config: ChannelConfig) {
		updateConfig(config, fireChangedNotification: true, updateStoredChannelList: true)
	}

	@objc(updateConfig:fireChangedNotification:)
	public func updateConfig(_ config: ChannelConfig, fireChangedNotification: Bool) {
		updateConfig(
			config,
			fireChangedNotification: fireChangedNotification,
			updateStoredChannelList: true
		)
	}

	@objc(updateConfig:fireChangedNotification:updateStoredChannelList:)
	public func updateConfig(
		_ config: ChannelConfig,
		fireChangedNotification: Bool,
		updateStoredChannelList: Bool
	) {
		if config.isEqual(self.config) {
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
		config.writeSecretKeyToKeychain()

		if updateStoredChannelList {
			associatedClient?.updateStoredChannelList()
		}

		if fireChangedNotification {
			NotificationCenter.default.post(
				name: ChannelStatusChange.configurationNotification,
				object: self
			)
		}
	}

	@objc public var configurationDictionary: [String: Any] {
		config.dictionaryValue
	}

	@objc(copyWithZone:)
	public func copy(with _: NSZone? = nil) -> Any {
		self
	}

	override open var description: String {
		"<IRCChannel [\(associatedClient?.description ?? "")]: \(name)>"
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

			guard let mutableConfig = config.mutableCopy() as? MutableChannelConfig else {
				return
			}

			mutableConfig.channelName = newValue
			config = mutableConfig
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

			guard let mutableConfig = config.mutableCopy() as? MutableChannelConfig else {
				return
			}

			mutableConfig.autoJoin = newValue
			config = mutableConfig
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

	@objc public var type: IRCChannelType {
		config.type
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
		guard let writePath = FileLogger.writePath(for: legacyTreeItem) else {
			return nil
		}

		return URL(fileURLWithPath: writePath)
	}

	@objc public var lastLine: TVCLogLine? {
		guard let line = viewController?.lastLine else {
			return nil
		}

		return (line as AnyObject) as? TVCLogLine
	}

	@objc public func preferencesChanged() {
		if TPCPreferences.displayPublicMessageCountOnDockBadge() == false, isChannel {
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

	@objc(resetStatus:)
	public func resetStatus(_ newStatus: IRCChannelStatus) {
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

	@objc open func activate() {
		statusChangedByAction = true
		resetStatus(.joined)

		guard let client = associatedClient else {
			return
		}

		if isUtility == false {
			memberInfo = ChannelMemberList(channel: legacyChannel)

			if isSelectedChannel {
				let channel = legacyChannel
				MainActor.assumeIsolated {
					NSObject.masterController().mainWindow.memberList?.assign(to: channel)
				}
			}
		}

		if isChannel {
			client.postEvent(toViewController: "channelJoined", for: legacyChannel)
			modeInfo = ChannelMode(channel: legacyChannel)
		}

		if isPrivateMessage || isDirectChat {
			let peerNickname: String = if isDirectChat {
				directChatConnection?.peerNickname ?? String(name.dropFirst())
			} else {
				name
			}

			add(client.findUserOrCreate(peerNickname))
			add(client.findUserOrCreate(client.userNickname))
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

	@objc public func prepareForPermanentDestruction() {
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
		let windows = TXSharedApplication.sharedWindowController().windows(fromWindowList: descriptions)

		for case let window as TDCSheetBase in windows {
			guard let channelWindow = window as? TDCChannelPrototype,
			      channelWindow.channelId == self.uniqueIdentifier
			else {
				continue
			}

			window.close()
		}

		let treeItem = ChannelMainActorTransfer(value: legacyTreeItem)
		MainActor.assumeIsolated {
			NSObject.masterController().mainWindow.inputHistoryManager().destroy(treeItem.value)
		}
		viewController?.perform(NSSelectorFromString("prepareForPermanentDestruction"))
	}

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
		viewController?.perform(NSSelectorFromString("prepareForApplicationTermination"))
	}

	@objc public func closeDirectChatConnection() {
		guard let connection = directChatConnection else {
			return
		}

		directChatConnection = nil
		connection.close()
	}

	@objc public func reopenLogFileIfNeeded() {
		if TPCPreferences.logToDiskIsEnabled(), isUtility == false {
			logFile?.reopenIfNeeded()
		} else {
			closeLogFile()
		}
	}

	@objc public func closeLogFile() {
		logFile?.close()
	}

	@objc public func logFileWriteSessionBegin() {
		associatedClient?.logFileRecordSessionChanged(true, in: legacyChannel)
	}

	@objc public func logFileWriteSessionEnd() {
		associatedClient?.logFileRecordSessionChanged(false, in: legacyChannel)
		logFileSessionCount = 0
	}

	@objc(writeToLogLineToLogFile:)
	public func writeToLogFile(_ logLine: TVCLogLine) {
		guard isUtility == false, TPCPreferences.logToDiskIsEnabled() else {
			return
		}

		logFileSessionCount += 1

		if logFileSessionCount == 1 {
			logFileWriteSessionBegin()
		}

		if logFile == nil {
			logFile = FileLogger(channel: legacyChannel)
		}

		logFile?.writeLogLine(logLine)
	}

	@objc(print:)
	public func print(_ logLine: TVCLogLine) {
		print(logLine, completionBlock: nil)
	}

	@objc(print:completionBlock:)
	public func print(
		_ logLine: TVCLogLine,
		completionBlock: LogControllerPrintOperationCompletion?
	) {
		viewController?.print(logLine, completionBlock: completionBlock)
		writeToLogFile(logLine)
	}

	@objc(addUser:)
	public func add(_ user: User) {
		memberInfo?.addUser(user)
	}

	@objc(addMember:)
	public func addMember(_ member: IRCChannelUser) {
		memberInfo?.addMember(swiftMember(member))
	}

	@objc(addMember:checkForDuplicates:)
	public func addMember(_ member: IRCChannelUser, checkForDuplicates: Bool) {
		memberInfo?.addMember(swiftMember(member), checkForDuplicates: checkForDuplicates)
	}

	@objc(removeMemberWithNickname:)
	public func removeMember(withNickname nickname: String) {
		memberInfo?.removeMember(withNickname: nickname)
	}

	@objc(removeMember:)
	public func removeMember(_ member: IRCChannelUser) {
		memberInfo?.removeMember(swiftMember(member))
	}

	@objc(resortMember:)
	public func resortMember(_ member: IRCChannelUser) {
		memberInfo?.resortMember(swiftMember(member))
	}

	@objc(replaceMember:withMember:)
	public func replaceMember(_ oldMember: IRCChannelUser, withMember newMember: IRCChannelUser) {
		memberInfo?.replaceMember(swiftMember(oldMember), with: swiftMember(newMember))
	}

	@objc(replaceMember:withMember:resort:)
	public func replaceMember(_ oldMember: IRCChannelUser, withMember newMember: IRCChannelUser, resort: Bool) {
		memberInfo?.replaceMember(swiftMember(oldMember), with: swiftMember(newMember), resort: resort)
	}

	@objc(replaceMember:withMember:resort:replaceInAllChannels:)
	public func replaceMember(
		_ oldMember: IRCChannelUser,
		withMember newMember: IRCChannelUser,
		resort: Bool,
		replaceInAllChannels: Bool
	) {
		memberInfo?.replaceMember(
			swiftMember(oldMember),
			with: swiftMember(newMember),
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

	@objc open var memberList: [IRCChannelUser]? {
		memberInfo?.memberList?.map(legacyMember)
	}

	@objc(pasteboardDataForMembers:)
	public func pasteboardData(forMembers members: [IRCChannelUser]) -> Data {
		memberInfo?.pasteboardData(for: members.map(swiftMember)) ?? Data()
	}

	@objc(readNicknamesFromPasteboardData:withBlock:)
	public class func readNicknames(
		fromPasteboardData pasteboardData: Data,
		with callback: (IRCChannel, [String]) -> Void
	) -> Bool {
		ChannelMemberList.readNicknames(from: pasteboardData, with: callback)
	}

	@objc(readMembersFromPasteboardData:withBlock:)
	public class func readMembers(
		fromPasteboardData pasteboardData: Data,
		with callback: (IRCChannel, [IRCChannelUser]) -> Void
	) -> Bool {
		ChannelMemberList.readMembers(from: pasteboardData) { channel, members in
			callback(channel, members.map { ($0 as AnyObject) as! IRCChannelUser })
		}
	}

	@objc(memberExists:)
	public func memberExists(_ nickname: String) -> Bool {
		memberInfo?.memberExists(nickname) ?? false
	}

	@objc(findMember:)
	open func findMember(_ nickname: String) -> IRCChannelUser? {
		memberInfo?.findMember(nickname).map(legacyMember)
	}

	@objc public func sortMembers() {
		memberInfo?.sortMembers()
	}

	private var isSelectedChannel: Bool {
		let channel = ChannelMainActorTransfer(value: self)
		return MainActor.assumeIsolated {
			channel.value === NSObject.masterController().mainWindow.selectedItem
		}
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
