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
	}

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
		guard canContinueConnecting, connectionState.canConnect else {
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
		connectionState.beginPreparation()
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
			|| socketConfig.connectionRequiresTrustedCertificate
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
		startup.credentialTask = Task { [weak self] in
			let stored = await loadCredentials(items)
			guard !Task.isCancelled, let self, !isTerminating, isConnecting, startup.identifier == startupIdentifier else { return }
			guard canContinueConnecting else {
				cancelReconnect()
				disconnect()
				return
			}
			guard config == configurationSnapshot else {
				// Refresh the same attempt. Endpoint selection has already consumed
				// an explicit target or advanced the configured-server rotation.
				startup.credentialTask = nil
				connectionState.cancelPreparation()
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
			startup.credentialTask = nil
			connectionState.finishPreparation()
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
		connectionConfig.connectionRequiresTrustedCertificate = enforcedPort != nil || endpoint?.reason == .stsUpgrade
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
			connectionState.beginDisconnect()
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
		connectionState.beginDisconnect()
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
		connectionState.beginQuit()
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
		if startup.credentialTask != nil, socket == nil {
			connectionState.cancelPreparation()
			output?.updateTitle(for: self)
		}
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

		pendingConnectionTask = Task { [weak self] in
			try? await Task.sleep(for: .seconds(delay))

			guard Task.isCancelled == false, let self else { return }

			pendingConnectionTask = nil
			action()
		}
	}
}
