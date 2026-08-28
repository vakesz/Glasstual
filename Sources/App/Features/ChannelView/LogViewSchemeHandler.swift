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

import Foundation
import os
import UniformTypeIdentifiers
import WebKit

private let schemeHandlerLogger = Logger(
	subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
	category: "LogViewSchemeHandler"
)

/** Serves the log view's document and every theme resource it references.

 Themes and templates write absolute file-system paths into `src` and `href`
 attributes, so a theme URL's path *is* that file-system path. The handler only
 reads below the directories `permittedRoots` names, which replaces the private
 `_setAllowUniversalAccessFromFileURLs:` pair the view used to rely on: the
 document has one origin, and no origin has file-system read access.

 Rendered documents are held in memory and served from there, so nothing is
 written into the theme's temporary directory any more. */
@MainActor
@objc(TVCLogViewSchemeHandler)
public final class LogViewThemeSchemeHandler: NSObject, WKURLSchemeHandler {
	public static let shared = LogViewThemeSchemeHandler()

	private let permittedRoots: @MainActor () -> [URL]
	private var documents: [String: Data] = [:]
	private var staleDocumentsRemoved = false

	init(permittedRoots: @escaping @MainActor () -> [URL] = LogViewThemeSchemeHandler.themeRoots) {
		self.permittedRoots = permittedRoots
		super.init()
	}

	/** The theme's temporary copy, its source (a variety's own resources are
	 not always remapped into the copy) and the application's own resources. */
	static func themeRoots() -> [URL] {
		var roots = [PathInfo.applicationResourcesURL]
		if let theme = SharedApplication.sharedThemeController().theme {
			roots.append(theme.temporaryURL)
			roots.append(theme.originalURL)
		}
		return roots
	}

	// MARK: Documents

	/** Registers a rendered document so that `url` serves it. */
	func registerDocument(_ html: String, at url: URL) {
		documents[url.absoluteString] = Data(html.utf8)
	}

	func unregisterDocument(at url: URL) {
		documents.removeValue(forKey: url.absoluteString)
	}

	/** Builds this view's document URL inside `baseURL`, which is the theme's
	 temporary directory. Relative references in the document then resolve
	 against the theme just as they did while it was a `file:` document. */
	func documentURL(forViewIdentifier identifier: String, in baseURL: URL) -> URL? {
		let path = baseURL
			.appending(path: "\(identifier).html")
			.standardizedFileURL
			.path(percentEncoded: false)
		return LogViewContentPolicy.resourceURL(forFilePath: path)
	}

	/** Earlier builds wrote a fresh `<UUID>.html` into the theme's temporary
	 directory on every load and never deleted any of them. */
	func removeStaleRenderedDocuments(in directoryURL: URL) {
		guard staleDocumentsRemoved == false else {
			return
		}
		staleDocumentsRemoved = true

		let contents = try? FileManager.default.contentsOfDirectory(
			at: directoryURL,
			includingPropertiesForKeys: nil,
			options: [.skipsSubdirectoryDescendants]
		)
		for url in contents ?? [] where Self.isRenderedDocumentName(url.lastPathComponent) {
			do {
				try FileManager.default.removeItem(at: url)
			} catch {
				schemeHandlerLogger.error(
					"Failed to remove stale rendered document: \(error.localizedDescription, privacy: .public)"
				)
			}
		}
	}

	private static func isRenderedDocumentName(_ name: String) -> Bool {
		guard name.hasSuffix(".html") else {
			return false
		}
		return UUID(uuidString: String(name.dropLast(5))) != nil
	}

	// MARK: Serving

	public func webView(_: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
		guard let url = urlSchemeTask.request.url else {
			fail(urlSchemeTask, url: nil, code: .badURL)
			return
		}

		if let document = documents[url.absoluteString] {
			respond(to: urlSchemeTask, url: url, data: document, mimeType: "text/html; charset=utf-8", isDocument: true)
			return
		}

		guard let path = LogViewContentPolicy.filePath(for: url) else {
			fail(urlSchemeTask, url: url, code: .unsupportedURL)
			return
		}

		let fileURL = URL(fileURLWithPath: path)
		guard permitsReading(fileURL) else {
			schemeHandlerLogger.error("Refused theme resource outside the permitted roots: \(path, privacy: .public)")
			fail(urlSchemeTask, url: url, code: .noPermissionsToReadFile)
			return
		}

		guard let data = try? Data(contentsOf: fileURL, options: [.mappedIfSafe]) else {
			fail(urlSchemeTask, url: url, code: .fileDoesNotExist)
			return
		}

		respond(to: urlSchemeTask, url: url, data: data, mimeType: Self.mimeType(for: fileURL), isDocument: false)
	}

	/** Every response is delivered before `start` returns, so there is never a
	 task in flight to stop. */
	public func webView(_: WKWebView, stop _: any WKURLSchemeTask) {}

	private func respond(
		to task: any WKURLSchemeTask,
		url: URL,
		data: Data,
		mimeType: String,
		isDocument: Bool
	) {
		var headers = [
			"Content-Type": mimeType,
			"Content-Length": String(data.count),
			"X-Content-Type-Options": "nosniff",
			"Cache-Control": "no-store",
		]
		/* A style may replace baseLayout.mustache and with it the <meta>
		 element, so the document also carries the policy as a header. */
		if isDocument {
			headers["Content-Security-Policy"] = LogViewContentPolicy.contentSecurityPolicy
		}

		guard
			let response = HTTPURLResponse(
				url: url,
				statusCode: 200,
				httpVersion: "HTTP/1.1",
				headerFields: headers
			)
		else {
			fail(task, url: url, code: .cannotParseResponse)
			return
		}

		task.didReceive(response)
		task.didReceive(data)
		task.didFinish()
	}

	private func fail(_ task: any WKURLSchemeTask, url: URL?, code: URLError.Code) {
		var userInfo: [String: Any] = [:]
		if let url {
			userInfo[NSURLErrorFailingURLErrorKey] = url
		}
		task.didFailWithError(NSError(domain: NSURLErrorDomain, code: code.rawValue, userInfo: userInfo))
	}

	// MARK: Policy

	/** Symbolic links are resolved on both sides, so a link inside the theme
	 that points outside it is refused rather than followed. */
	func permitsReading(_ fileURL: URL) -> Bool {
		let candidate = Self.normalizedPath(fileURL)
		return permittedRoots().contains { root in
			let rootPath = Self.normalizedPath(root)
			if candidate == rootPath {
				return true
			}
			let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
			return candidate.hasPrefix(prefix)
		}
	}

	private static func normalizedPath(_ url: URL) -> String {
		url.resolvingSymlinksInPath().standardizedFileURL.path(percentEncoded: false)
	}

	static func mimeType(for url: URL) -> String {
		switch url.pathExtension.lowercased() {
		case "css":
			return "text/css; charset=utf-8"
		case "js", "mjs":
			return "text/javascript; charset=utf-8"
		case "html", "htm":
			return "text/html; charset=utf-8"
		case "json":
			return "application/json"
		case "svg":
			return "image/svg+xml"
		case "woff":
			return "font/woff"
		case "woff2":
			return "font/woff2"
		case "ttf":
			return "font/ttf"
		case "otf":
			return "font/otf"
		default:
			break
		}
		guard
			let type = UTType(filenameExtension: url.pathExtension),
			let mimeType = type.preferredMIMEType
		else {
			return "application/octet-stream"
		}
		return mimeType
	}
}
