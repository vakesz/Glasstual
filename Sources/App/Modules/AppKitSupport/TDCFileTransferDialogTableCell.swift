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
 *********************************************************************** */

import AppKit
import UniformTypeIdentifiers

private let filenameFieldWithProgressBarYCord: CGFloat = 4
private let filenameFieldWithoutProgressBarYCord: CGFloat = 12

private let transferInfoFieldWithProgressBarYCord: CGFloat = 6
private let transferInfoFieldWithoutProgressBarYCord: CGFloat = 16

@objc(TDCFileTransferDialogTableCell)
public final class FileTransferDialogTableCell: NSTableCellView {
	@IBOutlet private weak var progressIndicator: NSProgressIndicator!
	@IBOutlet private weak var fileIconView: NSImageView!
	@IBOutlet private weak var filenameTextField: NSTextField!
	@IBOutlet private weak var filesizeTextField: NSTextField!
	@IBOutlet private weak var transferProgressTextField: NSTextField!
	@IBOutlet private weak var filenameTextFieldConstraint: NSLayoutConstraint!
	@IBOutlet private weak var transferProgressTextFieldConstraint: NSLayoutConstraint!

	@objc
	public func prepareInitialState() {
		let filename = self.filename

		filenameTextField.stringValue = filename

		let totalFilesize = self.totalFilesize

		filesizeTextField.stringValue =
			ByteCountFormatter.stringFromByteCount(withPaddedDigits: Int64(totalFilesize)) ?? ""

		progressIndicator.doubleValue = 0
		progressIndicator.minValue = 0
		progressIndicator.maxValue = Double(totalFilesize)

		let contentType = UTType(filenameExtension: (filename as NSString).pathExtension)
		fileIconView.image = NSWorkspace.shared.icon(for: contentType ?? .data)

		reloadStatusInformation()
	}

	@objc public var fileIcon: NSImage? {
		fileIconView.image
	}

	@objc public var fileIconFrameOnScreen: NSRect {
		guard let iconView = fileIconView, let window = iconView.window else {
			return .zero
		}

		let frameInWindow = iconView.convert(iconView.bounds, to: nil)
		return window.convertToScreen(frameInWindow)
	}

	@objc
	public func reloadStatusInformation() {
		/* Called from the transfer controller's socket dispatch queue.
		 The hop to the main queue is asynchronous so that the socket
		 queue never blocks on the main thread. */
		if Thread.isMainThread {
			reloadStatusInformationOnMain()
		} else {
			XRPerformBlockAsynchronouslyOnMainQueue { [weak self] in
				self?.reloadStatusInformationOnMain()
			}
		}
	}

