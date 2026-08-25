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

private enum FileOperationOptions {
	static let removeIfExists: UInt = 1 << 1
	static let enumerateDirectories: UInt = 1 << 2
	static let createDirectory: UInt = 1 << 3
	static let continueOnError: UInt = 1 << 4
	static let moveToTrash: UInt = 1 << 5
	static let moveToDestination: UInt = 1 << 6
	static let includeDotFiles: UInt = 1 << 7
	static let symlinkPackages: UInt = 1 << 8
}

public extension FileManager {
	@objc class var pathOfHomeDirectoryOutsideSandbox: String {
		guard let password = getpwuid(getuid()), let directory = password.pointee.pw_dir else {
			return NSHomeDirectory()
		}
		return String(cString: directory)
	}

	@objc class var URLOfHomeDirectoryOutsideSandbox: URL {
		URL(fileURLWithPath: pathOfHomeDirectoryOutsideSandbox, isDirectory: true)
	}

	@objc(fileExistsAtURL:)
	func fileExists(at url: URL) -> Bool {
		fileExists(atPath: url.path)
	}

	@objc(directoryExistsAtURL:)
	func directoryExists(at url: URL) -> Bool {
		directoryExists(atPath: url.path)
	}

	@objc(directoryExistsAtPath:)
	func directoryExists(atPath path: String) -> Bool {
		var isDirectory = ObjCBool(false)
		return fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
	}

	@objc(buildPathArrayWithPaths:)
	func buildPathArray(with paths: [String]) -> [String] {
		paths.filter { $0.isEmpty == false && directoryExists(atPath: $0) }
	}

	@objc(replaceItemAtURL:withItemAtURL:)
	func replaceItem(at destination: URL, withItemAt source: URL) -> Bool {
		replaceItem(
			at: destination,
			withItemAt: source,
			options: FileOperationOptions.moveToTrash | FileOperationOptions.removeIfExists
		)
	}

	@objc(replaceItemAtURL:withItemAtURL:options:)
	func replaceItem(at destination: URL, withItemAt source: URL, options: UInt) -> Bool {
		guard source.isFileURL, destination.isFileURL else { return false }
		do {
			if fileExists(at: destination) {
				guard options & FileOperationOptions.removeIfExists != 0 else { return true }
				try removeItem(at: destination, movingToTrash: options & FileOperationOptions.moveToTrash != 0)
			}

			let values = try source.resourceValues(forKeys: [.isSymbolicLinkKey, .isApplicationKey, .isPackageKey])
			let shouldLink = values.isSymbolicLink == true ||
				(options & FileOperationOptions.symlinkPackages != 0 &&
					(values.isApplication == true || values.isPackage == true))
			if shouldLink {
				try createSymbolicLink(at: destination, withDestinationURL: source.resolvingSymlinksInPath())
			} else if options & FileOperationOptions.moveToDestination != 0 {
				try moveItem(at: source, to: destination)
			} else {
				try copyItem(at: source, to: destination)
			}
			return true
		} catch {
			return false
		}
	}

	@objc(mergeDirectoryAtURL:withDirectoryAtURL:options:)
	func mergeDirectory(at source: URL, withDirectoryAt destination: URL, options: UInt) -> Bool {
		mergeItem(at: source, into: destination, options: options, depth: 0)
	}

	@objc(removeContentsOfDirectoryAtURL:options:)
	func removeContents(ofDirectoryAt url: URL, options: UInt) -> Bool {
		removeContents(ofDirectoryAt: url, excluding: nil, options: options)
	}

	@objc(removeContentsOfDirectoryAtURL:excludingURLs:options:)
	func removeContents(ofDirectoryAt url: URL, excluding urls: [URL]?, options: UInt) -> Bool {
		guard url.isFileURL, directoryExists(at: url) else { return false }
		let exclusions = Set(urls ?? [])
		do {
			let children = try contentsOfDirectory(
				at: url,
				includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey]
			)
			var succeeded = true
			for child in children where exclusions.contains(child) == false {
				do {
					try removeTree(
						at: child,
						exclusions: exclusions,
						moveToTrash: options & FileOperationOptions.moveToTrash != 0
					)
				} catch {
					succeeded = false
					if options & FileOperationOptions.continueOnError == 0 {
						return false
					}
				}
			}
			return succeeded
		} catch {
			return false
		}
	}

	private func mergeItem(at source: URL, into destination: URL, options: UInt, depth: Int) -> Bool {
		guard source.isFileURL, destination.isFileURL else { return false }
		do {
			let values = try source.resourceValues(forKeys: [
				.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .isApplicationKey, .isPackageKey,
			])
			guard depth > 0 || values.isDirectory == true else { return false }
			let isContainedDirectory = values.isDirectory == true && values.isApplication != true && values
				.isPackage != true
			if isContainedDirectory == false || depth > 0 && options & FileOperationOptions.enumerateDirectories == 0 {
				return replaceItem(at: destination, withItemAt: source, options: options)
			}
			if options & FileOperationOptions.createDirectory != 0 {
				try createDirectory(at: destination, withIntermediateDirectories: true)
			}
			let children = try contentsOfDirectory(at: source, includingPropertiesForKeys: [
				.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .isApplicationKey, .isPackageKey,
			])
			for child in children {
				if options & FileOperationOptions.includeDotFiles == 0,
				   child.lastPathComponent.hasPrefix(".")
				{
					continue
				}
				let childDestination = destination.appendingPathComponent(child.lastPathComponent)
				if mergeItem(at: child, into: childDestination, options: options, depth: depth + 1) == false,
				   options & FileOperationOptions.continueOnError == 0
				{
					return false
				}
			}
			return true
		} catch {
			return false
		}
	}

	private func removeTree(at url: URL, exclusions: Set<URL>, moveToTrash: Bool) throws {
		guard exclusions.contains(url) == false else { return }
		let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isApplicationKey, .isPackageKey])
		if values.isDirectory == true, values.isApplication != true, values.isPackage != true {
			for child in try contentsOfDirectory(at: url, includingPropertiesForKeys: nil) {
				try removeTree(at: child, exclusions: exclusions, moveToTrash: moveToTrash)
			}
			if try contentsOfDirectory(atPath: url.path).isEmpty == false {
				return
			}
		}
		try removeItem(at: url, movingToTrash: moveToTrash)
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
