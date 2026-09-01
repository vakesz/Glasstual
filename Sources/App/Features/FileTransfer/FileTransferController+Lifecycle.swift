/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
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

import Foundation

extension FileTransferController {
	public func prepareForPermanentDestruction() {
		dispatchPrecondition(condition: .onQueue(.main))
		closeAndPostNotification(false)
		lifecycleNotifications.cancelAll()
		portMapperNotifications.cancelAll()
	}

	public func close() {
		closeAndPostNotification(true)
	}

	public func closeAndPostNotification(_ postNotification: Bool) {
		dispatchPrecondition(condition: .onQueue(.main))
		NSObject.cancelPreviousPerformRequests(withTarget: self)

		stopTransfer()
		closePortMapping()

		if ![.complete, .fatalError, .recoverableError].contains(transferStatus) {
			transferStatus = .stopped
		}

		if postNotification {
			postCompletionNotificationIfNeeded()
		}

		transferCenter.updateMaintenanceTimer()
		enableSystemSleep()
	}

	func failWithNoSpaceLeftOnDevice() {
		close(with: .storageFull)
	}

	func close(
		with failure: FileTransferFailure,
		isFatalError: Bool = false
	) {
		errorMessageDescription = FileTransferStrings.failure(failure, peerNickname: peerNickname)
		transferStatus = isFatalError ? .fatalError : .recoverableError
		close()
	}

	func peerNicknameChanged(_ notification: Notification) {
		guard let oldNickname = notification.userInfo?["oldNickname"] as? String,
		      peerNickname == oldNickname,
		      let newNickname = notification.userInfo?["newNickname"] as? String
		else {
			return
		}
		peerNickname = newNickname
	}

	func clientDisconnected(_: Notification) {
		closeWithClientDisconnectedError()
	}

	func disableSystemSleep() {
		transferProgressHandler = ProcessInfo.processInfo.beginActivity(
			options: .userInitiated,
			reason: "Transferring file"
		) as NSObjectProtocol
	}

	private func enableSystemSleep() {
		guard let transferProgressHandler else { return }

		ProcessInfo.processInfo.endActivity(transferProgressHandler)
		self.transferProgressHandler = nil
	}

	private func closeWithClientDisconnectedError() {
		let pendingStatuses: Set<FileTransferStatus> = [
			.connecting,
			.initializing,
			.isListeningAsReceiver,
			.isListeningAsSender,
			.mappingListeningPort,
			.waitingForLocalIPAddress,
			.waitingForReceiverToAccept,
			.waitingForResumeAccept,
		]
		guard pendingStatuses.contains(transferStatus) else { return }
		closeWithClientDisconnectedErrorImmediately()
	}

	func closeWithClientDisconnectedErrorImmediately() {
		close(with: .notConnectedToIRC)
	}

	private func postCompletionNotificationIfNeeded() {
		guard let client else { return }

		let type: NotificationEvent
		switch (transferStatus, isSender) {
		case (.fatalError, true), (.recoverableError, true):
			type = .fileTransferSendFailed
		case (.fatalError, false), (.recoverableError, false):
			type = .fileTransferReceiveFailed
		case (.complete, true):
			type = .fileTransferSendSuccessful
		case (.complete, false):
			type = .fileTransferReceiveSuccessful
		default:
			return
		}

		client.notifyFileTransfer(
			type,
			nickname: peerNickname,
			filename: filename,
			filesize: totalFilesize,
			requestIdentifier: uniqueIdentifier
		)
	}
}
