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
import os
import SecurityInterface

private let connectionLogger = Logger(
	subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
	category: "IRCConnection"
)

/** NSXPC transports the response block across its private queue. The wrapper is
 immutable, and the callback is invoked only by RCMTrustPanel on the main thread. */
private final class TrustResponse: @unchecked Sendable {
	let callback: RCMTrustResponse

	init(_ callback: @escaping RCMTrustResponse) {
		self.callback = callback
	}
}

/** Security.framework does not annotate SecTrust as Sendable. Ownership is
 transferred unchanged to RCMTrustPanel and the value is not touched again. */
private struct TrustReference: @unchecked Sendable {
	let value: SecTrust
}

/** IRCClient calls this type on the main thread. NSXPC callbacks immediately
 transfer mutable application state to the main queue before touching it. */
@objc(IRCConnection)
public final class Connection: NSObject, RCMConnectionManagerClientProtocol, @unchecked Sendable {
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
	private var trustPanelDoNotInvokeCompletionBlock = false
	private var connectionInvalidatedVoluntarily = false

	@available(*, unavailable)
	override public init() {
		fatalError("init() is unavailable; use init(config:onClient:)")
	}

	@objc(initWithConfig:onClient:)
	public init(config: IRCConnectionConfig, onClient client: IRCClient) {
		self.client = client
		self.config = config.copy() as! IRCConnectionConfig
		uniqueIdentifier = NSString.withUUID()
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
		connection.remoteObjectInterface = NSXPCInterface(with: RCMConnectionManagerServerProtocol.self)
		connection.exportedInterface = NSXPCInterface(with: RCMConnectionManagerClientProtocol.self)
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
		XRPerformBlockSynchronouslyOnMainQueue { [weak self] in
			guard let self else { return }
			serviceConnection = nil

			if isConnecting || isConnected, connectionInvalidatedVoluntarily == false {
				let error = NSError(
					domain: ConnectionErrorDomain,
					code: Int(ConnectionErrorCode.other.rawValue),
					userInfo: [NSLocalizedDescriptionKey: LocalizedKey("IRC[vdy-jk]")]
				)
				didDisconnect(with: error)
			}

			resetState()
		}
	}

	private func remoteObjectProxy(
		errorHandler: ((Error) -> Void)? = nil
	) -> RCMConnectionManagerServerProtocol? {
		serviceConnection?.remoteObjectProxyWithErrorHandler { error in
			connectionLogger.error("IRC connection service error: \(error.localizedDescription, privacy: .public)")
			errorHandler?(error)
		} as? RCMConnectionManagerServerProtocol
	}

	@objc public func open() {
		guard isConnecting == false, isConnected == false, isDisconnecting == false else { return }
		warmProcessIfNeeded()
		isConnecting = true
		remoteObjectProxy()?.open(with: config)

		if TPCPreferences.appNapEnabled() == false {
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
			guard let policyName,
			      let trust = RCMSecureTransport.trust(
			      	fromCertificateChain: certificateChain,
			      	withPolicyName: policyName
			      ),
			      let protocolDescription = RCMSecureTransport.description(forProtocolType: protocolType),
			      let cipherDescription = RCMSecureTransport.description(forCipherSuite: cipherSuite)
			else { return }

			let summaryKey = RCMSecureTransport.isCipherSuiteDeprecated(cipherSuite) ? "Prompts[8ou-pu]" : "Prompts[2jq-t5]"
			let summary = LocalizedKey(summaryKey, protocolDescription, cipherDescription)
			var body = LocalizedKey("Prompts[iun-45]", policyName, summary)
			let trustReference = TrustReference(value: trust)
			if let failure {
				body += LocalizedKey("Prompts[k3t-vq]", failure)
			}

			XRPerformBlockSynchronouslyOnMainQueue {
				MainActor.assumeIsolated {
					_ = RCMTrustPanel.present(
						inWindow: NSApp.keyWindow,
						body: body,
						title: LocalizedKey("Prompts[sfx-xx]", policyName),
						defaultButton: LocalizedKey("Prompts[aqw-q1]"),
						alternateButton: nil,
						trustRef: trustReference.value
					) { _, _, _ in }
				}
			}
		}
	}

