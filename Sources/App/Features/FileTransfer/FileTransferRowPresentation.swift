// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

/** Everything one row of the transfer list draws, settled once per redraw.

 A row shows sizes, a speed and a time remaining, all of which are the same
 numbers said in the reader's language rather than anything the transfer itself
 keeps. Working them out here means the row's `body` reads them instead of
 formatting them. */
struct FileTransferRowPresentation {
	enum Progress: Equatable {
		case hidden
		case indeterminate
		case determinate(value: UInt64, total: UInt64)
	}

	let filename: String
	let totalSize: String
	/// How much has arrived so far, written the way the row's sizes are. The
	/// accessibility value reads it, so it is not a raw byte count.
	let processedSize: String
	let status: String
	let progress: Progress

	init(transfer: FileTransfer) {
		filename = transfer.filename
		totalSize = LocalizedByteCount.formatted(transfer.totalFilesize)
		processedSize = LocalizedByteCount.formatted(transfer.processedFilesize)
		progress = switch transfer.transferStatus {
		case .connecting:
			.indeterminate
		case .receiving, .sending:
			.determinate(value: transfer.processedFilesize, total: transfer.totalFilesize)
		default:
			.hidden
		}

		if transfer.transferStatus == .complete, case .unacknowledged? = transfer.completion {
			status = String(localized: .FileTransfer.sentToWithoutAPeerAcknowledgement(transfer.peerNickname))
		} else if [.fatalError, .recoverableError].contains(transfer.transferStatus) {
			status = transfer.errorMessageDescription ?? ""
		} else if transfer.transferStatus.isActive {
			status = Self.activeStatus(for: transfer, processedSize: processedSize, totalSize: totalSize)
		} else {
			status = transfer.transferStatus.notice(
				direction: transfer.isSender ? .outgoing : .incoming,
				peerNickname: transfer.peerNickname
			) ?? ""
		}
	}

	private static func activeStatus(
		for transfer: FileTransfer,
		processedSize: String,
		totalSize: String
	) -> String {
		let currentSpeed = averageSpeed(transfer.speedRecords)
		let speed = LocalizedByteCount.formatted(currentSpeed)
		let timeRemaining: String? = if currentSpeed > 0,
		                                transfer.processedFilesize < transfer.totalFilesize
		{
			timeRemainingDescription(
				for: TimeInterval((transfer.totalFilesize - transfer.processedFilesize) / currentSpeed)
			)
		} else {
			nil
		}

		let direction: FileTransferDirection = transfer.isSender ? .outgoing : .incoming

		return direction.progressNotice(
			processedSize: processedSize,
			totalSize: totalSize,
			speed: speed,
			peerNickname: transfer.peerNickname,
			timeRemaining: timeRemaining
		)
	}

	private static func averageSpeed(_ records: [UInt64]) -> UInt64 {
		guard records.isEmpty == false else { return 0 }
		var total: UInt64 = 0
		for record in records {
			let (sum, overflow) = total.addingReportingOverflow(record)
			total = overflow ? .max : sum
		}
		return total / UInt64(records.count)
	}

	private static func timeRemainingDescription(for interval: TimeInterval) -> String? {
		guard interval > 0 else { return nil }

		return DateFormatting.humanReadable(
			interval,
			shortValue: true,
			fields: [.day, .hour, .minute, .second]
		)
	}
}
