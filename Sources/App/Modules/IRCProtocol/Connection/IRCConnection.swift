/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\\_\\__|\\__,_|\\__,_|_|
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

import AppKit
import CocoaExtensions
import os
import Security
import SecurityInterface

private let connectionLogger = Logger(
	subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
	category: "IRCConnection"
)

/** NSXPC transports the response block across its private queue. The wrapper is
 immutable, and the callback is invoked only by TrustPanelPresenter on the main thread. */
private final class TrustResponseBox: @unchecked Sendable {
	let callback: TrustDecisionHandler

	init(_ callback: @escaping TrustDecisionHandler) {
		self.callback = callback
	}
}

/** Security.framework does not annotate SecTrust as Sendable. Ownership is
 transferred unchanged to TrustPanelPresenter and the value is not touched again. */
private struct TrustReference: @unchecked Sendable {
	let value: SecTrust
}

public protocol ConnectionDelegate: AnyObject {
	func ircConnection(_ sender: Connection, willConnectToProxy proxyHost: String, port proxyPort: UInt16)

	func ircConnectionDidConnect(_ sender: Connection)

	func ircConnectionDidSecureConnection(
		_ sender: Connection,
		withProtocolType protocolType: tls_protocol_version_t,
		cipherSuite: tls_ciphersuite_t
	)

	func ircConnectionDidCloseReadStream(_ sender: Connection)

	func ircConnection(_ sender: Connection, didDisconnectWithError disconnectError: Error?)

	func ircConnection(_ sender: Connection, didReceiveData data: String)

	func ircConnection(_ sender: Connection, willSendData data: String)
}

/** IRCClient calls this type on the main thread. NSXPC callbacks immediately
 transfer mutable application state to the main queue before touching it. */
@objc(IRCConnection)
public final class Connection: NSObject, RemoteConnectionClientProtocol, @unchecked Sendable {
	@objc public private(set) weak var client: IRCClient!
	@objc public private(set) var config: IRCConnectionConfig
	@objc public private(set) var isConnected = false
	@objc public private(set) var isConnectedWithClientSideCertificate = false
	@objc public private(set) var isConnecting = false
	@objc public private(set) var isDisconnecting = false
	@objc public private(set) var isSecured = false
	@objc public private(set) var isSending = false
	@objc public private(set) var EOFReceived = false
	@objc public private(set) var connectedAddress: String?
	@objc public private(set) var uniqueIdentifier: String

	private var serviceConnection: NSXPCConnection?
	private var trustPanel: SFCertificateTrustPanel?
	/** `trustPanel` is only assigned once the asynchronous certificate export lands, so it
	 cannot gate re-entry on its own. This latch is set synchronously on the main queue. */
	private var trustPanelIsPresenting = false
	private var trustPanelDoNotInvokeCompletionBlock = false
	private var connectionInvalidatedVoluntarily = false

	@available(*, unavailable)
	override public init() {
		fatalError("init() is unavailable; use init(config:onClient:)")
	}

	@objc(initWithConfig:onClient:)
	public init(config: IRCConnectionConfig, onClient client: IRCClient) {
		guard let configCopy = config.copy() as? IRCConnectionConfig else {
			preconditionFailure("IRCConnectionConfig.copy() returned an unexpected type")
		}
		self.client = client
		self.config = configCopy
		uniqueIdentifier = UUID().uuidString
		super.init()
	}

	@objc public func resetState() {
		isConnecting = false
		isConnected = false
		isConnectedWithClientSideCertificate = false
		isDisconnecting = false
		EOFReceived = false
		isSecured = false
		isSending = false
		connectedAddress = nil
		connectionInvalidatedVoluntarily = false
	}

	private func invalidateProcess() {
		guard let serviceConnection else { return }
		connectionLogger.debug("Invalidating IRC connection service")
		serviceConnection.invalidate()
	}

	private func warmProcessIfNeeded() {
		guard serviceConnection == nil else { return }
		warmProcess()
	}

	private func warmProcess() {
		connectionLogger.debug("Warming IRC connection service")
		let connection = NSXPCConnection(serviceName: "com.vakesz.glasstual.IRCConnectionHost")
		connection.remoteObjectInterface = NSXPCInterface(with: RemoteConnectionServerProtocol.self)
		connection.exportedInterface = NSXPCInterface(with: RemoteConnectionClientProtocol.self)
		connection.exportedObject = self
		connection.interruptionHandler = { [weak self] in
			self?.interruptionHandler()
			connectionLogger.info("IRC connection service interrupted")
		}
		connection.invalidationHandler = { [weak self] in
			self?.invalidationHandler()
			connectionLogger.info("IRC connection service invalidated")
		}
		connection.resume()
		serviceConnection = connection
	}

	private func interruptionHandler() {
		invalidateProcess()
	}

