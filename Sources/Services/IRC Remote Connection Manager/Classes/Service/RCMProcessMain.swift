/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2017, 2018 Codeux Software, LLC & respective contributors.
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

@objc(RCMProcessMain)
final class RemoteConnectionProcess: NSObject, RemoteConnectionServerProtocol {
	private var connection: Connection?
	private var serviceConnection: NSXPCConnection?
	/** `ProcessInfo.disableSuddenTermination()` is a counter. The host process is shared by
	 every connection, so an unbalanced disable would permanently pin the whole service. */
	private var suddenTerminationDisableCount = 0

	@available(*, unavailable)
	override init() {
		fatalError("init() is unavailable; use init(xpcConnection:)")
	}

	@objc(initWithXPCConnection:)
	init(xpcConnection: NSXPCConnection) {
		serviceConnection = xpcConnection
		super.init()
		Logging.setDefaultSubsystem(toMainBundleCategory: "General")
	}

	func clientConnectionEnded() {
		let activeConnection = connection
		connection = nil
		activeConnection?.close()
		serviceConnection = nil
		balanceSuddenTermination()
	}

	func open(with config: IRCConnectionConfig) {
		guard connection == nil else {
			RCMLog.connection.error("Cannot open a connection that is already open")
			return
		}

		guard let serviceConnection else {
			RCMLog.connection.error("Cannot open a connection after the client connection ended")
			return
		}

		let activeConnection = Connection(with: config, on: serviceConnection)
		activeConnection.open()
		connection = activeConnection
	}

	func close() {
		requireConnection(#function)?.close()
	}

	func send(_ data: Data) {
		requireConnection(#function)?.send(data)
	}

	func send(_ data: Data, bypassQueue: Bool) {
		requireConnection(#function)?.send(data, bypassQueue: bypassQueue)
	}

	func exportSecureConnectionInformation(_ completionBlock: SecureConnectionInformationReceiver) {
		/* The caller blocks on this reply, so it has to be invoked on every path. */
		guard let connection = requireConnection(#function) else {
			completionBlock(nil, tlsProtocolVersionUnknown, tlsCipherSuiteUnknown, [], nil)
			return
		}

		do {
			try connection.exportSecureConnectionInformation(to: completionBlock)
		} catch {
			RCMLog.connection.error("Unable to export secure connection information: \(error.localizedDescription)")
			completionBlock(nil, tlsProtocolVersionUnknown, tlsCipherSuiteUnknown, [], error.localizedDescription)
		}
	}

	func enforceFloodControl() {
		requireConnection(#function)?.enforceFloodControl()
	}

	func clearSendQueue() {
		requireConnection(#function)?.clearSendQueue()
	}

	func enableAppNap() {
		UserDefaults.standard.register(defaults: ["NSAppSleepDisabled": false])
	}

	func disableAppNap() {
		UserDefaults.standard.register(defaults: ["NSAppSleepDisabled": true])
	}

	func enableSuddenTermination() {
		guard suddenTerminationDisableCount > 0 else { return }
		suddenTerminationDisableCount -= 1
		ProcessInfo.processInfo.enableSuddenTermination()
	}

	func disableSuddenTermination() {
		suddenTerminationDisableCount += 1
		ProcessInfo.processInfo.disableSuddenTermination()
	}

	private func balanceSuddenTermination() {
		while suddenTerminationDisableCount > 0 {
			enableSuddenTermination()
		}
	}

	/** The service process is shared by every connection, so an unexpected call has to be
	 rejected rather than aborted — a trap here would drop every other server as well. */
	private func requireConnection(_ caller: String) -> Connection? {
		guard let connection else {
			RCMLog.connection.error("\(caller, privacy: .public) invoked without performing setup first")
			return nil
		}

		return connection
	}
}
