// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
import os
import Security

private let connectionLifecycleLogger = Logger(
	subsystem: LogSubsystem.current,
	category: "ConnectionLifecycle"
)

/** Where the next connection goes, when it is not the next configured server.

 `secured` is decided by whoever asks for the endpoint, from the connection it
 replaces. A redirect or a `/conn` that dropped to plaintext would send the
 account password the encrypted connection was protecting in clear, so neither
 may ask for less encryption than the session it follows had. */
struct PendingIRCEndpoint {
	enum Reason {
		case stsUpgrade
		case serverRedirect
		case userCommand
	}

	let host: String
	let port: UInt16
	let secured: Bool
	let origin: ServerEndpoint?
	let reason: Reason

	var credentialEndpoint: ServerEndpoint? {
		// Only STS carries endpoint credentials across a reconnect. Redirects
		// and explicit /conn targets do not inherit another endpoint's PASS.
		guard reason == .stsUpgrade,
		      let origin, origin.serverAddress.caseInsensitiveCompare(host) == .orderedSame else { return nil }
		return origin
	}
}

/// How the console reports the TLS version and cipher a connection settled on.
/// A legacy suite says so: it still connects, and the user should know.
private func cipherSuiteText(protocolName: String, cipherName: String, legacy: Bool) -> String {
	if legacy {
		return String(localized: .IRC.withTheCipherSuite4Deprecated(protocolName, cipherName))
	}

	return String(localized: .IRC.withTheCipherSuite(protocolName, cipherName))
}

extension ServerSession {
	func connect() {
		connect(.normal)
	}

	func connect(_ mode: SessionConnectMode) {
		connect(mode, bypassProxy: false)
	}

	func connect(_ mode: SessionConnectMode, bypassProxy: Bool) {
		connect(mode, bypassProxy: bypassProxy, retryingServerIdentifier: nil)
	}

	private func connect(_ mode: SessionConnectMode, bypassProxy: Bool, retryingServerIdentifier: String?) {
		guard isTerminating == false else { return }
		guard isConnecting == false, isConnected == false, isQuitting == false, isDisconnecting == false else {
			return
		}
		guard SystemSleepState.isSleeping == false else {
			connectionLifecycleLogger.info("Refusing to connect because the system is sleeping")
			return
		}
		let configurationSnapshot = config
		let requestedEndpoint = pendingEndpoint
		let diagnostics = ConnectionDiagnostics()
		diagnostics.record(.requested)
		guard var socketConfig = takeConnectionEndpoint(retryingServerIdentifier: retryingServerIdentifier) else { return }
		socketConfig.diagnostics = diagnostics
		cancelConnectCommandSettling()
		connectType = mode
		disconnectType = .normal
		isConnecting = true
		stopReconnectTimer()
		reconnect.isEnabled = true
		output?.updateTitle(for: self)
		if mode == .reconnect {
			printDebugInformation(toConsole: String(localized: .IRC.miscellaneousMessagesRelatedReconnecting))
		} else if mode == .retry {
			printDebugInformation(toConsole: String(localized: .IRC.miscellaneousMessagesRelatedRetrying))
		}
		if config.showConnectionPrefersIPv4Warning {
			printDebugInformation(String(localized: .IRC.pleaseTakeNoticeThePreferenceLabeled))
		}
		printDebugInformation(toConsole: String(localized: .IRC.connectingToOnPort(
			socketConfig.serverAddress,
			String(socketConfig.serverPort)
		)))
		sessionCredentials.forget()
		NotificationCenter.default.post(name: .serverSessionWillConnect, object: self)

		socketConfig.addressType = config.addressType
		socketConfig.cipherSuites = config.cipherSuites
		socketConfig.connectionShouldValidateCertificateChain = config.validateServerCertificateChain
		socketConfig.identityClientSideCertificate = config.identityClientSideCertificate
		if bypassProxy == false {
			socketConfig.proxyType = config.proxyType
			if socketConfig.proxyType == .socks5 || socketConfig.proxyType == .HTTP {
				socketConfig.proxyPort = config.proxyPort
				socketConfig.proxyAddress = config.proxyAddress
				socketConfig.proxyUsername = config.proxyUsername
			}
		}
		socketConfig.setFloodControl(
			delayInterval: config.floodControlDelayTimerInterval,
			maximumMessages: config.floodControlMaximumMessages
		)
		let startupIdentifier = startup.identifier
		let loadCredentials = credentialLoader
		let selectedServer = server
		let conversationConfigs = conversationList.map(\.config)
		let items = configurationSnapshot.keychainItems + conversationConfigs.map(\.keychainItem)
			+ (selectedServer.map { [$0.keychainItem] } ?? [])
		pendingCredentialTask = Task { [weak self] in
			let stored = await loadCredentials(items)
			guard !Task.isCancelled, let self, !isTerminating, isConnecting, startup.identifier == startupIdentifier else { return }
			guard config == configurationSnapshot else {
				// Refresh the same attempt. Endpoint selection has already consumed
				// an explicit target or advanced the configured-server rotation.
				pendingCredentialTask = nil
				isConnecting = false
				pendingEndpoint = requestedEndpoint
				connect(mode, bypassProxy: bypassProxy, retryingServerIdentifier: selectedServer?.uniqueIdentifier)
				return
			}
			var edits = configurationSnapshot.pendingKeychainEdits
			for conversationConfig in conversationConfigs {
				edits.merge(conversationConfig.pendingKeychainEdits) { _, newest in newest }
			}
			if let selectedServer {
				edits[selectedServer.keychainItem] = selectedServer.pendingServerPassword
			}
			sessionCredentials.install(stored, items: items, applying: edits)
			socketConfig.proxyPassword = configurationSnapshot.pendingProxyPassword.value(
				orStored: sessionCredentials.password(for: configurationSnapshot.proxyPasswordKeychainItem)
			)
			let connection = Connection(config: socketConfig, onSession: self)
			socket = connection
			pendingCredentialTask = nil
			connection.open()
		}
	}

