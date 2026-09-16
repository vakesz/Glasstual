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
import Security

/** Whether and when the client comes back after a connection ends.

 Reconnecting is not one flag: a disconnect the user asked for must not come
 back, one the sleep handler caused must, and the interval between attempts
 grows with how many have already failed. */
struct ReconnectSchedule {
	/// Whether the next disconnect should be followed by a reconnect.
	var isEnabled = false
	/// Whether ``isEnabled`` was set by going to sleep rather than by the
	/// user, which is what tells waking up to reconnect.
	var isEnabledForSleepMode = false
	/// How many attempts have been scheduled since the last successful
	/// registration, which is what the backoff is computed from.
	var attemptCount: UInt = 0
	/// Seconds to wait before the connection this schedule is holding back.
	var connectDelay: UInt = 0
	/// Whether the user has already been told this connection went quiet, so
	/// that the warning is printed once rather than every timeout.
	var timeoutWarningShown = false
	var timer: ClientTimer!
}

private let connectionLifecycleLogger = Logger(
	subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
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
	let origin: Server?
	let reason: Reason

	var credentialEndpoint: Server? {
		// Only STS carries endpoint credentials across a reconnect. Redirects
		// and explicit /conn targets do not inherit another endpoint's PASS.
		guard reason == .stsUpgrade,
		      let origin, origin.serverAddress.caseInsensitiveCompare(host) == .orderedSame else { return nil }
		return origin
	}
}

/// How the console reports the TLS version and cipher a connection settled on.
/// A deprecated suite says so: it still connects, and the user should know.
private func cipherSuiteText(protocolName: String, cipherName: String, deprecated: Bool) -> String {
	if deprecated {
		return String(localized: .IRC.withTheCipherSuite4Deprecated(protocolName, cipherName))
	}

	return String(localized: .IRC.withTheCipherSuite(protocolName, cipherName))
}

@MainActor
extension Client {
	func connect() {
		connect(.normal)
	}

	func connect(_ mode: ClientConnectMode) {
		connect(mode, bypassProxy: false)
	}

	func connect(_ mode: ClientConnectMode, bypassProxy: Bool) {
		connect(mode, bypassProxy: bypassProxy, retryingServerIdentifier: nil)
	}

