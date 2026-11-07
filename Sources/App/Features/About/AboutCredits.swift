// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit

/** The credits the standard About panel shows under the version line.

 The panel supplies the icon, name, version and copyright from the bundle, so
 this is only what the bundle cannot say: where the acknowledgements, the
 privacy policy and the support page are. */
enum AboutCredits {
	/// The project's published policy page, which the website serves.
	private static let privacyPolicyURL = URL(string: "https://vakesz.github.io/Glasstual/privacy.html")!
	/// The project's published support page, which the website serves.
	private static let supportURL = URL(string: "https://vakesz.github.io/Glasstual/support.html")!

	/// One centred line of links. The acknowledgements link is left out when the
	/// bundle does not carry the document, rather than pointing nowhere.
	static func make() -> NSAttributedString {
		var links: [(title: String, destination: URL)] = []

		if let acknowledgements = Bundle.main.url(
			forResource: "Acknowledgements",
			withExtension: "pdf",
			subdirectory: "Documentation"
		) {
			links.append((String(localized: .About.acknowledgementsButton), acknowledgements))
		}
		links.append((String(localized: .About.privacyPolicyLink), privacyPolicyURL))
		links.append((String(localized: .About.supportLink), supportURL))

		let paragraph = NSMutableParagraphStyle()
		paragraph.alignment = .center

		let font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
		let credits = NSMutableAttributedString()

		for (index, link) in links.enumerated() {
			if index > 0 {
				credits.append(NSAttributedString(string: "  ·  ", attributes: [
					.font: font,
					.foregroundColor: NSColor.secondaryLabelColor,
					.paragraphStyle: paragraph,
				]))
			}
			credits.append(NSAttributedString(string: link.title, attributes: [
				.font: font,
				.link: link.destination,
				.paragraphStyle: paragraph,
			]))
		}

		return credits
	}
}