	func takeConnectionEndpoint(retryingServerIdentifier: String? = nil) -> ConnectionConfig? {
		let servers = config.serverList
		guard servers.isEmpty == false else {
			printDebugInformation(toConsole: String(localized: .IRC.thereAreNoServersConfigured))
			return nil
		}
		let endpoint = pendingEndpoint
		pendingEndpoint = nil
		var host = endpoint?.host ?? ""
		var port = endpoint?.port ?? ConnectionDefaults.serverPort
		var secured = endpoint?.secured ?? false
		server = endpoint?.credentialEndpoint
		if host.isValidInternetAddress == false {
			let retryIndex = servers.firstIndex { $0.uniqueIdentifier == retryingServerIdentifier }
			let nextIndex = retryIndex.map(UInt.init)
				?? lastServerSelected.map { ($0 + 1) % UInt(servers.count) } ?? 0
			lastServerSelected = nextIndex
			let selected = servers[Int(nextIndex)]
			host = selected.serverAddress
			port = selected.serverPort
			secured = selected.prefersSecuredConnection
			server = selected
		}
		if let enforcedPort = environment.services.stsPolicies.enforcedPort(forHost: host) {
			if enforcedPort != port || secured == false {
				printDebugInformation(toConsole: String(localized: .IRC.strictTransportSecurityPolicy(String(enforcedPort))))
			}
			port = enforcedPort
			secured = true
		}
		var connectionConfig = ConnectionConfig()
		connectionConfig.serverAddress = host
		connectionConfig.serverPort = port
		connectionConfig.connectionPrefersSecuredConnection = secured
		return connectionConfig
	}

	/** Whether the session a follow-up endpoint replaces was meant to be encrypted.

	 A live socket answers for itself: it is encrypted, or it was opened to be.
	 With no socket, the server entry the session last connected to — or would
	 connect to first — stands in for it. */
	var sessionPrefersSecuredConnection: Bool {
		if let socket {
			return socket.isSecured || socket.config.connectionPrefersSecuredConnection
		}

		return (server ?? config.serverList.first)?.prefersSecuredConnection ?? false
	}

	/// The endpoint `/conn host` connects to: the host on the standard port
	/// for the encryption the current session has.
	func connectCommandEndpoint(host: String) -> PendingIRCEndpoint {
		let secured = sessionPrefersSecuredConnection

		return PendingIRCEndpoint(
			host: host,
			port: secured ? ConnectionDefaults.serverPortSecure : ConnectionDefaults.serverPort,
			secured: secured,
			origin: server,
			reason: .userCommand
		)
	}

	func autoConnect(withDelay delay: UInt, afterWakeUp: Bool) {
		reconnect.connectDelay = delay
		if afterWakeUp {
			autoConnectAfterWakeUp()
		} else {
			autoConnect()
		}
	}

