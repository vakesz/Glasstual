/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\\_\\__|\\__,_|\\__,_|_|
 *
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

import CocoaExtensions
import CryptoKit
import Foundation
import InlineContentKit
import os

private let payloadLogger = Logger(
	subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
	category: "ICLPayload"
)

extension InlineContentPayload {
	@objc(_resourcesTemporaryLocation)
	func resourcesTemporaryLocation() -> String {
		let sourcePath = SharedApplication.sharedThemeController().temporaryPath as NSString
		let basePath = sourcePath.appendingPathComponent("/ICLPayload-Resources/")
		PathInfo.createDirectory(atPath: basePath)
		return basePath
	}

	/** WebKit2 uses sandboxed processes. Copy resource files into the
	 application's temporary folder so WebKit can access them. */
	@objc(_copyResourcesToTemporaryLocation:)
	func copyResourcesToTemporaryLocation(_ resources: [URL]?) -> [String]? {
		guard let resources else {
			return nil
		}

		let basePath = resourcesTemporaryLocation() as NSString
		let fileManager = FileManager.default

		func copyOperation(_ resourceURL: URL) -> String {
			guard resourceURL.isFileURL else {
				return resourceURL.absoluteString
			}

			let resourcePath = resourceURL.path(percentEncoded: false)
			let resourceHash = SHA256.hash(data: Data(resourcePath.utf8))
				.map { String(format: "%02x", $0) }
				.joined()
			let filename = "\(resourceHash).\(resourceURL.pathExtension)"
			let destinationPath = basePath.appendingPathComponent(filename)

			if fileManager.fileExists(atPath: destinationPath) {
				return destinationPath
			}

			do {
				try fileManager.copyItem(atPath: resourcePath, toPath: destinationPath)
			} catch {
				let tildePath = (resourcePath as NSString).ceStandardizedTildePath as String? ?? resourcePath
				payloadLogger.error(
					"Copy operation for '\(tildePath, privacy: .public)' failed with error: \(error.localizedDescription, privacy: .public)"
				)
			}

			return destinationPath
		}

		return resources.map { copyOperation($0) }
	}

	@objc public var javaScriptObject: [String: Any] {
		var dictionary: [String: Any] = [
			"contentLength": UInt(contentLength),
			"contentSize": [
				"width": contentSize.width,
				"height": contentSize.height,
			],
			"html": html,
			"url": url,
			"urlToInline": urlToInline,
			"lineNumber": lineNumber,
			"uniqueIdentifier": uniqueIdentifier,
			"index": index,
		]

		if let copiedStyleResources = copyResourcesToTemporaryLocation(styleResources) {
			dictionary["styleResources"] = copiedStyleResources
		}
		if let copiedScriptResources = copyResourcesToTemporaryLocation(scriptResources) {
			dictionary["scriptResources"] = copiedScriptResources
		}

		if let entrypoint {
			dictionary["entrypoint"] = entrypoint
			/* Use the property (not storage) so default entrypoint payload values are applied. */
			dictionary["entrypointPayload"] = entrypointPayload
		}

		return dictionary
	}
}
