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

@MainActor
public extension IRCClient {
	func connect() {
		connect(.normal)
	}

	func connect(_ mode: IRCClientConnectMode) {
		connect(mode, bypassProxy: false)
	}

	func connect(_ mode: IRCClientConnectMode, bypassProxy: Bool) {
		guard isConnecting == false, isConnected == false, isQuitting == false, isDisconnecting == false else {
			return
		}
		guard SystemInformation.systemIsSleeping == false else {
			connectionLifecycleLogger.info("Refusing to connect because the system is sleeping")
			return
		}
		let servers = config.serverList
		guard servers.isEmpty == false else {
			printDebugInformation(toConsole: IRCConnectionStrings.noConfiguredServers)
			return
		}

		var serverAddress = temporaryServerAddressOverride ?? ""
		var serverPort = temporaryServerPortOverride > 0 ? temporaryServerPortOverride : UInt16(6667)
		var prefersSecuredConnection = false
		if (serverAddress as NSString).isValidInternetAddress == false {
			let nextIndex = lastServerSelected == UInt(NSNotFound) ? 0 : (lastServerSelected + 1) % UInt(servers.count)
			lastServerSelected = nextIndex
			let selectedServer = servers[Int(nextIndex)]
			serverAddress = selectedServer.serverAddress
			serverPort = selectedServer.serverPort
			prefersSecuredConnection = selectedServer.prefersSecuredConnection
			server = selectedServer
		}
		temporaryServerAddressOverride = nil
		temporaryServerPortOverride = 0

		if let enforced = STSPolicyStore.shared.enforcedEndpoint(forHost: serverAddress) {
			if enforced.port != serverPort || prefersSecuredConnection == false {
				printDebugInformation(toConsole: IRCTransportSecurityStrings.enforcedPolicy(port: enforced.port))
			}
			serverPort = enforced.port
			prefersSecuredConnection = true
		}
		if forceSecuredConnectionOnNextConnect {
			forceSecuredConnectionOnNextConnect = false
			prefersSecuredConnection = true
		}

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
		printDebugInformation(toConsole: IRCConnectionStrings.connecting(host: serverAddress, port: serverPort))
		NotificationCenter.default.post(name: .IRCClientWillConnect, object: self)

		var socketConfig = IRCConnectionConfig()
		socketConfig.addressType = config.addressType
		socketConfig.serverAddress = serverAddress
		socketConfig.serverPort = serverPort
		socketConfig.cipherSuites = config.cipherSuites
		socketConfig.connectionPrefersSecuredConnection = prefersSecuredConnection
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
		postEvent(toViewController: "serverConnecting")
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
		cancelDelayedDisconnect()
		guard isConnecting || isConnected, let socket else { return }
		isDisconnecting = true
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
		cancelReconnect()
		if isTerminating == false {
			postEvent(toViewController: "serverDisconnecting")
		}
		NotificationCenter.default.post(name: .IRCClientWillSendQuit, object: self)
		socket?.clearSendQueue()
		guard isLoggedIn else {
			disconnect()
			return
		}
		send("QUIT", arguments: [comment])

		/* Held so that a reconnect inside the two-second window cannot have this
		 stale block tear down the *new* session. */
		pendingDisconnectTask = Task { [weak self] in
			try? await Task.sleep(for: .seconds(2))

			guard Task.isCancelled == false, let self else { return }

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

	func cancelReconnect() {
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
		guard isLoggedIn, setAway == false || comment != nil else { return }
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

	func presentCertificateTrustInformation() {
		guard isSecured else { return }
		socket?.openSecuredConnectionCertificateModal()
	}

	private func scheduleConnection(after delay: UInt, action: @escaping @MainActor () -> Void) {
		cancelScheduledConnection()

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