	func autoConnect() {
		scheduleConnection(after: reconnect.connectDelay, action: autoConnectPerformConnect)
	}

	func autoConnectPerformConnect() {
		guard isConnecting == false, isConnected == false else { return }
		connect()
	}

	func autoConnectAfterWakeUp() {
		if reconnect.connectDelay > 0 {
			printDebugInformation(toConsole: String(localized: .IRC.delayingAutoConnectForSeconds(arg1: reconnect.connectDelay)))
		}
		scheduleConnection(after: reconnect.connectDelay, action: autoConnectAfterWakeUpPerformConnect)
	}

	func autoConnectAfterWakeUpPerformConnect() {
		guard isConnecting == false, isConnected == false else { return }
		reconnect.isEnabledForSleepMode = true
		connect(.reconnect)
	}

	func disconnect() {
		if isConnecting, socket == nil {
			// Credential preparation is already a connection attempt, but has no
			// socket delegate to deliver its completion to removal/reconnect callers.
			isDisconnecting = true
			output?.updateTitle(for: self)
			NotificationCenter.default.post(name: .serverSessionWillDisconnect, object: self)
			changeStateOff()
			invokeDisconnectCallbacks()
			NotificationCenter.default.post(name: .serverSessionDidDisconnect, object: self)
			return
		}
		cancelPendingSessionTasks()
		cancelDelayedDisconnect()
		guard isConnecting || isConnected, let socket else { return }
		isDisconnecting = true
		output?.updateTitle(for: self)
		NotificationCenter.default.post(name: .serverSessionWillDisconnect, object: self)
		socket.close()
	}

	func quit() {
		let comment = disconnectType == .computerSleep
			? config.sleepModeLeavingComment
			: config.normalLeavingComment
		quit(withComment: comment)
	}

	func quit(withComment comment: String) {
		guard isConnecting || isConnected, isQuitting == false, isDisconnecting == false else { return }
		isQuitting = true
		if isConnecting, socket == nil {
			cancelReconnect()
			NotificationCenter.default.post(name: .serverSessionWillSendQuit, object: self)
			disconnect()
			return
		}
		cancelPendingSessionTasks()
		socket?.beginCloseDeadline()
		cancelReconnect()
		NotificationCenter.default.post(name: .serverSessionWillSendQuit, object: self)
		socket?.clearSendQueue()
		guard isLoggedIn else {
			disconnect()
			return
		}
		send(.quit, arguments: [comment])

		/* Held so that a reconnect inside the two-second window cannot have this
		 stale block tear down the *new* session. */
		pendingDisconnectTask = Task { [weak self, weak socket] in
			try? await Task.sleep(for: .seconds(2))

			guard Task.isCancelled == false, let self, self.socket === socket else { return }

			pendingDisconnectTask = nil
			disconnect()
		}
	}

	func cancelDelayedDisconnect() {
		pendingDisconnectTask?.cancel()
		pendingDisconnectTask = nil
	}

	func cancelScheduledConnection() {
		pendingConnectionTask?.cancel()
		pendingConnectionTask = nil
	}

	func cancelPendingSessionTasks() {
		outboundTextProducer?.cancel()
		if pendingCredentialTask != nil, socket == nil {
			isConnecting = false
			isQuitting = false
			output?.updateTitle(for: self)
		}
		pendingCredentialTask?.cancel()
		pendingCredentialTask = nil
		pendingConfirmationTasks.values.forEach { $0.cancel() }
		pendingConfirmationTasks.removeAll()
		readMarkers.timer.stop()
		readMarkers.pendingConversations.removeAll()
		resetSASLNegotiation()
		sessionCredentials.forget()
		cancelScheduledConnection()
		cancelConnectCommandSettling()
		trackedUserPopulationTask?.cancel()
		trackedUserPopulationTask = nil
		rejoinTasks.values.forEach { $0.cancel() }
		rejoinTasks.removeAll()
		typingPauseTasks.values.forEach { $0.cancel() }
		typingPauseTasks.removeAll()
	}

	func cancelReconnect() {
		cancelScheduledConnection()
		reconnect.isEnabled = false
		reconnect.isEnabledForSleepMode = false
		stopReconnectTimer()
		output?.updateTitle(for: self)
	}

