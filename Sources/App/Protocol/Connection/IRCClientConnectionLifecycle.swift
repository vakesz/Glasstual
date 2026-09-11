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

struct PendingIRCEndpoint {
	enum Reason {
		case stsUpgrade
		case serverRedirect
		case userCommand
	}

	let host: String
	let port: UInt16
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
public extension IRCClient {
	func connect() {
		connect(.normal)
	}

	func connect(_ mode: IRCClientConnectMode) {
		connect(mode, bypassProxy: false)
	}

	func connect(_ mode: IRCClientConnectMode, bypassProxy: Bool) {
		guard isTerminating == false else { return }
		guard isConnecting == false, isConnected == false, isQuitting == false, isDisconnecting == false else {
			return
		}
		guard SystemInformation.systemIsSleeping == false else {
			connectionLifecycleLogger.info("Refusing to connect because the system is sleeping")
			return
		}
		let diagnostics = ConnectionDiagnostics()
		diagnostics.record(.requested)
		guard var socketConfig = takeConnectionEndpoint() else { return }
		socketConfig.diagnostics = diagnostics
		cancelConnectCommandSettling()
		connectType = mode
		disconnectType = .normal
		isConnecting = true
		stopReconnectTimer()
		reconnectEnabled = true
		output?.updateTitle(for: self)
		if mode == .reconnect {
			printDebugInformation(toConsole: IRCConnectionStrings.reconnecting)
		} else if mode == .retry {
			printDebugInformation(toConsole: IRCConnectionStrings.retrying)
		}
		if config.showConnectionPrefersIPv4Warning {
			printDebugInformation(IRCConnectionStrings.legacyIPv4PreferenceNotice)
		}
		printDebugInformation(toConsole: IRCConnectionStrings.connecting(
			host: socketConfig.serverAddress,
			port: socketConfig.serverPort
		))
		NotificationCenter.default.post(name: .IRCClientWillConnect, object: self)

		socketConfig.addressType = config.addressType
		socketConfig.cipherSuites = config.cipherSuites
		socketConfig.connectionShouldValidateCertificateChain = config.validateServerCertificateChain
		socketConfig.identityClientSideCertificate = config.identityClientSideCertificate
		if bypassProxy == false {
			socketConfig.proxyType = config.proxyType
			if socketConfig.proxyType == .socks5 || socketConfig.proxyType == .HTTP {
				socketConfig.proxyPort = config.proxyPort
				socketConfig.proxyAddress = config.proxyAddress
				socketConfig.proxyPassword = config.proxyPassword
				socketConfig.proxyUsername = config.proxyUsername
			}
		}
		socketConfig.floodControlDelayInterval = config.floodControlDelayTimerInterval
		socketConfig.floodControlMaximumMessages = config.floodControlMaximumMessages
		socketConfig.connectionPrefersModernCiphersOnly = environment.preferences.preferModernCiphers
		let connection = Connection(config: socketConfig, onClient: self)
		socket = connection
		connection.open()
	}

	internal func takeConnectionEndpoint() -> IRCConnectionConfig? {
		let servers = config.serverList
		guard servers.isEmpty == false else {
			printDebugInformation(toConsole: IRCConnectionStrings.noConfiguredServers)
			return nil
		}
		let endpoint = pendingEndpoint
		pendingEndpoint = nil
		var host = endpoint?.host ?? ""
		var port = endpoint?.port ?? IRCConnectionDefaults.serverPort
		var secured = endpoint?.reason == .stsUpgrade
		server = endpoint?.credentialEndpoint
		if (host as NSString).isValidInternetAddress == false {
			let nextIndex = lastServerSelected == UInt(NSNotFound) ? 0 : (lastServerSelected + 1) % UInt(servers.count)
			lastServerSelected = nextIndex
			let selected = servers[Int(nextIndex)]
			host = selected.serverAddress
			port = selected.serverPort
			secured = selected.prefersSecuredConnection
			server = selected
		}
		if let enforced = STSPolicyStore.shared.enforcedEndpoint(forHost: host) {
			if enforced.port != port || secured == false {
				printDebugInformation(toConsole: IRCTransportSecurityStrings.enforcedPolicy(port: enforced.port))
			}
			port = enforced.port
			secured = true
		}
		var connectionConfig = IRCConnectionConfig()
		connectionConfig.serverAddress = host
		connectionConfig.serverPort = port
		connectionConfig.connectionPrefersSecuredConnection = secured
		return connectionConfig
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
			printDebugInformation(toConsole: IRCConnectionStrings.delayedAutoConnect(seconds: connectDelay))
		}
		scheduleConnection(after: connectDelay, action: autoConnectAfterWakeUpPerformConnect)
	}

	func autoConnectAfterWakeUpPerformConnect() {
		guard isConnecting == false, isConnected == false else { return }
		reconnectEnabledBecauseOfSleepMode = true
		connect(.reconnect)
	}

	func disconnect() {
		cancelPendingSessionTasks()
		cancelDelayedDisconnect()
		guard isConnecting || isConnected, let socket else { return }
		isDisconnecting = true
		output?.updateTitle(for: self)
		NotificationCenter.default.post(name: .IRCClientWillDisconnect, object: self)
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
		cancelPendingSessionTasks()
		socket?.beginCloseDeadline()
		cancelReconnect()
		NotificationCenter.default.post(name: .IRCClientWillSendQuit, object: self)
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
		readMarkerTimer.stop()
		readMarkerPendingChannels.removeAll()
		resetSASLNegotiation()
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
				withComment: comment?.isEmpty == false ? comment : IRCConnectionStrings.defaultAwayMessage
			)
		}
	}

	func toggleAwayStatus(_ setAway: Bool) {
		toggleAwayStatus(setAway, withComment: IRCConnectionStrings.defaultAwayMessage)
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

	internal func setAwayForScreenSleep() {
		guard isLoggedIn, !userIsAway, lastAwayMessage == nil, !automaticallyAwayForScreenSleep else { return }
		toggleAwayStatus(true)
		automaticallyAwayForScreenSleep = true
	}

	internal func clearAwayAfterScreenSleep() {
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
