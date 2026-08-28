/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation
@testable import Glasstual
import Testing
import WebKit

/// Records what the handler answered. `WKURLSchemeTask` is a protocol, so the
/// handler can be driven without a web view.
@MainActor
private final class RecordingURLSchemeTask: NSObject, WKURLSchemeTask {
	let request: URLRequest
	private(set) var response: URLResponse?
	private(set) var body = Data()
	private(set) var failure: (any Error)?
	private(set) var didFinishLoading = false

	init(url: URL) {
		request = URLRequest(url: url)
		super.init()
	}

	var httpResponse: HTTPURLResponse? {
		response as? HTTPURLResponse
	}

	var failureCode: Int? {
		(failure as? NSError)?.code
	}

	func didReceive(_ response: URLResponse) {
		self.response = response
	}

	func didReceive(_ data: Data) {
		body.append(data)
	}

	func didFinish() {
		didFinishLoading = true
	}

	func didFailWithError(_ error: any Error) {
		failure = error
	}
}

/// One web view for the whole suite: the handler ignores it, but the protocol
/// requires one.
@MainActor
private enum SchemeHandlerTestSupport {
	static let webView = WKWebView()
}

@MainActor
@Suite("Log view theme scheme handler")
final class LogViewThemeSchemeHandlerTests {
	private let root: URL
	private let handler: LogViewThemeSchemeHandler

	init() throws {
		let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
			.appending(path: "LogViewThemeSchemeHandlerTests-\(UUID().uuidString)", directoryHint: .isDirectory)
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

		self.root = root
		handler = LogViewThemeSchemeHandler(permittedRoots: { [root] })
	}

	deinit {
		try? FileManager.default.removeItem(at: root)
	}

	private func write(_ contents: String, to relativePath: String) throws -> URL {
		let url = root.appending(path: relativePath)
		try FileManager.default.createDirectory(
			at: url.deletingLastPathComponent(),
			withIntermediateDirectories: true
		)
		try contents.write(to: url, atomically: true, encoding: .utf8)
		return url
	}

	private func run(_ url: URL) -> RecordingURLSchemeTask {
		let task = RecordingURLSchemeTask(url: url)
		handler.webView(SchemeHandlerTestSupport.webView, start: task)
		return task
	}

	private func themeURL(for fileURL: URL) throws -> URL {
		try #require(LogViewContentPolicy.resourceURL(forFilePath: fileURL.path(percentEncoded: false)))
	}

