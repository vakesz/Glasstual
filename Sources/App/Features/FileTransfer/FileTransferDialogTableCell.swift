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
 *********************************************************************** */

import AppKit
import CocoaExtensions
import UniformTypeIdentifiers

private let filenameFieldWithProgressBarYCord: CGFloat = 4
private let filenameFieldWithoutProgressBarYCord: CGFloat = 12

private let transferInfoFieldWithProgressBarYCord: CGFloat = 6
private let transferInfoFieldWithoutProgressBarYCord: CGFloat = 16

@objc(TDCFileTransferDialogTableCell)
public final class FileTransferDialogTableCell: NSTableCellView {
	@IBOutlet private var progressIndicator: NSProgressIndicator!
	@IBOutlet private var fileIconView: NSImageView!
	@IBOutlet private var filenameTextField: NSTextField!
	@IBOutlet private var filesizeTextField: NSTextField!
	@IBOutlet private var transferProgressTextField: NSTextField!
	@IBOutlet private var filenameTextFieldConstraint: NSLayoutConstraint!
	@IBOutlet private var transferProgressTextFieldConstraint: NSLayoutConstraint!

	public func prepareInitialState() {
		let filename = filename

		filenameTextField.stringValue = filename

		let totalFilesize = totalFilesize

		filesizeTextField.stringValue =
			Int64(totalFilesize).textualPaddedByteCountDescription

		progressIndicator.doubleValue = 0
		progressIndicator.minValue = 0
		progressIndicator.maxValue = Double(totalFilesize)

		let contentType = UTType(filenameExtension: (filename as NSString).pathExtension)
		fileIconView.image = NSWorkspace.shared.icon(for: contentType ?? .data)

		reloadStatusInformation()
	}

	public var fileIcon: NSImage? {
		fileIconView.image
	}

	public var fileIconFrameOnScreen: NSRect {
		guard let iconView = fileIconView, let window = iconView.window else {
			return .zero
		}

		let frameInWindow = iconView.convert(iconView.bounds, to: nil)
		return window.convertToScreen(frameInWindow)
	}

	public func reloadStatusInformation() {
		let transferStatus = transferStatus

		let transferIsStopped =
			transferStatus == .complete
				|| transferStatus == .fatalError
				|| transferStatus == .recoverableError
				|| transferStatus == .stopped
				|| transferStatus == .isListeningAsSender
				|| transferStatus == .isListeningAsReceiver
				|| transferStatus == .initializing
				|| transferStatus == .mappingListeningPort
				|| transferStatus == .waitingForLocalIPAddress
				|| transferStatus == .waitingForReceiverToAccept
				|| transferStatus == .waitingForResumeAccept

		let processedFilesize = processedFilesize

		if transferIsStopped {
			if progressIndicator.isHidden == false {
				progressIndicator.isHidden = true

				filenameTextFieldConstraint.constant = filenameFieldWithoutProgressBarYCord
				transferProgressTextFieldConstraint.constant = transferInfoFieldWithoutProgressBarYCord

				layoutSubtreeIfNeeded()
			}
		} else if progressIndicator.isHidden {
			progressIndicator.isHidden = false

			filenameTextFieldConstraint.constant = filenameFieldWithProgressBarYCord
			transferProgressTextFieldConstraint.constant = transferInfoFieldWithProgressBarYCord

			layoutSubtreeIfNeeded()
		}

		if transferIsStopped == false {
			if transferStatus == .connecting {
				progressIndicator.isIndeterminate = true
				progressIndicator.startAnimation(nil)
			} else {
				progressIndicator.isIndeterminate = false
				progressIndicator.doubleValue = Double(processedFilesize)
			}
		}

		reloadStatusText(processedFilesize: processedFilesize)
		updateClearButton()
	}

	private func reloadStatusText(processedFilesize: UInt64) {
		switch transferStatus {
		case .fatalError, .recoverableError:
			transferProgressTextField.stringValue = errorMessageDescription ?? ""
		case .sending, .receiving:
			transferProgressTextField.stringValue = activeTransferStatus(processedFilesize: processedFilesize)
		default:
			transferProgressTextField.stringValue = FileTransferStrings.status(
				transferStatus,
				direction: transferDirection,
				peerNickname: peerNickname
			) ?? ""
		}
	}

	private func activeTransferStatus(processedFilesize: UInt64) -> String {
		let currentSpeed = currentSpeed
		let totalFilesize = totalFilesize
		let timeRemainingString: String? = if currentSpeed > 0, processedFilesize < totalFilesize {
			timeRemainingDescription(
				for: TimeInterval((totalFilesize - processedFilesize) / currentSpeed)
			)
		} else {
			nil
		}
		let totalFilesizeString = filesizeTextField.stringValue
		let currentSpeedString = Int64(currentSpeed).textualPaddedByteCountDescription
		let processedFilesizeString = Int64(processedFilesize).textualPaddedByteCountDescription

		return FileTransferStrings.progress(
			direction: transferDirection,
			processedSize: processedFilesizeString,
			totalSize: totalFilesizeString,
			speed: currentSpeedString,
			peerNickname: peerNickname,
			timeRemaining: timeRemainingString
		)
	}

	private var transferDirection: FileTransferDirection {
		isReceiving ? .incoming : .outgoing
	}

	private func timeRemainingDescription(for interval: TimeInterval) -> String? {
		guard interval > 0 else { return nil }
		let units = NSCalendar.Unit([.day, .hour, .minute, .second]).rawValue
		return humanReadableTimeInterval(interval, true, units) as String?
	}

	public func updateClearButton() {
		cellItem?.updateClearButton()
	}

	public func onMaintenanceTimer() {
		cellItem?.onMaintenanceTimer()
	}

	private var cellItem: TDCFileTransferDialogTransferController? {
		objectValue as? TDCFileTransferDialogTransferController
	}

	private var transferStatus: FileTransferStatus {
		cellItem?.transferStatus ?? .stopped
	}

	private var isReceiving: Bool {
		cellItem?.isSender == false
	}

	private var path: String? {
		cellItem?.path
	}

	private var filename: String {
		cellItem?.filename ?? ""
	}

	private var filePath: String? {
		cellItem?.filePath
	}

	private var peerNickname: String {
		cellItem?.peerNickname ?? ""
	}

	private var errorMessageDescription: String? {
		cellItem?.errorMessageDescription
	}

	private var hostAddress: String {
		cellItem?.hostAddress ?? ""
	}

	private var hostPort: UInt16 {
		cellItem?.hostPort ?? 0
	}

	private var totalFilesize: UInt64 {
		cellItem?.totalFilesize ?? 0
	}

	private var processedFilesize: UInt64 {
		cellItem?.processedFilesize ?? 0
	}

	private var currentRecord: UInt64 {
		cellItem?.currentRecord ?? 0
	}

	private var currentSpeed: UInt64 {
		let speedRecords = speedRecords

		guard speedRecords.isEmpty == false else {
			return 0
		}

		var totalTransferred: UInt64 = 0

		for record in speedRecords {
			totalTransferred += record.uint64Value
		}

		return totalTransferred / UInt64(speedRecords.count)
	}

	private var speedRecords: [NSNumber] {
		cellItem?.speedRecords ?? []
	}
}
