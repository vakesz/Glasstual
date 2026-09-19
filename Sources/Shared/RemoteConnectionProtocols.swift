// Copyright (c) 2017, 2020 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
import Security

typealias SecureConnectionInformationReceiver = @Sendable (SecureConnectionInformation) -> Void

/** Commands the application sends to the isolated connection host.

 `Sendable` because both ends already are: what the application holds is an
 NSXPC proxy, and what the service exports is a forwarding shim whose only
 state is the queue it hands the commands to. Saying so lets a caller pass
 the connection between tasks without the compiler having to take it on
 trust.

 Every selector here and on ``RemoteConnectionClientProtocol`` is spelled out,
 and every one is prefixed `remoteConnection`: Objective-C selectors share one
 namespace, and `close`, `sendData:` or `didSendData` on a conformer that is
 also an `NSObject` are names something else can plausibly answer to already. */
@objc(RemoteConnectionServerProtocol)
nonisolated protocol RemoteConnectionServerProtocol: AnyObject, Sendable { // nonisolated: xpc-shim
	@objc(remoteConnectionOpenWithConfig:)
	func open(with config: ConnectionConfigEnvelope)

	@objc(remoteConnectionClose)
	func close()

	/// The caller includes the IRC line terminator in `data`.
	@objc(remoteConnectionSendData:)
	func send(_ data: Data)

	@objc(remoteConnectionSendData:bypassQueue:)
	func send(_ data: Data, bypassQueue: Bool)

	/// The receiver is an XPC reply block: the service answers it once, and it
	/// may answer after this call has returned.
	@objc(remoteConnectionExportSecureConnectionInformation:)
	func exportSecureConnectionInformation(_ receiver: @escaping SecureConnectionInformationReceiver)

	@objc(remoteConnectionEnforceFloodControl)
	func enforceFloodControl()

	@objc(remoteConnectionClearSendQueue)
	func clearSendQueue()

	/// Held until the connection ends: the host balances it when the
	/// application detaches, so there is no enabling half to call.
	@objc(remoteConnectionDisableAppNap)
	func disableAppNap()

	/// Held until the connection ends, balanced the same way as ``disableAppNap()``.
	@objc(remoteConnectionDisableSuddenTermination)
	func disableSuddenTermination()
}

/// Events the isolated connection host sends back to the application.
@objc(RemoteConnectionClientProtocol)
nonisolated protocol RemoteConnectionClientProtocol: AnyObject, Sendable { // nonisolated: xpc-shim
	@objc(remoteConnectionWillConnectToProxy:port:)
	func willConnect(toProxy proxyHost: String, port proxyPort: UInt16)

	@objc(remoteConnectionDidConnectToHost:)
	func didConnect(toHost host: String?)

	@objc(remoteConnectionDidSecureConnectionWithProtocolType:cipherSuite:)
	func didSecureConnection(
		withProtocolType protocolType: tls_protocol_version_t,
		cipherSuite: tls_ciphersuite_t
	)

	@objc(remoteConnectionDidCloseReadStream)
	func didCloseReadStream()

	@objc(remoteConnectionDidDisconnectWithError:)
	func didDisconnect(withError disconnectError: Error?)

	/** The complete lines one read from the server produced, in wire order.

	 `acknowledge` is an XPC reply block, and it is the flow control: the host
	 reads nothing more from the socket until the application has handled these
	 lines and answered. A server that sends faster than the application can
	 keep up is slowed by TCP rather than filling a queue between the two
	 processes, so no amount of traffic can overrun the application. */
	@objc(remoteConnectionDidReceiveLines:acknowledge:)
	func didReceive(_ lines: [Data], acknowledge: @escaping @Sendable () -> Void)

	@objc(remoteConnectionRequestInsecureCertificateTrust:)
	func requestInsecureCertificateTrust(_ response: @escaping TrustDecisionHandler)

	@objc(remoteConnectionWillSendData:)
	func willSend(_ data: Data)

	@objc(remoteConnectionDidSendData)
	func didSendData()
}

/// The interfaces both ends of the connection host speak.
///
/// Built in one place because a collection argument is only decoded for the
/// classes its interface names: an interface assembled by hand on either side
/// without them refuses every received line.
nonisolated enum RemoteConnectionInterface {
	/// What the application calls on the host.
	static func server() -> NSXPCInterface {
		NSXPCInterface(with: RemoteConnectionServerProtocol.self)
	}

	/// What the host calls on the application.
	static func client() -> NSXPCInterface {
		let interface = NSXPCInterface(with: RemoteConnectionClientProtocol.self)
		interface.setClasses(
			NSSet(objects: NSArray.self, NSData.self) as? Set<AnyHashable> ?? [],
			for: #selector(RemoteConnectionClientProtocol.didReceive(_:acknowledge:)),
			argumentIndex: 0,
			ofReply: false
		)
		return interface
	}
}
