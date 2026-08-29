/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
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

/** Which style and script resources an inline-content module may put into the
 log view.

 A module returns `styleResources` / `scriptResources` as URLs. File URLs are
 copied into the theme's temporary directory; everything else was previously
 handed to the page verbatim, which let a module load a `<script>` from any
 host. The log view runs from a `file://` document with the native `app`
 bridge attached, so whoever serves that script owns the bridge.

 The host set lives with the log view's Content-Security-Policy in
 `LogViewContentPolicy.permittedScriptOrigins`, so the Swift-side filter and the
 policy the page enforces can never disagree. */
enum InlineResourceHostPolicy {
	static func permits(_ url: URL) -> Bool {
		if url.isFileURL {
			return true
		}
		guard url.scheme?.lowercased() == "https", let host = url.host()?.lowercased() else {
			return false
		}
		return LogViewContentPolicy.permittedScriptOrigins.contains("https://\(host)")
	}
}

extension InlineContentPayload {
	func resourcesTemporaryLocation() -> String {
		let sourcePath = SharedApplication.sharedThemeController().temporaryPath as NSString
		let basePath = sourcePath.appendingPathComponent("/ICLPayload-Resources/")
		PathInfo.createDirectory(atPath: basePath)
		return basePath
	}

	/** WebKit2 uses sandboxed processes. Copy resource files into the
	 application's temporary folder so WebKit can access them. */
	func copyResourcesToTemporaryLocation(_ resources: [URL]?) -> [String]? {
		guard let resources else {
			return nil
		}

		let basePath = resourcesTemporaryLocation() as NSString
		let fileManager = FileManager.default

		func copyOperation(_ resourceURL: URL) -> String? {
			guard InlineResourceHostPolicy.permits(resourceURL) else {
				payloadLogger.error(
					"Refusing inline resource from '\(resourceURL.host() ?? "<no host>", privacy: .public)'"
				)
				return nil
			}

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
				let tildePath = resourcePath.standardizedTildePath
				payloadLogger.error(
					"Copy operation for '\(tildePath, privacy: .public)' failed with error: \(error.localizedDescription, privacy: .public)"
				)

				/* Returning the destination anyway hands WebKit a path to a
				 file that does not exist. */
				return nil
			}

			return destinationPath
		}

		return resources.compactMap { copyOperation($0) }
	}

	public var javaScriptObject: [String: JavaScriptValue] {
		var dictionary: [String: JavaScriptValue] = [
			"contentLength": .integer(Int(contentLength)),
			"contentSize": .object([
				"width": .double(contentSize.width),
				"height": .double(contentSize.height),
			]),
			"html": .string(html),
			"url": .string(url.absoluteString),
			"urlToInline": .string(urlToInline.absoluteString),
			"lineNumber": .string(lineNumber),
			"uniqueIdentifier": .string(uniqueIdentifier),
			"index": .integer(Int(index)),
		]

		if let copiedStyleResources = copyResourcesToTemporaryLocation(styleResources) {
			dictionary["styleResources"] = .array(copiedStyleResources.map(JavaScriptValue.string))
		}
		if let copiedScriptResources = copyResourcesToTemporaryLocation(scriptResources) {
			dictionary["scriptResources"] = .array(copiedScriptResources.map(JavaScriptValue.string))
		}

		if let entrypoint {
			dictionary["entrypoint"] = .string(entrypoint)
			/* Use the property (not storage) so default entrypoint payload values are applied. */
			dictionary["entrypointPayload"] = .object(entrypointPayload)
		}

		return dictionary
	}
}
