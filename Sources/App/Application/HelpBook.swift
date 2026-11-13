// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import Foundation

/// A place in the Help Book the app opens. The raw value is the anchor's
/// `name` on its page, and the Help Book tests check that each one exists.
enum HelpAnchor: String, CaseIterable, Sendable {
	/// The title page, which Help ▸ Glasstual Help opens.
	case home = "glasstual-help"
}

/** The Help Book bundled in the app's resources.

 Help Viewer finds the book through two Info.plist keys: the folder that holds
 it and its bundle identifier, which is also the book name `NSHelpManager`
 takes. The Help menu's search field comes from AppKit once the book is
 registered; nothing here builds it. */
enum HelpBook {
	static let folderInfoKey = "CFBundleHelpBookFolder"
	static let nameInfoKey = "CFBundleHelpBookName"

	/// The book's name as the bundle declares it.
	static func name(in bundle: Bundle = .main) -> String? {
		bundle.object(forInfoDictionaryKey: nameInfoKey) as? String
	}

	/// The book's folder inside the bundle's resources, if it is there.
	static func url(in bundle: Bundle = .main) -> URL? {
		guard let folder = bundle.object(forInfoDictionaryKey: folderInfoKey) as? String,
		      let url = bundle.resourceURL?.appending(path: folder, directoryHint: .isDirectory),
		      FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
		else {
			return nil
		}
		return url
	}

	/// Opens the Help viewer at `anchor`.
	static func open(_ anchor: HelpAnchor) {
		SystemHandoff.openHelp(anchor: anchor.rawValue, book: name())
	}
}
