// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import Foundation
@testable import Glasstual
import Testing

/// The Help Book in the built app, the keys that register it with Help
/// Viewer, and the anchors the app opens in it.
@MainActor
@Suite("Help Book")
struct HelpBookTests {
	private static func book() throws -> URL {
		try #require(HelpBook.url(), "The app bundle has no Help Book at CFBundleHelpBookFolder")
	}

	private static func bookInfo() throws -> [String: Any] {
		let data = try Data(contentsOf: book().appending(path: "Contents/Info.plist"))
		return try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
	}

	private static func englishFolder() throws -> URL {
		try book().appending(path: "Contents/Resources/en.lproj", directoryHint: .isDirectory)
	}

	/// Every page of the English book, keyed by its path inside `en.lproj`.
	private static func pages() throws -> [String: String] {
		let folder = try englishFolder()
		let enumerator = try #require(FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil))
		let prefix = folder.standardizedFileURL.path(percentEncoded: false).count
		var pages: [String: String] = [:]
		for case let url as URL in enumerator where url.pathExtension == "html" {
			let path = "/" + url.standardizedFileURL.path(percentEncoded: false).dropFirst(prefix)
				.drop { $0 == "/" }
			pages[path] = try String(contentsOf: url, encoding: .utf8)
		}
		return pages
	}

	private static func anchors(in html: String) -> Set<String> {
		Set(html.matches(of: #/<a name="([^"]+)"/#).map { String($0.output.1) })
	}

	private static func links(in html: String) -> [String] {
		html.matches(of: #/href="([^"#:]+\.html)(?:#[^"]*)?"/#).map { String($0.output.1) }
	}

	@Test("The app's Info.plist names the bundled book by its identifier")
	func infoPlistResolvesToTheBook() throws {
		let info = try Self.bookInfo()

		#expect(Bundle.main.object(forInfoDictionaryKey: HelpBook.folderInfoKey) as? String == "Glasstual.help")
		#expect(HelpBook.name() != nil)
		#expect(info["CFBundleIdentifier"] as? String == HelpBook.name())
		#expect(info["CFBundlePackageType"] as? String == "BNDL")
		#expect(info["HPDBookType"] as? String == "3")
		#expect(info["HPDBookTitle"] as? String == "Glasstual Help")
	}

	@Test("The book's title page and search index are in the bundle")
	func titlePageAndIndexExist() throws {
		let info = try Self.bookInfo()
		let folder = try Self.englishFolder()
		let accessPath = try #require(info["HPDBookAccessPath"] as? String)
		let indexPath = try #require(info["HPDBookCSIndexPath"] as? String)

		let title = try String(contentsOf: folder.appending(path: accessPath), encoding: .utf8)
		#expect(title.contains(#"<meta name="AppleTitle" content="Glasstual Help">"#))

		let index = try FileManager.default.attributesOfItem(atPath: folder.appending(path: indexPath).path(percentEncoded: false))
		#expect((index[.size] as? Int ?? 0) > 0, "The build phase did not write the search index")
	}

	@Test("Every anchor the app opens exists in the book")
	func everyOpenedAnchorExists() throws {
		let anchors = try Self.pages().values.reduce(into: Set<String>()) { $0.formUnion(Self.anchors(in: $1)) }

		for anchor in HelpAnchor.allCases {
			#expect(anchors.contains(anchor.rawValue), "No page has the anchor \(anchor.rawValue)")
		}
	}

	/// Only the title page carries AppleTitle: a second one would register a
	/// second book.
	@Test("Every page has a title and an anchor, and only the title page names the book")
	func pagesAreWellFormed() throws {
		let pages = try Self.pages()
		#expect(pages.count > 1)

		for (path, html) in pages {
			#expect(html.hasPrefix("<!DOCTYPE html>"), "\(path)")
			#expect(html.contains(#"<html lang="en">"#), "\(path)")
			#expect(html.firstMatch(of: #/<title>[^<]+</title>/#) != nil, "\(path) has no title")
			#expect(Self.anchors(in: html).isEmpty == false, "\(path) has no anchor")
			#expect(html.contains("AppleTitle") == (path == "/index.html"), "\(path)")
			#expect(html.contains("<script") == false, "\(path) carries a script")
		}
	}

	@Test("Every link between pages resolves, and every page is reachable from the title page")
	func linksResolve() throws {
		let pages = try Self.pages()
		var reachable: Set = ["/index.html"]
		var queue = ["/index.html"]

		while let path = queue.popLast() {
			let base = URL(filePath: path)
			for link in Self.links(in: pages[path] ?? "") {
				let target = URL(filePath: link, relativeTo: base).standardizedFileURL.path(percentEncoded: false)
				#expect(pages[target] != nil, "\(path) links to \(link), which does not exist")
				if pages[target] != nil, reachable.insert(target).inserted {
					queue.append(target)
				}
			}
		}

		#expect(Set(pages.keys).subtracting(Self.pendingPages) == reachable)
	}

	/** Pages for features still being built on another branch. They stay
	 unlinked and out of search until the feature lands; publishing one means
	 linking it from the title page, dropping its robots tag and removing it
	 from this list. */
	private static let pendingPages: Set<String> = []

	@Test("A pending page stays unlinked and out of the search index")
	func pendingPagesAreNotPublished() throws {
		let pages = try Self.pages()

		for path in Self.pendingPages {
			let page = try #require(pages[path], "\(path) is missing")
			#expect(page.contains(#"<meta name="robots" content="noindex">"#), "\(path)")
			let name = String(path.split(separator: "/").last ?? "")
			#expect(pages.values.allSatisfy { $0.contains(name) == false || $0 == page }, "\(path) is linked")
		}
	}

	@Test("Help ▸ Glasstual Help comes first, with Command-?")
	func helpMenuOpensTheBook() throws {
		_ = MenuActionController()
		let help = try #require(NSApp.mainMenu?.item(for: .glasstualHelp))

		#expect(help.menu === NSApp.helpMenu)
		#expect(help.menu?.items.first === help)
		#expect(help.keyEquivalent == "?")
		#expect(help.keyEquivalentModifierMask == .command)
		#expect(help.action == #selector(MenuActionController.showHelpBook(_:)))
		#expect(help.title == String(localized: .MainWindow.menuHelpGlasstualHelp))
	}
}
