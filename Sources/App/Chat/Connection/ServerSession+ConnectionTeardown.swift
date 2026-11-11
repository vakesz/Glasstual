// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

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
		if let policy = activeSTSPolicy {
			activeSTSPolicy = nil
			_ = environment.services.stsPolicies.applyCapabilityValues(
				policy.values, forHost: policy.host, connectedPort: policy.port,
				secured: true, certificateChainValidated: true
			)
		}
		batchMessages.dequeueEntries()
		typingTracker.removeAll()
		typingSender.removeAll()

		nextLineReplyToMessageIdentifier = nil
		nextMessageReplyIdentifier = nil
		reconnect.connectDelay = 0
		invokingISONCommandForFirstTime = false
		cancelConnectCommandSettling()
		autojoin.delayedWarningCount = 0
		connectionState.clearTransport()
		isLoggedIn = false
		connectionState.clearShutdown()
		inWhoisResponse = false
		inWhowasResponse = false
		nickServ = NickServIdentification()
		registrationGate = .notStarted
		unprintedEchoes.removeAll()
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

		reconnect.clearBackoffIfRegistrationHeld(until: ProcessInfo.processInfo.systemUptime)
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
		if let attempt = lastSTSUpgradeAttempt {
			environment.services.stsPolicies.noteUpgradeSucceeded(host: attempt.host)
			lastSTSUpgradeAttempt = nil
		}
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
		if isLegacy {
			printDebugInformation(toConsole: String(localized: .IRC.connectionIsNotForwardSecret))
		}

		if registrationGate == .awaitingTLS {
			beginRegistration()
		}
	}

	func connectionDidConnect() {
		guard canContinueConnecting else {
			cancelReconnect()
			disconnect()
			return
		}

		startRetryTimer()
		if let connectedAddress = socket?.connectedAddress, socket?.config.serverAddress.isIPAddress == false {
			printDebugInformation(toConsole: String(localized: .IRC.connectionToHostAtEstablished(connectedAddress)))
		} else {
			printDebugInformation(toConsole: String(localized: .IRC.connectionToHostEstablished))
		}

		connectionState.didConnect()
		userNickname = config.nickname
		nicknameRetry.sentNickname = config.nickname
		output?.updateTitle(for: self)
		ServerSessionDidConnect(subject: self).post()

		/* A connection that is to be TLS registers once the handshake says
		 what stands behind the certificate: `PASS` waits on that, and the
		 lines after it wait on `PASS`. */
		if socket?.config.connectionPrefersSecuredConnection == true, isSecured == false {
			registrationGate = .awaitingTLS
			return
		}
		beginRegistration()
	}

	func connectionDidDisconnect(error disconnectError: Error?) {
		if let attempt = lastSTSUpgradeAttempt, disconnectError != nil, socket?.isSecured != true {
			environment.services.stsPolicies.noteUpgradeFailed(host: attempt.host, port: attempt.port)
			lastSTSUpgradeAttempt = nil
		} else if socket?.isSecured == true {
			lastSTSUpgradeAttempt = nil
		}
		changeStateOff(withError: disconnectError)
		invokeDisconnectCallbacks()
		ServerSessionDidDisconnect(subject: self).post()
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
		noteLabeledLineWritten(data)
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

		/* Only a connection that dropped is news: a quit or a disconnect the
		 person asked for, and the hop to another server, are what they just did. */
		if !isQuitting, !isDisconnecting, disconnectMode != .serverRedirect {
			environment.services.notifications?.announce(
				String(localized: .ChatNotifications.announcementDisconnected(networkNameAlt))
			)
		}
	}
}