	private func reloadStatusInformationOnMain() {
		let transferStatus = self.transferStatus

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

		let processedFilesize = self.processedFilesize

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

		switch transferStatus {
		case .stopped:
			if isReceiving {
				transferProgressTextField.stringValue = LocalizedKey(
					"TDCFileTransferDialog[jvh-u7]",
					peerNickname
				)
			} else {
				transferProgressTextField.stringValue = LocalizedKey(
					"TDCFileTransferDialog[w3h-p8]",
					peerNickname
				)
			}

		case .mappingListeningPort:
			if isReceiving {
				transferProgressTextField.stringValue = LocalizedKey(
					"TDCFileTransferDialog[495-90]",
					peerNickname
				)
			} else {
				transferProgressTextField.stringValue = LocalizedKey(
					"TDCFileTransferDialog[j1z-88]",
					peerNickname
				)
			}

		case .waitingForLocalIPAddress:
			if isReceiving {
				transferProgressTextField.stringValue = LocalizedKey(
					"TDCFileTransferDialog[6t1-mb]",
					peerNickname
				)
			} else {
				transferProgressTextField.stringValue = LocalizedKey(
					"TDCFileTransferDialog[onl-av]",
					peerNickname
				)
			}

		case .initializing:
			if isReceiving {
				transferProgressTextField.stringValue = LocalizedKey(
					"TDCFileTransferDialog[42z-mg]",
					peerNickname
				)
			} else {
				transferProgressTextField.stringValue = LocalizedKey(
					"TDCFileTransferDialog[pcv-kg]",
					peerNickname
				)
			}

		case .isListeningAsSender:
			transferProgressTextField.stringValue = LocalizedKey(
				"TDCFileTransferDialog[ca5-2v]",
				peerNickname
			)

		case .isListeningAsReceiver:
			transferProgressTextField.stringValue = LocalizedKey(
				"TDCFileTransferDialog[pip-z6]",
				peerNickname
			)

		case .fatalError, .recoverableError:
			transferProgressTextField.stringValue = errorMessageDescription ?? ""

		case .complete:
			if isReceiving {
				transferProgressTextField.stringValue = LocalizedKey(
					"TDCFileTransferDialog[6gu-za]",
					peerNickname
				)
			} else {
				transferProgressTextField.stringValue = LocalizedKey(
					"TDCFileTransferDialog[rx7-xy]",
					peerNickname
				)
			}

		case .sending, .receiving:
			var timeRemainingString: String?

			let currentSpeed = self.currentSpeed
			let totalFilesize = self.totalFilesize

			/* The peer may send more than it announced. Never let the
			 unsigned subtraction wrap into a multi-century estimate. */
			if currentSpeed > 0, processedFilesize < totalFilesize {
				let timeRemaining = TimeInterval((totalFilesize - processedFilesize) / currentSpeed)

				if timeRemaining > 0 {
					let units = NSCalendar.Unit([.day, .hour, .minute, .second]).rawValue
					timeRemainingString = humanReadableTimeInterval(timeRemaining, true, units) as String?
				}
			}

			let totalFilesizeString = filesizeTextField.stringValue
			let currentSpeedString =
				ByteCountFormatter.stringFromByteCount(withPaddedDigits: Int64(currentSpeed)) ?? ""
			let processedFilesizeString =
				ByteCountFormatter.stringFromByteCount(withPaddedDigits: Int64(processedFilesize)) ?? ""

			let statusString: String

			if isReceiving {
				if let timeRemainingString {
					statusString = LocalizedKey(
						"TDCFileTransferDialog[9xn-7j]",
						processedFilesizeString,
						totalFilesizeString,
						currentSpeedString,
						peerNickname,
						timeRemainingString
					)
				} else {
					statusString = LocalizedKey(
						"TDCFileTransferDialog[7dk-lp]",
						processedFilesizeString,
						totalFilesizeString,
						currentSpeedString,
						peerNickname
					)
				}
			} else if let timeRemainingString {
				statusString = LocalizedKey(
					"TDCFileTransferDialog[u17-ql]",
					processedFilesizeString,
					totalFilesizeString,
					currentSpeedString,
					peerNickname,
					timeRemainingString
				)
			} else {
				statusString = LocalizedKey(
					"TDCFileTransferDialog[nvm-nd]",
					processedFilesizeString,
					totalFilesizeString,
					currentSpeedString,
					peerNickname
				)
			}

			transferProgressTextField.stringValue = statusString

		case .connecting:
			transferProgressTextField.stringValue = LocalizedKey(
				"TDCFileTransferDialog[7nf-fr]",
				peerNickname
			)

		case .waitingForReceiverToAccept:
			transferProgressTextField.stringValue = LocalizedKey(
				"TDCFileTransferDialog[cku-24]",
				peerNickname
			)

		case .waitingForResumeAccept:
			transferProgressTextField.stringValue = LocalizedKey(
				"TDCFileTransferDialog[gxq-zu]",
				peerNickname
			)

		@unknown default:
			break
		}

		updateClearButton()
	}

	@objc
	public func updateClearButton() {
		cellItem?.updateClearButton()
	}

	@objc
	public func onMaintenanceTimer() {
		cellItem?.onMaintenanceTimer()
	}

	private var cellItem: TDCFileTransferDialogTransferController? {
		objectValue as? TDCFileTransferDialogTransferController
	}

	private var transferStatus: TDCFileTransferDialogTransferStatus {
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
		let speedRecords = self.speedRecords

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
