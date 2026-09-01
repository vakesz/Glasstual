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

import Foundation
import os

extension FileTransferController {
	/// Hands the transfer to a ``DCCTransfer`` actor and follows it.
	///
	/// Every event arrives back here on the main actor, which is where the
	/// status, the progress and the dialog all live, so nothing the actor
	/// reports has to cross isolation a second time.
	func startTransfer(with configuration: DCCTransfer.Configuration) {
		let transfer = DCCTransfer(configuration: configuration)
		self.transfer = transfer

		transferEvents = Task { [weak self] in
			await transfer.start()

			for await event in transfer.events {
				self?.transferDidReport(event)
			}
		}
	}

	/// Stops the running transfer, if there is one.
	func stopTransfer() {
		transferEvents?.cancel()
		transferEvents = nil

		guard let transfer else {
			return
		}

		self.transfer = nil

		Task { await transfer.cancel() }
	}

	private func transferDidReport(_ event: DCCTransferEvent) {
		switch event {
		case let .listening(port):
			listeningServerDidStart(on: port)
		case .connected:
			transferDidConnect()
		case let .progress(processedBytes):
			transferDidProgress(to: processedBytes)
		case .finished:
			transferStatus = .complete
			close()
		case let .failed(error):
			transferDidFail(with: error)
		}
	}

	private func transferDidConnect() {
		transferStatus = isSender ? .sending : .receiving
		transferCenter.updateMaintenanceTimer()
	}

	private func transferDidProgress(to processedBytes: UInt64) {
		/* `currentRecord` is the byte count the maintenance timer turns into a
		 transfer rate once a second, so it takes the delta, not the total. */
		if processedBytes > processedFilesize {
			currentRecord += processedBytes - processedFilesize
		}

		processedFilesize = processedBytes
	}

	private func transferDidFail(with error: DCCTransferError) {
		guard ![.complete, .fatalError, .recoverableError].contains(transferStatus) else {
			return
		}

		fileTransferLogger.error("DCC transfer failed: \(String(describing: error), privacy: .public)")
		close(with: FileTransferFailure(error))
	}
}
