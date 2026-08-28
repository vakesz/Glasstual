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

import Darwin
import Foundation
import os

public extension TDCFileTransferDialogTransferController {
	func socket(_ socket: TDCFileTransferDialogSocket, didStartListeningOnPort port: UInt16) {
		dispatchPrecondition(condition: .onQueue(.main))
		guard socket === listeningServer else { return }
		listeningServerDidStart(on: port)
	}

	func socket(_ socket: TDCFileTransferDialogSocket, didFailToListenWithError error: Error) {
		dispatchPrecondition(condition: .onQueue(.main))
		guard socket === listeningServer else { return }
		fileTransferLogger.error("DCC listener failed: \(error.localizedDescription, privacy: .public)")
		close(with: .noListeningPort)
	}

	func socket(
		_ socket: TDCFileTransferDialogSocket,
		didAcceptConnection connection: TDCFileTransferDialogSocket
	) {
		dispatchPrecondition(condition: .onQueue(.main))
		guard socket === listeningServer, isActingAsServer else {
			connection.disconnect()
			return
		}
		guard listeningServerConnectedClient == nil else {
			connection.disconnect()
			return
		}
		guard acceptedConnectionIsFromPeer(connection) else {
			connection.disconnect()
			return
		}

		/* One listener serves one transfer. Leaving the port open past the
		 first accept only gives somebody else a window to reach it. */
		socket.stopListening()

		listeningServerConnectedClient = connection
		transferStatus = isReversed ? .receiving : .sending
		transferDialog.updateMaintenanceTimer()
		guard openFileHandle() else { return }

		if isReversed {
			readSocket?.readData()
		} else {
			sendPendingFileData()
		}
	}

	/// Whether an inbound connection came from the peer this transfer was
	/// negotiated with.
	///
	/// Only a reverse DCC gives us the peer's address up front: for a plain
	/// `DCC SEND` we listen and the remote end announces itself by connecting,
	/// so there is nothing to compare against and the connection is allowed.
	private func acceptedConnectionIsFromPeer(_ connection: TDCFileTransferDialogSocket) -> Bool {
		guard !hostAddress.isEmpty else {
			return true
		}

		guard let remoteHost = connection.remoteHost, remoteHost == hostAddress else {
			fileTransferLogger.error(
				"Rejected DCC connection from an address other than the one the transfer was offered from"
			)

			return false
		}

		return true
	}

	func socketDidConnect(_ socket: TDCFileTransferDialogSocket) {
		dispatchPrecondition(condition: .onQueue(.main))
		guard socket === connectionToRemoteServer, isActingAsClient else { return }

		transferStatus = isReversed ? .sending : .receiving
		transferDialog.updateMaintenanceTimer()
		guard openFileHandle() else { return }

		if isReversed {
			sendPendingFileData()
		} else {
			readSocket?.readData()
		}
	}

	func socket(_ socket: TDCFileTransferDialogSocket, didDisconnectWithError error: Error?) {
		dispatchPrecondition(condition: .onQueue(.main))
		guard socket === listeningServer
			|| socket === listeningServerConnectedClient
			|| socket === connectionToRemoteServer
		else {
			return
		}
		guard ![.complete, .fatalError, .recoverableError].contains(transferStatus) else { return }

		if let error {
			close(with: .underlying(error.localizedDescription))
		} else {
			close()
		}
	}

	func socket(_ socket: TDCFileTransferDialogSocket, didRead data: Data) {
		dispatchPrecondition(condition: .onQueue(.main))
		guard socket === readSocket, !isSender, let fileHandle else { return }

		/* A peer that sends more than it advertised would otherwise overshoot
		 the announced size by up to one read buffer. Keep only what was
		 promised and fail the transfer on the excess. */
		let remaining = totalFilesize > processedFilesize ? totalFilesize - processedFilesize : 0
		let overshot = UInt64(data.count) > remaining
		let data = overshot ? data.prefix(Int(remaining)) : data

		currentRecord += UInt64(data.count)
		processedFilesize += UInt64(data.count)

		if !data.isEmpty {
			do {
				try fileHandle.write(contentsOf: data)
			} catch {
				fileTransferLogger.error(
					"Failed to write transfer data: \(error.localizedDescription, privacy: .public)"
				)
				let cocoaError = error as NSError
				if cocoaError.domain == NSPOSIXErrorDomain, cocoaError.code == ENOSPC {
					failWithNoSpaceLeftOnDevice()
				} else {
					close(with: .fileHandlerFailed)
				}
				return
			}
		}

		readSocket?.write(acknowledgement(for: processedFilesize), timeout: -1)

		if overshot {
			fileTransferLogger.error("Peer sent more data than the transfer announced")
			close(with: .oversizedTransfer)
			return
		}

		if processedFilesize < totalFilesize {
			readSocket?.readData()
			return
		}

		transferStatus = .complete
		close()
	}

	func socketDidWriteData(_ socket: TDCFileTransferDialogSocket) {
		dispatchPrecondition(condition: .onQueue(.main))
		guard socket === writeSocket, isSender else { return }

		if sendQueueSize > 0 {
			sendQueueSize -= 1
		}
		if processedFilesize < totalFilesize {
			sendPendingFileData()
			return
		}
		guard sendQueueSize == 0 else { return }

		transferStatus = .complete
		close()
	}

	internal func sendPendingFileData() {
		guard isSender, transferStatus == .sending, let fileHandle, let writeSocket else { return }

		while currentRecord < FileTransferLimits.rateLimit,
		      sendQueueSize < FileTransferLimits.maximumSendQueueSize,
		      processedFilesize < totalFilesize
		{
			let data: Data
			do {
				guard let result = try fileHandle.read(upToCount: FileTransferLimits.bufferSize),
				      !result.isEmpty
				else {
					close(with: .sourceFileUnreadable)
					return
				}
				data = result
			} catch {
				fileTransferLogger.error(
					"Failed to read transfer data: \(error.localizedDescription, privacy: .public)"
				)
				close(with: .sourceFileUnreadable)
				return
			}

			currentRecord += UInt64(data.count)
			processedFilesize += UInt64(data.count)
			sendQueueSize += 1
			writeSocket.write(data, timeout: FileTransferLimits.sendTimeout)
		}
	}

	private var writeSocket: TDCFileTransferDialogSocket? {
		isReversed ? connectionToRemoteServer : listeningServerConnectedClient
	}

	private var readSocket: TDCFileTransferDialogSocket? {
		isReversed ? listeningServerConnectedClient : connectionToRemoteServer
	}

	private func acknowledgement(for byteCount: UInt64) -> Data {
		let bytes = UInt32(truncatingIfNeeded: byteCount)
		return Data([
			UInt8(truncatingIfNeeded: bytes >> 24),
			UInt8(truncatingIfNeeded: bytes >> 16),
			UInt8(truncatingIfNeeded: bytes >> 8),
			UInt8(truncatingIfNeeded: bytes),
		])
	}
}