	func presentCertificateTrustInformation() {
		guard isSecured else { return }
		socket?.openSecuredConnectionCertificateModal()
	}

	private func scheduleConnection(after delay: UInt, action: @escaping @MainActor () -> Void) {
		cancelScheduledConnection()
		guard isTerminating == false else { return }

		guard delay > 0 else {
			action()
			return
		}

		pendingConnectionTask = Task { [weak self] in
			try? await Task.sleep(for: .seconds(delay))

			guard Task.isCancelled == false, let self else { return }

			pendingConnectionTask = nil
			action()
		}
	}
}

extension SessionDisconnectMode {
	/// The mode a disconnect is reported under: a rejected certificate says so
	/// whatever the session had configured for this disconnect.
	static func effective(
		configured: SessionDisconnectMode,
		errorDomain: String?,
		errorCode: Int?
	) -> SessionDisconnectMode {
		guard errorDomain == connectionErrorDomain,
		      errorCode == Int(ConnectionErrorCode.badCertificate.rawValue)
		else { return configured }
		return .badCertificate
	}
}

extension ServerSession {
	func resetAllPropertyValues() {
		batchMessages.dequeueEntries()
		typingTracker.removeAll()
		typingStateSent.removeAll()
		typingActiveSentAt.removeAll()
		typingPauseTasks.values.forEach { $0.cancel() }
		typingPauseTasks.removeAll()

		nextLineReplyToMessageIdentifier = nil
		nextMessageReplyIdentifier = nil
		reconnect.connectDelay = 0
		invokingISONCommandForFirstTime = false
		isAutojoining = false
		isAutojoined = false
		cancelConnectCommandSettling()
		autojoin.delayedWarningCount = 0
		isConnected = false
		isConnecting = false
		isLoggedIn = false
		isQuitting = false
		isDisconnecting = false
		inWhoisResponse = false
		inWhowasResponse = false
		nickServ = NickServIdentification()
		away.isAway = false
		userIsIRCop = false
		znc.isConnected = false
		znc.isSendingCertificateInfo = false
		znc.certificateChainText = nil
		znc.isPlayingBackHistory = false

		/* The flag exists to stop one connection attempt from upgrading twice.
		 Clearing it only on a successful TLS handshake meant an upgrade that
		 failed to connect left it set for the life of the session object, and
		 every later STS offer from that server was ignored. The session it
		 guards ends here. */
		performedSTSUpgrade = false

		resetChatHistoryState()
		// Reconnect intent belongs to the pending schedule, which survives this reset.
		reconnect.timeoutWarningShown = false
		lastWhoRequestConversationListIndex = 0
		server = nil
		KeychainPersistence.shared.persist(Dictionary(uniqueKeysWithValues: retiredServerKeychainItems.map { ($0, .cleared) }))
		retiredServerKeychainItems.removeAll()
		userHostmask = nil
		forgetUserNickname()
		nicknameRetry.attempt = 0
		nicknameRetry.sentNickname = nil
		away.previousNickname = nil
		lastMessageReceived = 0

		resetSASLNegotiation()
		resetCapabilityNegotiation()
		removeAllUsers()
	}

	func changeStateOff(withError disconnectError: Error? = nil) {
		guard isConnecting || isConnected else { return }

		let terminating = isTerminating
		socket = nil
		removeTimedCommands()
		removeRequestedCommands()
		stopAutojoinTimer()
		cancelPendingAutojoin()
		stopAutojoinDelayedWarningTimer()
		stopISONTimer()
		stopPongTimer()
		stopRetryTimer()
		cancelDelayedDisconnect()
		cancelPendingSessionTasks()

		if !terminating, reconnect.isEnabled {
			startReconnectTimer()
			reconnect.isEnabled = reconnect.timer.isActive
		} else {
			reconnect.isEnabled = false
		}
		if !reconnect.isEnabled {
			/* Nothing is scheduled, so the backoff has nothing to grow for. A
			 user-initiated disconnect ends the run, and the connection the user
			 starts next must not inherit the delay this one had reached. */
			reconnect.attemptCount = 0
		}

		apply(supportInfo.reset())
		clearAddressBookCache()
		clearTrackedUsers()

		if !terminating {
			presentDisconnect(disconnectError)
		}

		endLoggingSessions()
		resetAllPropertyValues()

		if !terminating, let output {
			output.reloadChatItemGroup(self)
			output.updateTitle(for: self)
		}
	}