	private func connect(_ mode: ClientConnectMode, bypassProxy: Bool, retryingServerIdentifier: String?) {
		guard isTerminating == false else { return }
		guard isConnecting == false, isConnected == false, isQuitting == false, isDisconnecting == false else {
			return
		}
		guard SystemInformation.systemIsSleeping == false else {
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
		NotificationCenter.default.post(name: .ClientWillConnect, object: self)

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
		socketConfig.floodControlDelayInterval = config.floodControlDelayTimerInterval
		socketConfig.floodControlMaximumMessages = config.floodControlMaximumMessages
		socketConfig.connectionPrefersModernCiphersOnly = environment.preferences.preferModernCiphers
		let session = startup.identifier
		let loadCredentials = credentialLoader
		let selectedServer = server
		let channels = channelList.map(\.config)
		let items = configurationSnapshot.keychainItems + channels.map(\.keychainItem)
			+ (selectedServer.map { [$0.keychainItem] } ?? [])
		pendingCredentialTask = Task { [weak self] in
			let stored = await loadCredentials(items)
			guard !Task.isCancelled, let self, !isTerminating, isConnecting, startup.identifier == session else { return }
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
			for channel in channels {
				edits.merge(channel.pendingKeychainEdits) { _, newest in newest }
			}
			if let selectedServer {
				edits[selectedServer.keychainItem] = selectedServer.pendingServerPassword
			}
			sessionCredentials.install(stored, items: items, applying: edits)
			socketConfig.proxyPassword = configurationSnapshot.pendingProxyPassword.value(
				orStored: sessionCredentials.password(for: configurationSnapshot.proxyPasswordKeychainItem)
			)
			let connection = Connection(config: socketConfig, onClient: self)
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
		if (host as NSString).isValidInternetAddress == false {
			let retryIndex = servers.firstIndex { $0.uniqueIdentifier == retryingServerIdentifier }
			let nextIndex = retryIndex.map(UInt.init)
				?? (lastServerSelected == UInt(NSNotFound) ? 0 : (lastServerSelected + 1) % UInt(servers.count))
			lastServerSelected = nextIndex
			let selected = servers[Int(nextIndex)]
			host = selected.serverAddress
			port = selected.serverPort
			secured = selected.prefersSecuredConnection
			server = selected
		}
		if let enforced = STSPolicyStore.shared.enforcedEndpoint(forHost: host) {
			if enforced.port != port || secured == false {
				printDebugInformation(toConsole: String(localized: .IRC.strictTransportSecurityPolicy(String(enforced.port))))
			}
			port = enforced.port
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
	 With no socket, the server entry the client last connected to — or would
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
			NotificationCenter.default.post(name: .ClientWillDisconnect, object: self)
			changeStateOff()
			invokeDisconnectCallbacks()
			NotificationCenter.default.post(name: .ClientDidDisconnect, object: self)
			return
		}
		cancelPendingSessionTasks()
		cancelDelayedDisconnect()
		guard isConnecting || isConnected, let socket else { return }
		isDisconnecting = true
		output?.updateTitle(for: self)
		NotificationCenter.default.post(name: .ClientWillDisconnect, object: self)
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
			NotificationCenter.default.post(name: .ClientWillSendQuit, object: self)
			disconnect()
			return
		}
		cancelPendingSessionTasks()
		socket?.beginCloseDeadline()
		cancelReconnect()
		NotificationCenter.default.post(name: .ClientWillSendQuit, object: self)
		socket?.clearSendQueue()
		guard isLoggedIn else {
			disconnect()
			return
		}
		send("QUIT", arguments: [comment])

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
		readMarkers.pendingChannels.removeAll()
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

	func toggleAwayStatus(withComment comment: String?) {
		if userIsAway {
			toggleAwayStatus(false, withComment: nil)
		} else {
			toggleAwayStatus(
				true,
				withComment: comment?.isEmpty == false ? comment : String(localized: .IRC.beBackLater)
			)
		}
	}

	func toggleAwayStatus(_ setAway: Bool) {
		toggleAwayStatus(setAway, withComment: String(localized: .IRC.beBackLater))
	}

	func toggleAwayStatus(_ setAway: Bool, withComment comment: String?) {
		automaticallyAwayForScreenSleep = false
		guard isLoggedIn, setAway == false || comment != nil else { return }
		/* `AWAYLEN` is measured here rather than at each caller: the menu, the
		 screen-sleep timer and `/away` all end up on this line, and only the
		 first of them used to bound the comment. */
		let comment = comment.map(truncatedAwayComment)
		if setAway, let comment {
			send("AWAY", arguments: [comment])
		} else {
			send("AWAY", arguments: [])
		}
		lastAwayMessage = setAway ? comment : nil
		let newNickname: String?
		if setAway {
			newNickname = config.awayNickname
			preAwayUserNickname = userNickname
		} else {
			newNickname = preAwayUserNickname ?? (config.awayNickname?.isEmpty == false ? config.nickname : nil)
			preAwayUserNickname = nil
		}
		if let newNickname {
			changeNickname(newNickname)
		}
	}

	func setAwayForScreenSleep() {
		guard isLoggedIn, !userIsAway, lastAwayMessage == nil, !automaticallyAwayForScreenSleep else { return }
		toggleAwayStatus(true)
		automaticallyAwayForScreenSleep = true
	}

	func clearAwayAfterScreenSleep() {
		guard automaticallyAwayForScreenSleep else { return }
		automaticallyAwayForScreenSleep = false
		if isLoggedIn {
			toggleAwayStatus(false)
		} else {
			lastAwayMessage = nil
			preAwayUserNickname = nil
		}
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

/// The mode a disconnect is reported under: a rejected certificate says so
/// whatever the client had configured for this disconnect.
func effectiveDisconnectMode(
	configured: ClientDisconnectMode,
	errorDomain: String?,
	errorCode: Int?
) -> ClientDisconnectMode {
	guard errorDomain == connectionErrorDomain,
	      errorCode == Int(ConnectionErrorCode.badCertificate.rawValue)
	else { return configured }
	return .badCertificate
}

/// What `USER` sends. An empty username or real name falls back to the
/// nickname, and the mode bits are the RFC 2812 ones for invisible and plain.
struct RegistrationValues: Equatable {
	let username: String
	let realName: String
	let modeSymbols: String

	init(nickname: String, username: String, realName: String, setInvisibleMode: Bool) {
		self.username = username.isEmpty ? nickname : username
		self.realName = realName.isEmpty ? nickname : realName
		modeSymbols = setInvisibleMode ? "8" : "0"
	}
}

@MainActor
extension Client {
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
		isWaitingForNickServ = false
		serverHasNickServ = false
		userIsIdentifiedWithNickServ = false
		userIsAway = false
		userIsIRCop = false
		znc.isConnected = false
		znc.isSendingCertificateInfo = false
		znc.certificateChainText = nil
		znc.isPlayingBackHistory = false

		/* The flag exists to stop one connection attempt from upgrading twice.
		 Clearing it only on a successful TLS handshake meant an upgrade that
		 failed to connect left it set for the life of the client object, and
		 every later STS offer from that server was ignored. The session it
		 guards ends here. */
		performedSTSUpgrade = false

		resetChatHistoryState()
		reconnect.isEnabled = false
		reconnect.timeoutWarningShown = false
		lastWhoRequestChannelListIndex = 0
		server = nil
		KeychainPersistence.shared.persist(Dictionary(uniqueKeysWithValues: retiredServerKeychainItems.map { ($0, .cleared) }))
		retiredServerKeychainItems.removeAll()
		userHostmask = nil
		forgetUserNickname()
		nicknameRetry.attempt = 0
		nicknameRetry.sentNickname = nil
		preAwayUserNickname = nil
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
		} else {
			/* Nothing is scheduled, so the backoff has nothing to grow for. A
			 user-initiated disconnect ends the run, and the connection the user
			 starts next must not inherit the delay this one had reached. */
			reconnect.attemptCount = 0
		}

		supportInfo.reset()
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
		let description = cipherSuiteText(
			protocolName: SecureTransportSupport.description(forProtocolType: protocolType),
			cipherName: SecureTransportSupport.description(forCipherSuite: cipherSuite),
			deprecated: SecureTransportSupport.isCipherSuiteDeprecated(cipherSuite)
		)
		printDebugInformation(toConsole: String(localized: .IRC.connectionSecuredUsing(description)))
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
		NotificationCenter.default.post(name: .ClientDidConnect, object: self)

		let registration = RegistrationValues(
			nickname: config.nickname,
			username: config.username,
			realName: config.realName,
			setInvisibleMode: config.setInvisibleModeOnConnect
		)
		sendCapability("LS", data: "302")
		if let password = sessionServerPassword {
			sendPassword(password)
		}
		changeNickname(config.nickname)
		send("USER", arguments: [registration.username, registration.modeSymbols, "*", registration.realName])
	}

	func connectionDidDisconnect(error disconnectError: Error?) {
		changeStateOff(withError: disconnectError)
		invokeDisconnectCallbacks()
		NotificationCenter.default.post(name: .ClientDidDisconnect, object: self)
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

@MainActor
private extension Client {
	func presentDisconnect(_ disconnectError: Error?) {
		let nsError = disconnectError as NSError?
		let disconnectMode = effectiveDisconnectMode(
			configured: disconnectType,
			errorDomain: nsError?.domain,
			errorCode: nsError?.code
		)

		if let disconnectError {
			printError(disconnectError.localizedDescription, asCommand: LogLineFormat.defaultCommand)
		}

		let disconnectMessage = disconnectMode.reasonText
		for channel in channelList {
			guard channel.isActive else {
				channel.errorOnLastJoinAttempt = false
				continue
			}
			channel.deactivate()
			if !channel.isUtility {
				printDebugInformation(disconnectMessage, in: channel)
			}
		}

		printDebugInformation(toConsole: disconnectMessage)
		presentation?.mark()
	}
}

enum ClientConnectionTimerPolicy {
	static let pingInterval: TimeInterval = 270
	static let pongCheckInterval: TimeInterval = 30
	static let reconnectInterval: TimeInterval = 20
	static let maximumReconnectInterval: TimeInterval = 300
	static let retryInterval: TimeInterval = 240
	static let timeoutInterval: TimeInterval = 360

	/** How long to wait before reconnection attempt number `attempt`.

	 A fixed twenty seconds forever is a client that keeps knocking at the same
	 rate whether the server bounced once or has been down since yesterday, and
	 a network outage has every client on it knock in lockstep. The delay
	 doubles from twenty seconds to a five-minute ceiling, and `jitter` — a
	 fraction the caller draws at random — takes up to a quarter of it back off
	 again so that the attempts spread out instead of arriving together. */
	static func reconnectDelay(attempt: UInt, jitter: Double) -> TimeInterval {
		// Capped before the shift so that a long-running client cannot overflow it.
		let doublings = min(attempt, 8)
		let backoff = min(reconnectInterval * TimeInterval(1 << doublings), maximumReconnectInterval)
		let spread = backoff * 0.25 * min(max(jitter, 0), 1)

		return max(1, backoff - spread)
	}

	enum PongAction: Equatable {
		case none
		case ping
		case warnTimeout
		case disconnect
	}

	static func pongAction(
		elapsed: TimeInterval,
		eofReceived: Bool,
		disconnectOnTimeout: Bool,
		pingEnabled: Bool,
		warningAlreadyShown: Bool
	) -> PongAction {
		if elapsed >= timeoutInterval {
			if eofReceived || disconnectOnTimeout {
				return .disconnect
			}
			return warningAlreadyShown ? .none : .warnTimeout
		}
		if elapsed >= pingInterval, pingEnabled {
			return .ping
		}
		return .none
	}
}

@MainActor
extension Client {
	func stopAllTimers() {
		stopAutojoinTimer()
		stopAutojoinDelayedWarningTimer()
		cancelPendingAutojoin()
		stopISONTimer()
		stopReconnectTimer()
		stopRetryTimer()
		stopPongTimer()
		stopSASLTimeoutTimer()
		stopWhoTimer()
		readMarkers.timer.stop()
	}

	func startPongTimer() {
		guard !pongTimer.isActive else { return }
		pongTimer.start(ClientConnectionTimerPolicy.pongCheckInterval, repeats: true)
	}

	func stopPongTimer() {
		guard pongTimer.isActive else { return }
		pongTimer.stop()
	}

	func onPongTimer() {
		guard isLoggedIn else {
			stopPongTimer()
			return
		}

		let elapsed = Date().timeIntervalSince1970 - lastMessageReceived
		switch ClientConnectionTimerPolicy.pongAction(
			elapsed: elapsed,
			eofReceived: socket?.EOFReceived ?? false,
			disconnectOnTimeout: config.performDisconnectOnPongTimer,
			pingEnabled: config.performPongTimer,
			warningAlreadyShown: reconnect.timeoutWarningShown
		) {
		case .disconnect:
			printDebugInformation(String(localized: .IRC.minutesHaveElapsedSinceLastResponse(Float(elapsed / 60))), in: nil)
			disconnect()
		case .warnTimeout:
			reconnect.timeoutWarningShown = true
			printDebugInformation(String(localized: .IRC.minutesHaveElapsedSinceLastResponseFromThis(Float(elapsed / 60))), in: nil)
		case .ping:
			if let serverAddress {
				sendPing(serverAddress)
			}
		case .none:
			break
		}
	}

	/** Schedules the next reconnection attempt.

	 The run is one-shot rather than repeating because each attempt waits longer
	 than the last: a disconnect that leaves `reconnect.isEnabled` set brings the
	 client back here, and `onReconnectTimer` re-arms the schedule itself when
	 the attempt it started never got as far as connecting. */
	func startReconnectTimer() {
		guard isTerminating == false else { return }
		let enabled = reconnect.isEnabledForSleepMode
			? !config.autoSleepModeDisconnect
			: config.autoReconnect
		guard enabled, !reconnect.timer.isActive else { return }
		let delay = ClientConnectionTimerPolicy.reconnectDelay(
			attempt: reconnect.attemptCount,
			jitter: .random(in: 0 ... 1)
		)
		reconnect.attemptCount &+= 1
		reconnect.timer.start(delay, repeats: false)
	}

	func stopReconnectTimer() {
		guard reconnect.timer.isActive else { return }
		reconnect.timer.stop()
	}

	func onReconnectTimer() {
		guard !isConnecting, !isConnected else { return }

		connect(.reconnect)

		/* `connect` refuses while the machine is asleep, while the client is
		 quitting, and when there is no endpoint to take. Nothing else would put
		 the schedule back, so it is put back here rather than letting the one
		 refusal end automatic reconnection for the session. */
		guard !isConnecting, !isConnected, !isTerminating, reconnect.isEnabled else { return }

		startReconnectTimer()
	}

	func startRetryTimer() {
		guard !retryTimer.isActive else { return }
		retryTimer.start(ClientConnectionTimerPolicy.retryInterval)
	}

	func stopRetryTimer() {
		guard retryTimer.isActive else { return }
		retryTimer.stop()
	}

	func onRetryTimer() {
		guard isConnected else { return }
		addDisconnectCallback { [weak self] in
			self?.connect(.retry)
		}
		disconnect()
	}
}

@MainActor
extension Client {
	func noteReachabilityChanged(_ reachable: Bool) {
		guard reachable == false else { return }
		disconnectOnReachabilityChange()
	}

	/** Tears the session down when the network the user was on has gone.

	 Only a logged-in session is worth disconnecting, and only when the user
	 asked for it: a client still registering has nothing to quit, and one that
	 stays connected across a network change is the default. */
	func disconnectOnReachabilityChange() {
		guard isLoggedIn, config.performDisconnectOnReachabilityChange else { return }

		disconnectType = .reachabilityChange
		reconnect.isEnabled = true
		disconnect()
	}
}
