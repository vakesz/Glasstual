/* *********************************************************************
 *
 *         Copyright (c) 2015 - 2020 Codeux Software, LLC
 *     Please see ACKNOWLEDGEMENT for additional information.
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
 *  * Neither the name of "Codeux Software, LLC", nor the names of its
 *    contributors may be used to endorse or promote products derived
 *    from this software without specific prior written permission.
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

private let fileOperationLogger = Logger(
	subsystem: "com.vakesz.glasstual.frameworks.CocoaExtensions",
	category: "FileOperations"
)

public struct FileOperationOptions: OptionSet, Sendable {
	public let rawValue: UInt

	public init(rawValue: UInt) {
		self.rawValue = rawValue
	}

	/// Delete whatever already sits at the destination instead of failing.
	public static let removeIfExists = FileOperationOptions(rawValue: 1 << 1)

	/// Send the replaced item to the trash rather than deleting it outright.
	public static let moveToTrash = FileOperationOptions(rawValue: 1 << 5)

	/// Link, rather than copy, applications and other bundles.
	public static let symlinkPackages = FileOperationOptions(rawValue: 1 << 8)
}

public extension FileManager {
	class var pathOfHomeDirectoryOutsideSandbox: String {
		guard let password = getpwuid(getuid()), let directory = password.pointee.pw_dir else {
			return NSHomeDirectory()
		}
		return String(cString: directory)
	}

	class var URLOfHomeDirectoryOutsideSandbox: URL {
		URL(fileURLWithPath: pathOfHomeDirectoryOutsideSandbox, isDirectory: true)
	}

	func fileExists(at url: URL) -> Bool {
		fileExists(atPath: url.path)
	}

	func replaceItem(at destination: URL, withItemAt source: URL) -> Bool {
		replaceItem(at: destination, withItemAt: source, options: [.moveToTrash, .removeIfExists])
	}

	/// Puts `source` where `destination` is, copying, moving or linking it
	/// depending on `options`. Theme and plugin installation run through here,
	/// so a failure is logged rather than swallowed into a bare `false`.
	func replaceItem(at destination: URL, withItemAt source: URL, options: FileOperationOptions) -> Bool {
		do {
			try stageAndReplaceItem(at: destination, withItemAt: source, options: options)
			return true
		} catch {
			fileOperationLogger.error(
				"""
				Could not place [\(source.standardizedTildePath ?? "", privacy: .public)] \
				at [\(destination.standardizedTildePath ?? "", privacy: .public)]: \
				\(error.localizedDescription, privacy: .public)
				"""
			)
			return false
		}
	}

	/// Validates a staged copy, then publishes it with one filesystem operation.
	/// Neither copying nor validation can damage an already installed item.
	func stageAndReplaceItem(
		at destination: URL,
		withItemAt source: URL,
		options: FileOperationOptions = [.removeIfExists, .moveToTrash],
		validate: (URL) throws -> Void = { _ in }
	) throws {
		guard source.isFileURL, destination.isFileURL else { throw CocoaError(.fileWriteUnsupportedScheme) }
		let sourcePath = source.resolvingSymlinksInPath().standardizedFileURL.path
		let destinationPath = destination.resolvingSymlinksInPath().standardizedFileURL.path
		if sourcePath == destinationPath {
			guard fileExists(at: source) else { throw CocoaError(.fileNoSuchFile) }
			try validate(source)
			return
		}
		guard !sourcePath.hasPrefix(destinationPath + "/"), !destinationPath.hasPrefix(sourcePath + "/") else {
			throw CocoaError(.fileWriteInvalidFileName)
		}
		let replacing = fileExists(at: destination)
		guard !replacing || options.contains(.removeIfExists) else { throw CocoaError(.fileWriteFileExists) }
		let parent = destination.deletingLastPathComponent()
		try createDirectory(at: parent, withIntermediateDirectories: true)
		removeStagingDirectories(in: parent)
		let stagingDirectory = parent.appendingPathComponent(
			"\(stagingDirectoryPrefix)\(UUID().uuidString)",
			isDirectory: true
		)
		try createDirectory(at: stagingDirectory, withIntermediateDirectories: false)
		var removeStagingDirectory = true
		defer {
			if removeStagingDirectory {
				try? removeItem(at: stagingDirectory)
			}
		}
		let staged = stagingDirectory.appendingPathComponent(destination.lastPathComponent)
		let values = try source.resourceValues(forKeys: [.isSymbolicLinkKey, .isApplicationKey, .isPackageKey])
		let shouldLink = values.isSymbolicLink == true ||
			(options.contains(.symlinkPackages) && (values.isApplication == true || values.isPackage == true))
		if shouldLink {
			try createSymbolicLink(at: staged, withDestinationURL: source.resolvingSymlinksInPath())
		} else {
			try copyItem(at: source, to: staged)
		}
		try validate(staged)
		// SWAP leaves the old item in staging; EXCL cannot clobber a racing create.
		let flags = replacing ? UInt32(RENAME_SWAP) : UInt32(RENAME_EXCL)
		guard renamex_np(staged.path, destination.path, flags) == 0 else {
			throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
		}
		if replacing, options.contains(.moveToTrash) {
			do {
				try trashItem(at: staged, resultingItemURL: nil)
			} catch {
				// Publication succeeded. Preserve the old copy if Trash is unavailable.
				removeStagingDirectory = false
				fileOperationLogger
					.error("Installed replacement; previous item retained at \(staged.path, privacy: .public)")
			}
		}
	}

	/// Clears whatever an earlier install left in `parent`.
	///
	/// A staging directory outlives its install exactly once: when the replaced
	/// item could not reach the Trash, it is kept there deliberately. Nothing
	/// else ever collects those, so each install sweeps the ones before it
	/// rather than letting a directory accumulate a copy per failed trash.
	private func removeStagingDirectories(in parent: URL) {
		guard let siblings = try? contentsOfDirectory(
			at: parent,
			includingPropertiesForKeys: nil,
			options: .skipsSubdirectoryDescendants
		) else {
			return
		}

		for sibling in siblings where sibling.lastPathComponent.hasPrefix(stagingDirectoryPrefix) {
			do {
				try removeItem(at: sibling)
			} catch {
				fileOperationLogger.error(
					"""
					Could not clear the staging directory left at \
					[\(sibling.path, privacy: .public)]: \(error.localizedDescription, privacy: .public)
					"""
				)
			}
		}
	}
}

/// Names the directory an install stages into, and the ones it sweeps.
private let stagingDirectoryPrefix = ".glasstual-install-"