	private func openInsecureCertificateTrustPanel(_ response: @escaping RCMTrustResponse) {
		guard trustPanel == nil else { return }
		let response = TrustResponse(response)

		exportSecureConnectionInformation { [weak self] policyName, _, _, certificateChain, _ in
			guard let self, let policyName,
			      let trust = RCMSecureTransport.trust(
			      	fromCertificateChain: certificateChain,
			      	withPolicyName: policyName
			      )
			else { return }
			let trustReference = TrustReference(value: trust)

			XRPerformBlockSynchronouslyOnMainQueue {
				MainActor.assumeIsolated {
					trustPanel = RCMTrustPanel.present(
						inWindow: nil,
						body: LocalizedKey("Prompts[85z-qw]", policyName),
						title: LocalizedKey("Prompts[m8b-58]", policyName),
						defaultButton: LocalizedKey("Prompts[zjw-bd]"),
						alternateButton: LocalizedKey("Prompts[qso-2g]"),
						trustRef: trustReference.value,
						completionBlock: { [weak self] _, trusted, _ in
							MainActor.assumeIsolated {
								guard let self else { return }
								self.trustPanel = nil
								if self.trustPanelDoNotInvokeCompletionBlock {
									self.trustPanelDoNotInvokeCompletionBlock = false
									return
								}
								response.callback(trusted)
							}
						},
						contextInfo: nil
					)
				}
			}
		}
	}

	private func closeInsecureCertificateTrustPanel() {
		guard let trustPanel else { return }
		trustPanelDoNotInvokeCompletionBlock = true

		XRPerformBlockSynchronouslyOnMainQueue {
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
				self.trustPanel = nil
			}
		}
	}

	private func exportSecureConnectionInformation(_ receiver: @escaping RCMSecureConnectionInformationCompletionBlock) {
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
		XRPerformBlockSynchronouslyOnMainQueue { [weak self] in
			guard let self else { return }
			client.ircConnection(self, willConnectToProxy: proxyHost, port: proxyPort)
		}
	}

	public func ircConnectionDidConnect(toHost host: String?) {
		XRPerformBlockSynchronouslyOnMainQueue { [weak self] in
			guard let self else { return }
			connectedAddress = host
			isConnecting = false
			isConnected = true
			client.ircConnectionDidConnect(self)
		}
	}

	public func ircConnectionDidSecureConnection(
		withProtocolType protocolType: tls_protocol_version_t,
		cipherSuite: tls_ciphersuite_t
	) {
		XRPerformBlockSynchronouslyOnMainQueue { [weak self] in
			guard let self else { return }
			isSecured = true
			isConnectedWithClientSideCertificate = config.identityClientSideCertificate != nil
			client.ircConnectionDidSecureConnection(self, withProtocolType: protocolType, cipherSuite: cipherSuite)
		}
	}

	public func ircConnectionDidCloseReadStream() {
		XRPerformBlockSynchronouslyOnMainQueue { [weak self] in
			guard let self else { return }
			EOFReceived = true
			client.ircConnectionDidCloseReadStream(self)
		}
	}

	public func ircConnectionDidDisconnectWithError(_ disconnectError: Error?) {
		XRPerformBlockSynchronouslyOnMainQueue { [weak self] in
			guard let self else { return }
			connectionInvalidatedVoluntarily = true
			invalidateProcess()
			didDisconnect(with: disconnectError)
		}
	}

	private func didDisconnect(with error: Error?) {
		XRPerformBlockSynchronouslyOnMainQueue { [weak self] in
			guard let self else { return }
			closeInsecureCertificateTrustPanel()
			client.ircConnection(self, didDisconnectWithError: error)
		}
	}

	public func ircConnectionDidReceive(_ data: Data) {
		guard let string = convertFromCommonEncoding(data) else { return }
		client.ircConnection(self, didReceiveData: string)
	}

	public func ircConnectionRequestInsecureCertificateTrust(_ trustBlock: @escaping RCMTrustResponse) {
		XRPerformBlockSynchronouslyOnMainQueue { [weak self] in
			self?.openInsecureCertificateTrustPanel(trustBlock)
		}
	}

	public func ircConnectionWillSend(_ data: Data) {
		XRPerformBlockSynchronouslyOnMainQueue { [weak self] in
			guard let self, let string = convertFromCommonEncoding(data) else { return }
			client.ircConnection(self, willSendData: string)
		}
	}

	public func ircConnectionDidSendData() {
		XRPerformBlockSynchronouslyOnMainQueue { [weak self] in
			self?.isSending = false
		}
	}
}
