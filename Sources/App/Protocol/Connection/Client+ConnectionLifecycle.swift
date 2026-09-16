/* *********************************************************************
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
 *********************************************************************** */

import CocoaExtensions
import Foundation
import os

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
		reconnectEnabled = true
		output?.updateTitle(for: self)
		if mode == .reconnect {
			printDebugInformation(toConsole: ConnectionStrings.reconnecting)
		} else if mode == .retry {
			printDebugInformation(toConsole: ConnectionStrings.retrying)
		}
		if config.showConnectionPrefersIPv4Warning {
			printDebugInformation(ConnectionStrings.legacyIPv4PreferenceNotice)
		}
		printDebugInformation(toConsole: ConnectionStrings.connecting(
			host: socketConfig.serverAddress,
			port: socketConfig.serverPort
		))
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
			printDebugInformation(toConsole: ConnectionStrings.noConfiguredServers)
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
				printDebugInformation(toConsole: TransportSecurityStrings.enforcedPolicy(port: enforced.port))
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
		connectDelay = delay
		if afterWakeUp {
			autoConnectAfterWakeUp()
		} else {
			autoConnect()
		}
	}

	func autoConnect() {
		scheduleConnection(after: connectDelay, action: autoConnectPerformConnect)
	}

	func autoConnectPerformConnect() {
		guard isConnecting == false, isConnected == false else { return }
		connect()
	}

	func autoConnectAfterWakeUp() {
		if connectDelay > 0 {
			printDebugInformation(toConsole: ConnectionStrings.delayedAutoConnect(seconds: connectDelay))
		}
		scheduleConnection(after: connectDelay, action: autoConnectAfterWakeUpPerformConnect)
	}

	func autoConnectAfterWakeUpPerformConnect() {
		guard isConnecting == false, isConnected == false else { return }
		reconnectEnabledBecauseOfSleepMode = true
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
		readMarkerTimer.stop()
		readMarkerPendingChannels.removeAll()
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
		reconnectEnabled = false
		reconnectEnabledBecauseOfSleepMode = false
		stopReconnectTimer()
		output?.updateTitle(for: self)
	}

	func toggleAwayStatus(withComment comment: String?) {
		if userIsAway {
			toggleAwayStatus(false, withComment: nil)
		} else {
			toggleAwayStatus(
				true,
				withComment: comment?.isEmpty == false ? comment : ConnectionStrings.defaultAwayMessage
			)
		}
	}

	func toggleAwayStatus(_ setAway: Bool) {
		toggleAwayStatus(setAway, withComment: ConnectionStrings.defaultAwayMessage)
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
