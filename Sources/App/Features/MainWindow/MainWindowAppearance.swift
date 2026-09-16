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
 *********************************************************************** */

import AppKit

/// The shape of `TVCMainWindowAppearance.plist`.
struct MainWindowAppearanceSchema: Decodable, Sendable {
	let defaultWindowSize: AppearanceSize
}

final class MainWindowAppearance: ApplicationAppearance {
	private(set) var textView: MainWindowTextViewAppearance
	private(set) var defaultWindowSize: NSSize = .zero

	@MainActor
	init?() {
		guard let textView = MainWindowTextViewAppearance() else {
			return nil
		}
		self.textView = textView

		super.init(applicationProperties: Self.currentApplicationProperties)

		guard let schema = AppearanceSchema.load(
			MainWindowAppearanceSchema.self,
			resource: "TVCMainWindowAppearance",
			appearanceName: appearanceName
		) else {
			return nil
		}

		defaultWindowSize = schema.defaultWindowSize.size
	}
}
