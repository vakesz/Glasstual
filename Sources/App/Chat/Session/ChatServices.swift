// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/// Dependencies supplied by the application. Presentation delegates are borrowed;
/// the certificate presenter and transport-security store are owned.
@MainActor
final class ChatServices {
	weak var output: (any ServerSessionPresenting)?
	weak var menu: (any MenuPresenting)?
	weak var channelList: (any ChannelListPresenting)?
	weak var applicationState: (any ApplicationStatePresenting)?
	weak var notifications: (any UserNotificationPresenting)?
	weak var fileTransfers: (any FileTransferPresenting)?
	weak var messageRules: (any MessageRuleFiltering)?
	weak var scripts: (any UserScriptRunning)?
	weak var chatSession: ChatSession?

	/// The loaded theme's resolved nickname format.
	var themeNicknameFormat: @MainActor () -> String = { NicknameFormat.default }

	var updateDockBadge: @MainActor () -> Void = {}

	/// Where credentials the session saves on its own go, such as a password
	/// an account registration created.
	var credentialPersistence = KeychainPersistence.shared

	var connectToServer: @MainActor (ServerConnectionRequest) -> Void

	let certificates: (any CertificatePresenting)?

	/// Shared across sessions because STS policies apply to hosts.
	let stsPolicies: STSPolicyStore

	/// The key and certificate each network presents on secure DCC connections.
	let dccIdentities: DCCLocalIdentityStore
	/// The secure DCC peer certificates the user decided to trust.
	let dccPeerCertificates: DCCPeerCertificateStore

	init(
		output: (any ServerSessionPresenting)? = nil,
		menu: (any MenuPresenting)? = nil,
		channelList: (any ChannelListPresenting)? = nil,
		applicationState: (any ApplicationStatePresenting)? = nil,
		notifications: (any UserNotificationPresenting)? = nil,
		fileTransfers: (any FileTransferPresenting)? = nil,
		messageRules: (any MessageRuleFiltering)? = nil,
		scripts: (any UserScriptRunning)? = nil,
		chatSession: ChatSession? = nil,
		certificates: (any CertificatePresenting)? = nil,
		connectToServer: @escaping @MainActor (ServerConnectionRequest) -> Void = { _ in },
		stsPolicies: STSPolicyStore = .applicationStore,
		dccIdentities: DCCLocalIdentityStore = .shared,
		dccPeerCertificates: DCCPeerCertificateStore = .shared
	) {
		self.output = output
		self.menu = menu
		self.channelList = channelList
		self.applicationState = applicationState
		self.notifications = notifications
		self.fileTransfers = fileTransfers
		self.messageRules = messageRules
		self.scripts = scripts
		self.chatSession = chatSession
		self.stsPolicies = stsPolicies
		self.dccIdentities = dccIdentities
		self.dccPeerCertificates = dccPeerCertificates
		self.certificates = certificates
		self.connectToServer = connectToServer
	}
}