	private func invalidationHandler() {
		performSynchronouslyOnMainQueue { [weak self] in
			guard let self else { return }
			serviceConnection = nil

			if isConnecting || isConnected, connectionInvalidatedVoluntarily == false {
				let error = NSError(
					domain: connectionErrorDomain,
					code: Int(ConnectionErrorCode.other.rawValue),
					userInfo: [NSLocalizedDescriptionKey: IRCConnectionStrings.serviceClosedUnexpectedly]
				)
				didDisconnect(with: error)
			}

			resetState()
		}
	}

	private func remoteObjectProxy(
		errorHandler: ((Error) -> Void)? = nil
	) -> RemoteConnectionServerProtocol? {
		serviceConnection?.remoteObjectProxyWithErrorHandler { error in
			connectionLogger.error("IRC connection service error: \(error.localizedDescription, privacy: .public)")
			errorHandler?(error)
		} as? RemoteConnectionServerProtocol
	}

	@objc public func open() {
		guard isConnecting == false, isConnected == false, isDisconnecting == false else { return }
		warmProcessIfNeeded()
		isConnecting = true
		remoteObjectProxy()?.open(with: config)

		if TextualPreferences.appNapEnabled() == false {
			remoteObjectProxy()?.disableAppNap()
		}

		remoteObjectProxy()?.disableSuddenTermination()
	}

	@objc public func close() {
		guard isDisconnecting == false else { return }

		if isConnecting || isConnected {
			isDisconnecting = true
			remoteObjectProxy()?.close()
		} else {
			invalidateProcess()
		}
	}

	@objc public func enforceFloodControl() {
		guard isConnected else { return }
		remoteObjectProxy()?.enforceFloodControl()
	}

	@objc public func openSecuredConnectionCertificateModal() {
		exportSecureConnectionInformation { policyName, protocolType, cipherSuite, certificateChain, failure in
			guard
				let policyName,
				let trust = SecureTransportSupport.trust(
					fromCertificateChain: certificateChain,
					policyName: policyName
				),
				let protocolDescription = SecureTransportSupport.description(forProtocolType: protocolType),
				let cipherDescription = SecureTransportSupport.description(forCipherSuite: cipherSuite)
			else { return }

			let cipherStatus: PromptCipherStatus = SecureTransportSupport.isCipherSuiteDeprecated(cipherSuite)
				? .deprecated
				: .current
			let summary = PromptStrings.TransportSecurity.cipherSummary(
				policyName: protocolDescription,
				cipherSuite: cipherDescription,
				status: cipherStatus
			)
			var body = PromptStrings.TransportSecurity.certificateSummary(
				policyName: policyName,
				cipherSummary: summary
			)
			let trustReference = TrustReference(value: trust)
			if let failure {
				body += PromptStrings.TransportSecurity.trustFailure(failure)
			}

			performSynchronouslyOnMainQueue {
				MainActor.assumeIsolated {
					_ = TrustPanelPresenter.present(
						in: NSApp.keyWindow,
						body: body,
						title: PromptStrings.TransportSecurity.encryptedConnectionTitle(policyName: policyName),
						defaultButton: PromptStrings.Action.close,
						alternateButton: nil,
						trust: trustReference.value
					) { _, _, _ in }
				}
			}
		}
	}

	private func openInsecureCertificateTrustPanel(_ response: @escaping TrustDecisionHandler) {
		guard trustPanelIsPresenting == false else {
			/* The connection host blocks its handshake until this reply arrives. */
			response(false)
			return
		}
		trustPanelIsPresenting = true
		let response = TrustResponseBox(response)

		exportSecureConnectionInformation { [weak self] policyName, _, _, certificateChain, _ in
			guard
				let self,
				let policyName,
				let trust = SecureTransportSupport.trust(
					fromCertificateChain: certificateChain,
					policyName: policyName
				)
			else {
				performSynchronouslyOnMainQueue {
					self?.trustPanelIsPresenting = false
				}
				response.callback(false)
				return
			}
			let trustReference = TrustReference(value: trust)

			performSynchronouslyOnMainQueue {
				MainActor.assumeIsolated {
					trustPanel = TrustPanelPresenter.present(
						in: nil,
						body: PromptStrings.TransportSecurity.certificateFailureBody(serverName: policyName),
						title: PromptStrings.TransportSecurity.certificateFailureTitle(serverName: policyName),
						defaultButton: PromptStrings.TransportSecurity.invalidCertificateContinueButtonTitle,
						alternateButton: PromptStrings.Action.cancel,
						trust: trustReference.value,
						completion: { [weak self] _, trusted, _ in
							MainActor.assumeIsolated {
								guard let self else {
									response.callback(false)
									return
								}
								self.trustPanel = nil
								self.trustPanelIsPresenting = false
								if self.trustPanelDoNotInvokeCompletionBlock {
									self.trustPanelDoNotInvokeCompletionBlock = false
									return
								}
								response.callback(trusted)
							}
						},
						context: nil
					)
				}
			}
		}
	}

