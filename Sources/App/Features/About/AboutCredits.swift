// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import PDFKit

/** The credits the standard About panel shows under the version line.

 The panel supplies the icon, name, version and copyright from the bundle, so
 this is only what the bundle cannot say: where the privacy policy and the
 support page are, and the acknowledgements themselves. The panel's credits
 area scrolls, which is where macOS applications keep their acknowledgements,
 so they are read here rather than opened in another application. */
enum AboutCredits {
	/// The project's published policy page, which the website serves.
	private static let privacyPolicyURL = URL(string: "https://vakesz.github.io/Glasstual/privacy.html")!
	/// The project's published support page, which the website serves.
	private static let supportURL = URL(string: "https://vakesz.github.io/Glasstual/support.html")!

	/// The acknowledgements document the bundle carries.
	private static var acknowledgementsURL: URL? {
		Bundle.main.url(forResource: "Acknowledgements", withExtension: "pdf", subdirectory: "Documentation")
	}

	static func make() -> NSAttributedString {
		make(acknowledgements: acknowledgementsURL.flatMap { PDFDocument(url: $0)?.string })
	}

	/** A centred line of links, then the acknowledgements under their heading.
	 The section is left out when there is no text to show, rather than a
	 heading over nothing. */
	static func make(acknowledgements: String?) -> NSAttributedString {
		let centred = NSMutableParagraphStyle()
		centred.alignment = .center

		let font = NSFont.preferredFont(forTextStyle: .caption1)
		let credits = NSMutableAttributedString()
		let links = [
			(String(localized: .About.privacyPolicyLink), privacyPolicyURL),
			(String(localized: .About.supportLink), supportURL),
		]

		for (index, link) in links.enumerated() {
			if index > 0 {
				credits.append(NSAttributedString(string: "  ·  ", attributes: [
					.font: font,
					.foregroundColor: NSColor.secondaryLabelColor,
					.paragraphStyle: centred,
				]))
			}
			credits.append(NSAttributedString(string: link.0, attributes: [
				.font: font,
				.link: link.1,
				.paragraphStyle: centred,
			]))
		}

		let text = acknowledgements?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
		guard text.isEmpty == false else { return credits }

		let body = NSMutableParagraphStyle()
		body.paragraphSpacing = font.pointSize / 2

		credits.append(NSAttributedString(string: "\n\n" + String(localized: .About.acknowledgementsButton) + "\n", attributes: [
			.font: NSFont.systemFont(ofSize: font.pointSize, weight: .semibold),
			.foregroundColor: NSColor.labelColor,
			.paragraphStyle: centred,
		]))
		credits.append(NSAttributedString(string: text, attributes: [
			.font: font,
			.foregroundColor: NSColor.secondaryLabelColor,
			.paragraphStyle: body,
		]))

		return credits
	}
}
