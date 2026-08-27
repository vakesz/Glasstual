/* *********************************************************************
 *
 *         Copyright (c) 2016 - 2020 Codeux Software, LLC
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

import Foundation
import os

public extension NSURL {
	@objc(resourceValueForKey:)
	func textual_resourceValue(forKey key: String) -> Any? {
		textual_resourceValue(forKey: key, error: nil)
	}

	@objc(resourceValueForKey:error:)
	func textual_resourceValue(forKey key: String, error errorPointer: NSErrorPointer) -> Any? {
		var value: AnyObject?
		do {
			try getResourceValue(&value, forKey: URLResourceKey(rawValue: key))
			return value
		} catch {
			errorPointer?.pointee = error as NSError
			return nil
		}
	}

	@objc(resourceValueForKeyWithLoggedError:)
	func textual_resourceValueWithLoggedError(forKey key: String) -> Any? {
		var error: NSError?
		let value = textual_resourceValue(forKey: key, error: &error)

		if let error {
			let displayURL = textualStandardizedTildePath ?? absoluteString ?? ""
			Logging.frameworkSubsystem?.error(
				"Resource value [\(key, privacy: .public)] could not be accessed for URL [\(displayURL, privacy: .public)]: \(error.localizedDescription, privacy: .public)"
			)
		}

		return value
	}

	@objc(resourceValuesForKeyWithLoggedError:)
	func textual_resourceValuesWithLoggedError(forKeys keys: [URLResourceKey]) -> [URLResourceKey: Any]? {
		do {
			return try (self as URL).resourceValues(forKeys: Set(keys)).allValues
		} catch {
			let keyList = keys.map(\.rawValue).joined(separator: ", ")
			let displayURL = textualStandardizedTildePath ?? absoluteString ?? ""
			Logging.frameworkSubsystem?.error(
				"Resource values [\(keyList, privacy: .public)] could not be accessed for URL [\(displayURL, privacy: .public)]: \(error.localizedDescription, privacy: .public)"
			)
			return nil
		}
	}

	@objc(filesystemRepresentationString)
	var textualFilesystemRepresentationString: String? {
		guard isFileURL else { return nil }
		let representation = fileSystemRepresentation
		return FileManager.default.string(
			withFileSystemRepresentation: representation,
			length: strlen(representation)
		)
	}

	@objc(isEqualByFileRepresentation:)
	func textual_isEqualByFileRepresentation(to otherURL: URL) -> Bool {
		precondition(otherURL.isFileURL)
		return strcmp(fileSystemRepresentation, (otherURL as NSURL).fileSystemRepresentation) == 0
	}

	@objc(intervalSinceCreatedWithError:)
	func textual_intervalSinceCreated(error errorPointer: NSErrorPointer) -> TimeInterval {
		let date = textual_resourceValue(forKey: URLResourceKey.creationDateKey.rawValue, error: errorPointer) as? Date
		return -(date ?? .distantFuture).timeIntervalSinceNow
	}

	@objc(intervalSinceLastModificationWithError:)
	func textual_intervalSinceLastModification(error errorPointer: NSErrorPointer) -> TimeInterval {
		let date = textual_resourceValue(
			forKey: URLResourceKey.contentModificationDateKey.rawValue,
			error: errorPointer
		) as? Date
		return -(date ?? .distantFuture).timeIntervalSinceNow
	}

	@objc(standardizedTildePath)
	var textualStandardizedTildePath: String? {
		guard isFileURL, let path else { return nil }
		return (path as NSString).ceStandardizedTildePath as String?
	}
}

public extension NSArray {
	@objc(pathsArrayForFileURLs:)
	class func textual_pathsArray(forFileURLs fileURLs: [URL]) -> [String] {
		textual_pathsArray(forFileURLs: fileURLs, standardizingPaths: true)
	}

	@objc(pathsArrayForFileURLs:standardizingPaths:)
	class func textual_pathsArray(forFileURLs fileURLs: [URL], standardizingPaths: Bool) -> [String] {
		fileURLs.map { url in
			precondition(url.isFileURL, "URL '\(url)' is not a file")
			return standardizingPaths ? url.standardizedFileURL.path : url.path
		}
	}
}
