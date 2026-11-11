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

	/** The configured server entry this endpoint's credentials may come from.

	 An STS upgrade keeps the entry it upgraded. A redirect or `/conn` that
	 lands on a host the network's own server list names is that entry: the
	 user configured the host, so its password goes to it. Any other host is
	 somebody the user never configured, and a redirect is server-controlled
	 input, so nothing is sent there. */
	func credentialEndpoint(among servers: [ServerEndpoint]) -> ServerEndpoint? {
		if let inherited = credentialEndpoint {
			return inherited
		}

		return servers.first { $0.serverAddress.caseInsensitiveCompare(host) == .orderedSame }
	}
}

/// How the console reports the TLS version and cipher a connection settled on.
/// A legacy suite says so: it still connects, and the user should know.
func cipherSuiteText(protocolName: String, cipherName: String, legacy: Bool) -> String {
	if legacy {
		return String(localized: .IRC.withTheCipherSuite4Deprecated(protocolName, cipherName))
	}

	return String(localized: .IRC.withTheCipherSuite(protocolName, cipherName))
}

extension ServerSession {
	/// Application shutdown starts while accepted settings saves are still
	/// draining, before each session begins its own teardown.
	var canContinueConnecting: Bool {
		!isTerminating && environment.services.applicationState?.applicationIsTerminating != true
			&& config.bouncerNetwork?.isRemoved != true
	}

	func connect(_ mode: SessionConnectMode = .normal, bypassProxy: Bool = false) {
		guard config.bouncerNetwork?.isRemoved != true else {
			printDebugInformation(toConsole: String(localized: .Bouncer.networkRemovedNotice))
			return
		}
		connect(mode, bypassProxy: bypassProxy, retryingServerIdentifier: nil)
	}

	private func connect(_ mode: SessionConnectMode, bypassProxy: Bool, retryingServerIdentifier: String?) {
		guard canContinueConnecting, connectionState.canConnect else {
			return
		}
		guard SystemSleepState.isSleeping == false else {
			connectionLifecycleLogger.info("Refusing to connect because the system is sleeping")
			return
		}
		let configurationSnapshot = config
		let requestedEndpoint = endpoints.pending
		let diagnostics = ConnectionDiagnostics()
		diagnostics.record(.requested)
		guard var socketConfig = takeConnectionEndpoint(retryingServerIdentifier: retryingServerIdentifier) else { return }
		socketConfig.diagnostics = diagnostics
		cancelConnectCommandSettling()
		connectType = mode
		disconnectType = .normal
		connectionState.beginPreparation()
		stopReconnectTimer()
		reconnect.isEnabled = true
		output?.updateTitle(for: self)
		announceConnectionAttempt(mode, to: socketConfig)
		sessionCredentials.forget()
		if credentialConsent?.covers(host: socketConfig.serverAddress, port: socketConfig.serverPort) != true {
			credentialConsent = nil
		}
		ServerSessionWillConnect(subject: self).post()

		socketConfig.apply(configurationSnapshot, bypassProxy: bypassProxy)
		let startupIdentifier = startup.identifier
		let loadCredentials = credentialLoader
		let selectedServer = endpoints.current
		let conversationConfigs = conversationList.map(\.config)
		let attempt = ConnectAttempt(
			snapshot: configurationSnapshot,
			requestedEndpoint: requestedEndpoint,
			selectedServer: selectedServer,
			conversationConfigs: conversationConfigs,
			items: configurationSnapshot.keychainItems + conversationConfigs.map(\.keychainItem)
				+ (selectedServer.map { [$0.keychainItem] } ?? []),
			socketConfig: socketConfig,
			mode: mode,
			bypassProxy: bypassProxy
		)
		startup.credentialTask = Task { [weak self] in
			let stored = await loadCredentials(attempt.items)
			guard !Task.isCancelled, let self, !isTerminating, isConnecting, startup.identifier == startupIdentifier else { return }
			finishConnecting(attempt, stored: stored)
		}
	}

	private func announceConnectionAttempt(_ mode: SessionConnectMode, to socketConfig: ConnectionConfig) {
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
	}

	/// The rest of `connect`, once the keychain has answered for the attempt.
	private func finishConnecting(_ attempt: ConnectAttempt, stored: [KeychainItem: String]) {
		guard canContinueConnecting else {
			cancelReconnect()
			disconnect()
			return
		}
		guard config == attempt.snapshot else {
			// Refresh the same attempt. Endpoint selection has already consumed
			// an explicit target or advanced the configured-server rotation.
			startup.credentialTask = nil
			connectionState.cancelPreparation()
			endpoints.pending = attempt.requestedEndpoint
			connect(
				attempt.mode,
				bypassProxy: attempt.bypassProxy,
				retryingServerIdentifier: attempt.selectedServer?.uniqueIdentifier
			)
			return
		}
		var edits = attempt.snapshot.pendingKeychainEdits
		for conversationConfig in attempt.conversationConfigs {
			edits.merge(conversationConfig.pendingKeychainEdits) { _, newest in newest }
		}
		if let selectedServer = attempt.selectedServer {
			edits[selectedServer.keychainItem] = selectedServer.pendingServerPassword
		}
		sessionCredentials.install(stored, items: attempt.items, applying: edits)
		var socketConfig = attempt.socketConfig
		/* An explicit endpoint that is not one of the configured servers
		 never receives the account password, over SASL or to services. */
		if attempt.requestedEndpoint != nil, endpoints.current == nil {
			sessionCredentials.withholdsAccountCredentials = true
			printDebugInformation(
				toConsole: ConnectionSafetyStrings.Credentials.withheldFromUnconfiguredHost(
					socketConfig.serverAddress
				)
			)
		}
		socketConfig.proxyPassword = attempt.snapshot.pendingProxyPassword.value(
			orStored: sessionCredentials.password(for: attempt.snapshot.proxyPasswordKeychainItem)
		)
		let connection = Connection(config: socketConfig, onSession: self)
		socket = connection
		startup.credentialTask = nil
		connectionState.finishPreparation()
		connection.open()
	}