	@Test("A registered document is served from memory with the content policy")
	func registeredDocumentIsServedWithThePolicy() throws {
		let documentURL = try #require(handler.documentURL(forViewIdentifier: "view", in: root))
		handler.registerDocument("<html><body>hi</body></html>", at: documentURL)

		let task = run(documentURL)
		let response = try #require(task.httpResponse)

		#expect(task.failure == nil)
		#expect(task.didFinishLoading)
		#expect(String(data: task.body, encoding: .utf8) == "<html><body>hi</body></html>")
		#expect(response.value(forHTTPHeaderField: "Content-Type") == "text/html; charset=utf-8")
		#expect(
			response.value(forHTTPHeaderField: "Content-Security-Policy")
				== LogViewContentPolicy.contentSecurityPolicy
		)
	}

	@Test("An unregistered document is a miss rather than a read of the theme directory")
	func unregisteredDocumentIsAMiss() throws {
		let documentURL = try #require(handler.documentURL(forViewIdentifier: "view", in: root))
		handler.registerDocument("<html></html>", at: documentURL)
		handler.unregisterDocument(at: documentURL)

		let task = run(documentURL)

		#expect(task.failureCode == URLError.Code.fileDoesNotExist.rawValue)
		#expect(task.response == nil)
	}

	@Test("A resource under a permitted root is served with its media type")
	func resourceUnderAPermittedRootIsServed() throws {
		let fileURL = try write("body { }", to: "Varieties/Light/design.css")

		let task = try run(themeURL(for: fileURL))
		let response = try #require(task.httpResponse)

		#expect(task.failure == nil)
		#expect(String(data: task.body, encoding: .utf8) == "body { }")
		#expect(response.value(forHTTPHeaderField: "Content-Type") == "text/css; charset=utf-8")
		#expect(response.value(forHTTPHeaderField: "X-Content-Type-Options") == "nosniff")
		/* Only the document carries the policy; a subresource does not. */
		#expect(response.value(forHTTPHeaderField: "Content-Security-Policy") == nil)
	}

	@Test("A path with characters that need escaping still resolves")
	func escapedPathResolves() throws {
		let fileURL = try write("/* a b */", to: "a b/ünïcode.css")

		let task = try run(themeURL(for: fileURL))

		#expect(task.failure == nil)
		#expect(String(data: task.body, encoding: .utf8) == "/* a b */")
	}

	@Test("A missing file below a permitted root fails the task")
	func missingFileFailsTheTask() throws {
		let url = try #require(
			LogViewContentPolicy
				.resourceURL(forFilePath: root.appending(path: "absent.css").path(percentEncoded: false))
		)

		let task = run(url)

		#expect(task.failureCode == URLError.Code.fileDoesNotExist.rawValue)
		#expect(task.didFinishLoading == false)
	}

	@Test("A file outside every permitted root is refused")
	func fileOutsideThePermittedRootsIsRefused() throws {
		let outside = root.deletingLastPathComponent().appending(path: "outside-\(UUID().uuidString).css")
		try "body { }".write(to: outside, atomically: true, encoding: .utf8)
		defer { try? FileManager.default.removeItem(at: outside) }

		let task = try run(themeURL(for: outside))

		#expect(task.failureCode == URLError.Code.noPermissionsToReadFile.rawValue)
	}

	@Test("Traversal out of a permitted root is refused")
	func traversalIsRefused() throws {
		let outside = root.deletingLastPathComponent().appending(path: "outside-\(UUID().uuidString).css")
		try "body { }".write(to: outside, atomically: true, encoding: .utf8)
		defer { try? FileManager.default.removeItem(at: outside) }

		let traversal = root.path(percentEncoded: false) + "/../" + outside.lastPathComponent
		let url = try #require(LogViewContentPolicy.resourceURL(forFilePath: traversal))

		let task = run(url)

		#expect(task.failureCode == URLError.Code.noPermissionsToReadFile.rawValue)
	}

	@Test("A symbolic link that leaves a permitted root is refused")
	func symbolicLinkEscapeIsRefused() throws {
		let outside = root.deletingLastPathComponent().appending(path: "outside-\(UUID().uuidString).css")
		try "body { }".write(to: outside, atomically: true, encoding: .utf8)
		defer { try? FileManager.default.removeItem(at: outside) }

		let link = root.appending(path: "link.css")
		try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)

		let task = try run(themeURL(for: link))

		#expect(task.failureCode == URLError.Code.noPermissionsToReadFile.rawValue)
	}

	@Test("A request in another scheme is refused")
	func foreignSchemeIsRefused() throws {
		let task = try run(#require(URL(string: "https://example.com/design.css")))

		#expect(task.failureCode == URLError.Code.unsupportedURL.rawValue)
	}

	@Test("Documents rendered by earlier builds are deleted once")
	func staleRenderedDocumentsAreDeleted() throws {
		let stale = try write("<html></html>", to: "\(UUID().uuidString).html")
		let kept = try write("<html></html>", to: "index.html")
		let keptResource = try write("body { }", to: "design.css")

		handler.removeStaleRenderedDocuments(in: root)

		#expect(FileManager.default.fileExists(atPath: stale.path(percentEncoded: false)) == false)
		#expect(FileManager.default.fileExists(atPath: kept.path(percentEncoded: false)))
		#expect(FileManager.default.fileExists(atPath: keptResource.path(percentEncoded: false)))
	}

	@Test(
		"Media types cover the resource kinds a style ships",
		arguments: [
			("design.css", "text/css; charset=utf-8"),
			("scripts.js", "text/javascript; charset=utf-8"),
			("icon.svg", "image/svg+xml"),
			("icon.png", "image/png"),
			("lock.tiff", "image/tiff"),
			("face.woff2", "font/woff2"),
			("settings.json", "application/json"),
			("unknown.qqq", "application/octet-stream"),
		]
	)
	func mediaTypesAreCorrect(filename: String, mimeType: String) {
		#expect(LogViewThemeSchemeHandler.mimeType(for: URL(fileURLWithPath: "/\(filename)")) == mimeType)
	}
}
