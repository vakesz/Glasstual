/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\_\\__|\\__,_|\\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import AppKit
import CocoaExtensions
import Darwin
import os

enum TranscriptDirectory {
	static let console = "Console"
	static let channel = "Channels"
	static let privateMessage = "Queries"
}

private struct WeakLogger {
	weak var logger: FileLogger?
}

/// Transcript file logger. Main-actor isolated so that opening, writing and the
/// idle sweep that closes a stale handle can never race with each other.
@objc(TLOFileLogger)
@MainActor
public final class FileLogger: NSObject {
	private static let logger = Logger(
		subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
		category: "FileLogger"
	)

	private static let noSpaceLeftOnDeviceAlertInterval: TimeInterval = 300
	private nonisolated static let fileHandleIdleLimit: TimeInterval = 1200 // nonisolated: let
	private static let idleSweepInterval: Duration = .seconds(600)

	/** Weak so a logger that is released without closing drops out of the sweep
	 instead of keeping it running forever, which an unbalanced open/close count
	 used to do. */
	private static var openLoggers: [WeakLogger] = []
	private static var idleSweepTask: Task<Void, Never>?
	private static var noSpaceAlertVisible = false
	private static var lastNoSpaceFailTime: TimeInterval = 0

	private weak var client: IRCClient?
	private weak var channel: IRCChannel?
	private var fileHandle: FileHandle?
	private var dateOpened: Date?
	private var lastWriteTime: TimeInterval = 0

	@objc public private(set) var filePath: String?

	@available(*, unavailable)
	override public init() {
		fatalError("Use init(client:) or init(channel:)")
	}

	@objc(initWithClient:)
	public init(client: IRCClient) {
		self.client = client

		super.init()
	}

	@objc(initWithChannel:)
	public init(channel: IRCChannel) {
		client = channel.associatedClient
		self.channel = channel

		super.init()
	}

	isolated deinit {
		close()
	}

	// MARK: - Plain Text API

	public func writeLogLine(_ logLine: LogLine) {
		let stringToWrite: String = if let channel {
			logLine.renderedBodyForTranscriptLog(in: channel)
		} else {
			logLine.renderedBodyForTranscriptLog
		}

		writePlainText(stringToWrite)
	}

	@objc(writePlainText:)
	public func writePlainText(_ string: String) {
		reopenIfNeeded()

		guard let fileHandle else {
			Self.logger.error("File handle is closed")

			return
		}

		guard let dataToWrite = (string + "\n").data(using: .utf8, allowLossyConversion: true) else {
			return
		}

		lastWriteTime = Date().timeIntervalSince1970

		do {
			try fileHandle.write(contentsOf: dataToWrite)
		} catch {
			Self.logger.error("Failed to write to log file: \(error.localizedDescription, privacy: .public)")

			if Self.errorIsNoSpaceLeftOnDevice(error) {
				failWithNoSpaceLeftOnDevice()
			}

			close()
		}
	}

	// MARK: - File Handle Management

	@objc public func close() {
		closeHandle(removeObserver: true)
	}

	private func closeHandle(removeObserver: Bool) {
		guard let fileHandle else {
			return
		}

		do {
			try fileHandle.synchronize()
		} catch {
			Self.logger.error("Failed to synchronize log file: \(error.localizedDescription, privacy: .public)")
		}

		do {
			try fileHandle.close()
		} catch {
			Self.logger.error("Failed to close log file: \(error.localizedDescription, privacy: .public)")
		}

		self.fileHandle = nil
		filePath = nil
		lastWriteTime = 0
		dateOpened = nil

		if removeObserver {
			unregisterFromIdleSweep()
		}
	}

	@objc public func reopenIfNeeded() {
		if fileHandle != nil, let dateOpened, Calendar.current.isDate(dateOpened, inSameDayAs: Date()) {
			return
		}

		reopen()
	}

	@objc public func reopen() {
		close()
		open()
	}

	@objc public func open() {
		if fileHandle != nil {
			Self.logger.error("Tried to open log file when a file handle already exists")

			return
		}

		guard buildFilePath(), let filePath, let writePath else {
			return
		}

		let fileManager = FileManager.default
		let fileURL = URL(fileURLWithPath: filePath)
		let writeURL = URL(fileURLWithPath: writePath, isDirectory: true)

		if fileManager.fileExists(atPath: writePath) == false {
			do {
				try fileManager.createDirectory(at: writeURL, withIntermediateDirectories: true)
			} catch {
				Self.logger.error("Error Creating Folder: \(error.localizedDescription, privacy: .public)")

				return
			}
		}

		if fileManager.fileExists(atPath: filePath) == false {
			do {
				try Data().write(to: fileURL, options: [])
			} catch {
				Self.logger.error("Error Creating File: \(error.localizedDescription, privacy: .public)")

				return
			}
		}

		let openedHandle: FileHandle

		do {
			openedHandle = try FileHandle(forUpdating: fileURL)
			_ = try openedHandle.seekToEnd()
		} catch {
			Self.logger.error(
				"Failed to open file handle at path '\(Self.displayPath(for: fileURL), privacy: .public)'"
			)
			Self.logger.error("Failed to seek to end of log file: \(error.localizedDescription, privacy: .public)")

			return
		}

		fileHandle = openedHandle
		dateOpened = Date()

		registerForIdleSweep()
	}

	// MARK: - Paths

	@objc public var writePath: String? {
		(filePath as NSString?)?.deletingLastPathComponent
	}

	@objc public var fileName: String? {
		(filePath as NSString?)?.lastPathComponent
	}