	func takeConnectionEndpoint(retryingServerIdentifier: String? = nil) -> ConnectionConfig? {
		let servers = config.serverList
		guard servers.isEmpty == false else {
			printDebugInformation(toConsole: String(localized: .IRC.thereAreNoServersConfigured))
			return nil
		}
		let target = endpoints.take(from: servers, retrying: retryingServerIdentifier)
		let host = target.host
		var port = target.port
		var secured = target.secured
		let enforcedPort = environment.services.stsPolicies.enforcedPort(forHost: host)
		if let enforcedPort {
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
		connectionConfig.connectionRequiresTrustedCertificate = enforcedPort != nil || target.reason == .stsUpgrade
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

		return (endpoints.current ?? config.serverList.first)?.prefersSecuredConnection ?? false
	}

	/// The endpoint `/conn host` connects to: the host on the standard port
	/// for the encryption the current session has.
	func connectCommandEndpoint(host: String) -> PendingIRCEndpoint {
		let secured = sessionPrefersSecuredConnection

		return PendingIRCEndpoint(
			host: host,
			port: secured ? ConnectionDefaults.serverPortSecure : ConnectionDefaults.serverPort,
			secured: secured,
			origin: endpoints.current,
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
			connectionState.beginDisconnect()
			output?.updateTitle(for: self)
			ServerSessionWillDisconnect(subject: self).post()
			changeStateOff()
			invokeDisconnectCallbacks()
			ServerSessionDidDisconnect(subject: self).post()
			return
		}
		cancelPendingSessionTasks()
		cancelDelayedDisconnect()
		guard isConnecting || isConnected, let socket else { return }
		connectionState.beginDisconnect()
		output?.updateTitle(for: self)
		ServerSessionWillDisconnect(subject: self).post()
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
		connectionState.beginQuit()
		if isConnecting, socket == nil {
			cancelReconnect()
			ServerSessionWillSendQuit(subject: self).post()
			disconnect()
			return
		}
		cancelPendingSessionTasks()
		socket?.beginCloseDeadline()
		cancelReconnect()
		ServerSessionWillSendQuit(subject: self).post()
		socket?.clearSendQueue()
		guard isLoggedIn else {
			disconnect()
			return
		}
		send(.quit, arguments: [comment])

		/* Held so that a reconnect inside the two-second window cannot have this
		 stale block tear down the *new* session. */
		scheduled.delayedDisconnect = SessionTimer.once(after: 2) { [weak self, weak socket] in
			guard let self, self.socket === socket else { return }

			scheduled.delayedDisconnect = nil
			disconnect()
		}
	}

	func cancelDelayedDisconnect() {
		scheduled.delayedDisconnect?.stop()
		scheduled.delayedDisconnect = nil
	}

	func cancelScheduledConnection() {
		scheduled.cancelConnection()
	}

	func cancelPendingSessionTasks() {
		outboundTextProducer?.cancel()
		if startup.credentialTask != nil, socket == nil {
			connectionState.cancelPreparation()
			output?.updateTitle(for: self)
		}
		scheduled.cancelPending()
		readMarkers.timer.stop()
		readMarkers.pendingConversations.removeAll()
		resetSASLNegotiation()
		sessionCredentials.forget()
		cancelConnectCommandSettling()
		presencePolling.cancelPopulation()
		typingSender.removeAll()
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
		socket?.showCertificateDetails()
	}

	private func scheduleConnection(after delay: UInt, action: @escaping @MainActor () -> Void) {
		cancelScheduledConnection()
		guard isTerminating == false else { return }

		guard delay > 0 else {
			action()
			return
		}

		scheduled.connection = Task { [weak self] in
			try? await Task.sleep(for: .seconds(delay))

			guard Task.isCancelled == false, let self else { return }

			scheduled.connection = nil
			action()
		}
	}
}

/// One `connect` call's choices, carried across the keychain read.
private struct ConnectAttempt {
	let snapshot: ServerConfig
	let requestedEndpoint: PendingIRCEndpoint?
	let selectedServer: ServerEndpoint?
	let conversationConfigs: [ConversationConfig]
	let items: [KeychainItem]
	let socketConfig: ConnectionConfig
	let mode: SessionConnectMode
	let bypassProxy: Bool
}
