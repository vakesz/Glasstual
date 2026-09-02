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
import os

extension FileTransferController {
	public func onMaintenanceTimer() {
		guard transferStatus == .receiving || transferStatus == .sending else {
			assertionFailure("Maintenance timer fired for an inactive transfer")
			return
		}

		speedRecords.append(currentRecord)
		if speedRecords.count > FileTransferLimits.speedRecordCount {
			speedRecords.removeFirst()
		}
		currentRecord = 0
		reloadStatusInformation()
	}

	/** Takes the destination this receiver writes into, once.

	 Everything downstream — the resume offset the client proposes, and the
	 handle `DCCTransfer` seeks in — reads `filePath`, so the name has to settle
	 before any of it runs. Claiming a free name is also what makes a resume
	 safe: the only file this transfer will ever append to is the one it took
	 here, so a partial download can carry on while an unrelated file of the
	 same name is left alone.

	 A second call is a no-op, which is what lets a stopped transfer be started
	 again without walking on to yet another name and losing the bytes it
	 already has. */
	func claimDestinationFilename() {
		guard claimedFilePath == nil else { return }

		setNonexistentFilename()
		claimedFilePath = filePath
	}

	/// Moves `filename` on to the next free name in the download folder.
	///
	/// A transfer that lands on a name already in use would otherwise overwrite
	/// somebody's file, so the receiver takes the next free one before the
	/// transfer opens anything.
	private func setNonexistentFilename() {
		guard let directoryPath = path,
		      var candidatePath = filePath,
		      FileManager.default.fileExists(atPath: candidatePath)
		else {
			return
		}

		let filenameExtension = (filename as NSString).pathExtension
		let stem = (filename as NSString).deletingPathExtension
		var suffix = 1
		repeat {
			let candidateName = filenameExtension.isEmpty
				? "\(stem)_\(suffix)"
				: "\(stem)_\(suffix).\(filenameExtension)"
			candidatePath = (directoryPath as NSString).appendingPathComponent(candidateName)
			suffix += 1
		} while FileManager.default.fileExists(atPath: candidatePath)

		filename = (candidatePath as NSString).lastPathComponent
	}
}
