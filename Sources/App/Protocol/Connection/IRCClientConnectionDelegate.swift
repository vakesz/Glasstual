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
import Security

enum IRCClientDisconnectPolicy {
	static func shouldTransitionOff(isConnecting: Bool, isConnected: Bool) -> Bool {
		isConnecting || isConnected
	}

	static func effectiveMode(
		configured: IRCClientDisconnectMode,
		errorDomain: String?,
		errorCode: Int?
	) -> IRCClientDisconnectMode {
		guard errorDomain == connectionErrorDomain,
		      errorCode == Int(ConnectionErrorCode.badCertificate.rawValue)
		else { return configured }
		return .badCertificate
	}
}

enum IRCClientRegistrationPolicy {
	struct Values: Equatable {
		let username: String
		let realName: String
		let modeSymbols: String
	}

	static func values(
		nickname: String,
		username: String,
		realName: String,
		setInvisibleMode: Bool
	) -> Values {
		Values(
			username: username.isEmpty ? nickname : username,
			realName: realName.isEmpty ? nickname : realName,
			modeSymbols: setInvisibleMode ? "8" : "0"
		)
	}
}

@MainActor
public extension IRCClient {
	func resetAllPropertyValues() {
		batchMessages.dequeueEntries()
		typingTracker.removeAll()
		typingStateSent.removeAll()
		typingActiveSentAt.removeAll()
		typingPauseTasks.values.forEach { $0.cancel() }
		typingPauseTasks.removeAll()

		nextLineReplyToMessageIdentifier = nil
		nextMessageReplyIdentifier = nil
		connectDelay = 0
		invokingISONCommandForFirstTime = false
		isAutojoining = false
		isAutojoined = false
		autojoinDelayedWarningCount = 0
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
		isConnectedToZNC = false
		zncBouncerIsSendingCertificateInfo = false
		zncBouncerCertificateChainDataMutable = nil
		zncBouncerIsPlayingBackHistory = false

		resetChatHistoryState()
		reconnectEnabled = false
		timeoutWarningShownToUser = false
		lastWhoRequestChannelListIndex = 0
		server = nil
		retiredServerKeychainItems.forEach { $0.delete() }
		retiredServerKeychainItems.removeAll()
		userHostmask = nil
		forgetUserNickname()
		tryingNicknameNumber = 0
		tryingNicknameSentNickname = nil
		preAwayUserNickname = nil
		lastMessageReceived = 0

		resetCapabilityNegotiation()
		removeAllUsers()
	}

	func changeStateOff() {
		changeStateOff(withError: nil)
	}

	func changeStateOff(withError disconnectError: Error?) {
		guard IRCClientDisconnectPolicy.shouldTransitionOff(
			isConnecting: isConnecting,
			isConnected: isConnected
		) else { return }

		let terminating = isTerminating
		socket = nil
		removeTimedCommands()
		removeRequestedCommands()
		stopAutojoinTimer()
		stopAutojoinNextJoinTimer()
		stopAutojoinDelayedWarningTimer()
		stopISONTimer()
		stopPongTimer()
		stopRetryTimer()
		cancelDelayedDisconnect()
		cancelScheduledConnection()

		if !terminating, reconnectEnabled {
			startReconnectTimer()
		}

		supportInfo.reset()
		clearAddressBookCache()
		clearTrackedUsers()

		if !terminating {
			logController?.cancelRenderJobs()
			presentDisconnect(disconnectError)
		}

		endLoggingSessions()
		resetAllPropertyValues()

		if !terminating, let output {
			output.reloadTreeGroup(self)
			output.updateTitle(for: self)
		}
	}

	func ircConnection(_ sender: Connection, willConnectToProxy proxyHost: String, port proxyPort: UInt16) {
		precondition(sender === socket)
		switch sender.config.proxyType {
		case .socks5, .tor:
			printDebugInformation(toConsole: IRCConnectionStrings.socksProxy(host: proxyHost, port: proxyPort))
		case .HTTP:
			printDebugInformation(toConsole: IRCConnectionStrings.httpProxy(host: proxyHost, port: proxyPort))
		default:
			break
		}
	}

	func ircConnectionDidSecureConnection(
		_ sender: Connection,
		withProtocolType protocolType: tls_protocol_version_t,
		cipherSuite: tls_ciphersuite_t
	) {
		precondition(sender === socket)
		performedSTSUpgrade = false
		guard let protocolDescription = SecureTransportSupport.description(forProtocolType: protocolType),
		      let cipherDescription = SecureTransportSupport.description(forCipherSuite: cipherSuite)
		else { return }

		let description = IRCConnectionStrings.cipherSuite(
			protocolName: protocolDescription,
			cipherName: cipherDescription,
			deprecated: SecureTransportSupport.isCipherSuiteDeprecated(cipherSuite)
		)
		printDebugInformation(toConsole: IRCConnectionStrings.secured(using: description))
	}

	func ircConnectionDidConnect(_ sender: Connection) {
		precondition(sender === socket)
		guard !isTerminating else { return }

		startRetryTimer()
		if let connectedAddress = sender.connectedAddress, !sender.config.serverAddress.isIPAddress {
			printDebugInformation(toConsole: IRCConnectionStrings.hostConnectionEstablished(address: connectedAddress))
		} else {
			printDebugInformation(toConsole: IRCConnectionStrings.hostConnectionEstablished)
		}

		isConnecting = false
		isConnected = true
		userNickname = config.nickname
		tryingNicknameSentNickname = config.nickname
		output?.updateTitle(for: self)
		NotificationCenter.default.post(name: .IRCClientDidConnect, object: self)

		let registration = IRCClientRegistrationPolicy.values(
			nickname: config.nickname,
			username: config.username,
			realName: config.realName,
			setInvisibleMode: config.setInvisibleModeOnConnect
		)
		sendCapability("LS", data: "302")
		if let password = server?.serverPassword {
			sendPassword(password)
		}
		changeNickname(config.nickname)
		send("USER", arguments: [registration.username, registration.modeSymbols, "*", registration.realName])
	}

	func ircConnection(_ sender: Connection, didDisconnectWithError disconnectError: Error?) {
		precondition(sender === socket)
		changeStateOff(withError: disconnectError)
		invokeDisconnectCallbacks()
		NotificationCenter.default.post(name: .IRCClientDidDisconnect, object: self)
	}

	func ircConnectionDidCloseReadStream(_ sender: Connection) {
		precondition(sender === socket)
		guard !isTerminating, !isDisconnecting else { return }
		if isQuitting {
			disconnect()
			return
		}
		printDebugInformation(toConsole: IRCConnectionStrings.serverClosedReadStream)
	}

	func ircConnection(_ sender: Connection, willSendData data: String) {
		precondition(sender === socket)
		guard !isTerminating else { return }
		rawDataLogOutgoingTraffic(data)
	}
}

@MainActor
private extension IRCClient {
	func presentDisconnect(_ disconnectError: Error?) {
		let nsError = disconnectError as NSError?
		let disconnectMode = IRCClientDisconnectPolicy.effectiveMode(
			configured: disconnectType,
			errorDomain: nsError?.domain,
			errorCode: nsError?.code
		)

		if let disconnectError {
			printError(disconnectError.localizedDescription, asCommand: TVCLogLineDefaultCommandValue)
		}

		let disconnectMessage = IRCConnectionStrings.disconnectReason(for: disconnectMode)
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
		if isConnected {
			_ = notifyEvent(.disconnect, lineType: .debug)
		}
		postEvent(toViewController: "serverDisconnected")
	}
}
