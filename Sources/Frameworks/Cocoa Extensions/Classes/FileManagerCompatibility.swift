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

	/// Move the source instead of copying it.
	public static let moveToDestination = FileOperationOptions(rawValue: 1 << 6)

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

	func directoryExists(at url: URL) -> Bool {
		directoryExists(atPath: url.path)
	}

	func directoryExists(atPath path: String) -> Bool {
		var isDirectory = ObjCBool(false)
		return fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
	}

	func replaceItem(at destination: URL, withItemAt source: URL) -> Bool {
		replaceItem(at: destination, withItemAt: source, options: [.moveToTrash, .removeIfExists])
	}

	/// Puts `source` where `destination` is, copying, moving or linking it
	/// depending on `options`. Theme and plugin installation run through here,
	/// so a failure is logged rather than swallowed into a bare `false`.
	func replaceItem(at destination: URL, withItemAt source: URL, options: FileOperationOptions) -> Bool {
		guard source.isFileURL, destination.isFileURL else {
			fileOperationLogger.error("Refusing to replace a non-file URL")
			return false
		}

		do {
			if fileExists(at: destination) {
				guard options.contains(.removeIfExists) else {
					fileOperationLogger.error(
						"Destination [\(destination.standardizedTildePath ?? "", privacy: .public)] already exists"
					)
					return false
				}

				try removeItem(at: destination, movingToTrash: options.contains(.moveToTrash))
			}

			try createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)

			let values = try source.resourceValues(forKeys: [.isSymbolicLinkKey, .isApplicationKey, .isPackageKey])
			let shouldLink = values.isSymbolicLink == true ||
				(options.contains(.symlinkPackages) &&
					(values.isApplication == true || values.isPackage == true))
			if shouldLink {
				try createSymbolicLink(at: destination, withDestinationURL: source.resolvingSymlinksInPath())
			} else if options.contains(.moveToDestination) {
				try moveItem(at: source, to: destination)
			} else {
				try copyItem(at: source, to: destination)
			}
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

	private func removeItem(at url: URL, movingToTrash: Bool) throws {
		if movingToTrash {
			var resultingURL: NSURL?
			try trashItem(at: url, resultingItemURL: &resultingURL)
		} else {
			try removeItem(at: url)
		}
	}
}