	private func closeInsecureCertificateTrustPanel() {
		guard let trustPanel else { return }
		trustPanelDoNotInvokeCompletionBlock = true

		performSynchronouslyOnMainQueue {
			MainActor.assumeIsolated {
				if let parent = trustPanel.sheetParent {
					parent.endSheet(trustPanel, returnCode: .cancel)
					return
				}

				if NSApp.modalWindow === trustPanel {
					NSApp.stopModal(withCode: .cancel)
					return
				}

				trustPanel.orderOut(nil)
				trustPanelDoNotInvokeCompletionBlock = false
				trustPanelIsPresenting = false
				self.trustPanel = nil
			}
		}
	}

	private func exportSecureConnectionInformation(_ receiver: @escaping SecureConnectionInformationReceiver) {
		remoteObjectProxy()?.exportSecureConnectionInformation(receiver)
	}

	private func convertFromCommonEncoding(_ data: Data) -> String? {
		client.convert(fromCommonEncoding: data)
	}

	private func convertToCommonEncoding(_ string: String) -> Data? {
		client.convert(toCommonEncoding: string)
	}

	@objc(sendLine:)
	public func sendLine(_ line: String) {
		let cleanLine = line
			.replacingOccurrences(of: "\r", with: "")
			.replacingOccurrences(of: "\n", with: "") + "\r\n"

		guard let data = convertToCommonEncoding(cleanLine) else { return }
		isSending = true

		if cleanLine.hasPrefix("PONG") {
			remoteObjectProxy()?.send(data, bypassQueue: true)
		} else {
			remoteObjectProxy()?.send(data)
		}
	}

	@objc public func clearSendQueue() {
		remoteObjectProxy()?.clearSendQueue()
	}

	public func ircConnectionWillConnect(toProxy proxyHost: String, port proxyPort: UInt16) {
		performSynchronouslyOnMainQueue { [weak self] in
			guard let self else { return }
			MainActor.assumeIsolated {
				client.ircConnection(self, willConnectToProxy: proxyHost, port: proxyPort)
			}
		}
	}

	public func ircConnectionDidConnect(toHost host: String?) {
		performSynchronouslyOnMainQueue { [weak self] in
			guard let self else { return }
			connectedAddress = host
			isConnecting = false
			isConnected = true
			MainActor.assumeIsolated {
				client.ircConnectionDidConnect(self)
			}
		}
	}

	public func ircConnectionDidSecureConnection(
		withProtocolType protocolType: tls_protocol_version_t,
		cipherSuite: tls_ciphersuite_t
	) {
		performSynchronouslyOnMainQueue { [weak self] in
			guard let self else { return }
			isSecured = true
			isConnectedWithClientSideCertificate = config.identityClientSideCertificate != nil
			MainActor.assumeIsolated {
				client.ircConnectionDidSecureConnection(
					self,
					withProtocolType: protocolType,
					cipherSuite: cipherSuite
				)
			}
		}
	}

	public func ircConnectionDidCloseReadStream() {
		performSynchronouslyOnMainQueue { [weak self] in
			guard let self else { return }
			EOFReceived = true
			MainActor.assumeIsolated {
				client.ircConnectionDidCloseReadStream(self)
			}
		}
	}

	public func ircConnectionDidDisconnectWithError(_ disconnectError: Error?) {
		performSynchronouslyOnMainQueue { [weak self] in
			guard let self else { return }
			connectionInvalidatedVoluntarily = true
			invalidateProcess()
			didDisconnect(with: disconnectError)
		}
	}

	private func didDisconnect(with error: Error?) {
		performSynchronouslyOnMainQueue { [weak self] in
			guard let self else { return }
			closeInsecureCertificateTrustPanel()
			MainActor.assumeIsolated {
				client.ircConnection(self, didDisconnectWithError: error)
			}
		}
	}

	public func ircConnectionDidReceive(_ data: Data) {
		/* Decoding reads client.config and client.supportInfo, and the client's state is
		 only safe to touch on the main queue, so hop first like the sibling callbacks. */
		performSynchronouslyOnMainQueue { [weak self] in
			guard let self, let string = convertFromCommonEncoding(data) else { return }
			MainActor.assumeIsolated {
				client.ircConnection(self, didReceiveData: string)
			}
		}
	}

	public func ircConnectionRequestInsecureCertificateTrust(_ trustBlock: @escaping TrustDecisionHandler) {
		performSynchronouslyOnMainQueue { [weak self] in
			self?.openInsecureCertificateTrustPanel(trustBlock)
		}
	}

	public func ircConnectionWillSend(_ data: Data) {
		performSynchronouslyOnMainQueue { [weak self] in
			guard let self, let string = convertFromCommonEncoding(data) else { return }
			MainActor.assumeIsolated {
				client.ircConnection(self, willSendData: string)
			}
		}
	}

	public func ircConnectionDidSendData() {
		performSynchronouslyOnMainQueue { [weak self] in
			self?.isSending = false
		}
	}
}