	func connectionWillConnect(toProxy proxyHost: String, port proxyPort: UInt16) {
		switch socket?.config.proxyType {
		case .socks5, .tor:
			printDebugInformation(toConsole: String(localized: .IRC.connectingUsingSocks5ProxyOnPort(proxyHost, String(proxyPort))))
		case .HTTP:
			printDebugInformation(toConsole: String(localized: .IRC.connectingUsingHttpProxyOnPort(proxyHost, String(proxyPort))))
		default:
			break
		}
	}

	func connectionDidSecure(protocolType: tls_protocol_version_t, cipherSuite: tls_ciphersuite_t) {
		performedSTSUpgrade = false
		output?.reloadChatItem(self)
		output?.updateTitle(for: self)
		let isLegacy = SecureTransportSupport.isCipherSuiteLegacy(cipherSuite)
		let description = cipherSuiteText(
			protocolName: SecureTransportSupport.description(forProtocolType: protocolType),
			cipherName: SecureTransportSupport.description(forCipherSuite: cipherSuite),
			legacy: isLegacy
		)
		printDebugInformation(toConsole: String(localized: .IRC.connectionSecuredUsing(description)))

		/* Said on every connection that settled on a suite without forward
		 secrecy, which is what the transport's own fallback to the legacy suites
		 produces and the only way one is ever offered. Keyed on what was
		 negotiated rather than on whether the fallback ran, so the warning cannot
		 be missed by a path that reaches the same suite another way. */
		guard isLegacy else { return }

		printDebugInformation(toConsole: String(localized: .IRC.connectionIsNotForwardSecret))
	}

	func connectionDidConnect() {
		guard !isTerminating else { return }

		startRetryTimer()
		if let connectedAddress = socket?.connectedAddress, socket?.config.serverAddress.isIPAddress == false {
			printDebugInformation(toConsole: String(localized: .IRC.connectionToHostAtEstablished(connectedAddress)))
		} else {
			printDebugInformation(toConsole: String(localized: .IRC.connectionToHostEstablished))
		}

		isConnecting = false
		isConnected = true
		userNickname = config.nickname
		nicknameRetry.sentNickname = config.nickname
		output?.updateTitle(for: self)
		NotificationCenter.default.post(name: .serverSessionDidConnect, object: self)

		/* What `USER` sends: an empty username or real name falls back to the
		 nickname, and the mode bits are the RFC 2812 ones for invisible and
		 plain. */
		let username = config.username.isEmpty ? config.nickname : config.username
		let realName = config.realName.isEmpty ? config.nickname : config.realName
		let modeSymbols = config.setInvisibleModeOnConnect ? "8" : "0"
		sendCapability("LS", data: "302")
		if let password = sessionServerPassword {
			sendPassword(password)
		}
		changeNickname(config.nickname)
		send(.user, arguments: [username, modeSymbols, "*", realName])
	}

	func connectionDidDisconnect(error disconnectError: Error?) {
		changeStateOff(withError: disconnectError)
		invokeDisconnectCallbacks()
		NotificationCenter.default.post(name: .serverSessionDidDisconnect, object: self)
	}

	func connectionDidCloseReadStream() {
		guard !isTerminating, !isDisconnecting else { return }
		if isQuitting {
			disconnect()
			return
		}
		printDebugInformation(toConsole: String(localized: .IRC.serverClosedReadStream))
	}

	func connectionWillSend(_ data: String) {
		guard !isTerminating else { return }
		rawDataLogOutgoingTraffic(data)
	}
}

private extension ServerSession {
	func presentDisconnect(_ disconnectError: Error?) {
		let nsError = disconnectError as NSError?
		let disconnectMode = SessionDisconnectMode.effective(
			configured: disconnectType,
			errorDomain: nsError?.domain,
			errorCode: nsError?.code
		)

		if let disconnectError {
			printError(disconnectError.localizedDescription, asCommand: ChatLineFormat.defaultCommand)
		}

		let disconnectMessage = disconnectMode.reasonText
		for conversation in conversationList {
			guard conversation.isActive else {
				conversation.errorOnLastJoinAttempt = false
				continue
			}
			conversation.deactivate()
			if !conversation.isConsole {
				printDebugInformation(disconnectMessage, in: conversation)
			}
		}

		printDebugInformation(toConsole: disconnectMessage)
		presentation?.mark()
	}
}