	@objc(writePathForItem:)
	public static func writePath(for item: IRCTreeItem) -> String? {
		guard let sourcePath = PathInfo.transcriptFolder else {
			return nil
		}

		return writePath(for: item, relativeTo: sourcePath)
	}

	@objc(writePathForItem:relativeTo:)
	public static func writePath(for item: IRCTreeItem, relativeTo sourcePath: String) -> String? {
		guard let relativePath = relativeTranscriptPath(for: item) else {
			return nil
		}

		return (sourcePath as NSString).appendingPathComponent(relativePath)
	}

	private func writePath(relativeTo sourcePath: String) -> String? {
		if let channel {
			return Self.writePath(for: channel, relativeTo: sourcePath)
		}

		guard let client else {
			return nil
		}

		return Self.writePath(for: client, relativeTo: sourcePath)
	}

	private func buildFilePath() -> Bool {
		guard let sourcePath = PathInfo.transcriptFolder,
		      let writePath = writePath(relativeTo: sourcePath)
		else {
			return false
		}

		let dateTime = formattedTimestamp(Date() as NSDate, "%Y-%m-%d") as String? ?? ""
		filePath = (writePath as NSString).appendingPathComponent("\(dateTime).txt")

		return true
	}

	private static func relativeTranscriptPath(for item: IRCTreeItem) -> String? {
		let channel = item.associatedChannel

		if let channel, channel.isUtility {
			return nil
		}

		guard let client = item.associatedClient else {
			return nil
		}

		let identifier = client.uniqueIdentifier as NSString
		let clientIdentifier = identifier.substring(to: min(5, identifier.length))
		let clientName = "\(client.name) (\(clientIdentifier))".safeFilename

		guard let channel else {
			return "/\(clientName)/\(TranscriptDirectory.console)/"
		}

		let channelName = channel.name.safeFilename

		if channel.isChannel {
			return "/\(clientName)/\(TranscriptDirectory.channel)/\(channelName)/"
		}

		if channel.isPrivateMessage || channel.isDirectChat {
			return "/\(clientName)/\(TranscriptDirectory.privateMessage)/\(channelName)/"
		}

		return nil
	}

	private static func displayPath(for url: URL) -> String {
		url.standardizedTildePath ?? url.path
	}

	// MARK: - Idle Sweep

	private var fileHandleIdle: Bool {
		Self.fileHandleIsIdle(lastWriteTime: lastWriteTime, at: Date().timeIntervalSince1970)
	}

	/// A handle that has never been written to is not idle; one that has is idle
	/// once nothing has been written to it for `fileHandleIdleLimit` seconds.
	nonisolated static func fileHandleIsIdle(lastWriteTime: TimeInterval, // nonisolated: pure
	                                         at now: TimeInterval) -> Bool
	{
		guard lastWriteTime > 0 else {
			return false
		}

		return (now - lastWriteTime) > fileHandleIdleLimit
	}

	private static func startIdleSweep() {
		guard idleSweepTask == nil else {
			return
		}

		idleSweepTask = Task { @MainActor in
			while Task.isCancelled == false {
				try? await Task.sleep(for: idleSweepInterval)

				guard Task.isCancelled == false else {
					return
				}

				sweepIdleLoggers()
			}
		}
	}

	private static func stopIdleSweep() {
		idleSweepTask?.cancel()
		idleSweepTask = nil
	}

	private static func sweepIdleLoggers() {
		openLoggers.removeAll { $0.logger == nil }

		guard openLoggers.isEmpty == false else {
			stopIdleSweep()

			return
		}

		for entry in openLoggers {
			entry.logger?.closeIfIdle()
		}
	}

	private func closeIfIdle() {
		guard fileHandleIdle else {
			return
		}

		Self.logger.debug("Closing \(String(describing: self), privacy: .public) because it's idle")

		close()
	}

	private func registerForIdleSweep() {
		Self.openLoggers.removeAll { $0.logger == nil || $0.logger === self }
		Self.openLoggers.append(WeakLogger(logger: self))

		Self.startIdleSweep()
	}

	private func unregisterFromIdleSweep() {
		Self.openLoggers.removeAll { $0.logger == nil || $0.logger === self }

		if Self.openLoggers.isEmpty {
			Self.stopIdleSweep()
		}
	}

	// MARK: - Disk Space

	private static func errorIsNoSpaceLeftOnDevice(_ error: Error?) -> Bool {
		var current = error as NSError?

		while let candidate = current {
			if candidate.domain == NSPOSIXErrorDomain, candidate.code == Int(ENOSPC) {
				return true
			}

			if candidate.domain == NSCocoaErrorDomain, candidate.code == CocoaError.fileWriteOutOfSpace.rawValue {
				return true
			}

			current = candidate.userInfo[NSUnderlyingErrorKey] as? NSError
		}

		return false
	}

	private func failWithNoSpaceLeftOnDevice() {
		if Self.noSpaceAlertVisible {
			return
		}

		let currentTime = Date().timeIntervalSince1970

		if Self.lastNoSpaceFailTime > 0,
		   (currentTime - Self.lastNoSpaceFailTime) < Self.noSpaceLeftOnDeviceAlertInterval
		{
			return
		}

		Self.lastNoSpaceFailTime = currentTime
		Self.noSpaceAlertVisible = true

		TDCAlert.alert(
			withMessage: PromptStrings.Logging.resumeAfterLowStorageBody,
			title: PromptStrings.Logging.disabledForLowStorageTitle,
			defaultButton: PromptStrings.Action.confirmation,
			alternateButton: nil
		) { _ in
			Self.noSpaceAlertVisible = false
		}
	}
}
