// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
import os

private nonisolated let inlineMediaLogger = Logger(
	subsystem: LogSubsystem.current,
	category: "TranscriptController"
)

extension TranscriptController {
	func processInlineMedia(_ links: [LinkParserResult], atLineNumber lineNumber: String) {
		for link in links {
			processInlineMediaAtAddress(
				link.stringValue,
				withUniqueIdentifier: link.uniqueIdentifier,
				atLineNumber: lineNumber
			)
		}
	}

	@discardableResult
	func processInlineMediaAtAddress(
		_ address: String,
		withUniqueIdentifier linkIdentifier: String,
		atLineNumber lineNumber: String
	) -> UUID? {
		/* The link parser's scheme set is user-extensible, so an address that
		 became clickable is not necessarily one the inline-content service can
		 handle. It only ever fetches over HTTP, and aborts on a file: URL. */
		guard let url = URL(string: address), LinkSchemeRules.isWebURL(url),
		      backingView?.containsLine(identifier: lineNumber) == true else { return nil }
		let generation = renderScheduler.generation
		let loader = inlineImageLoader
		// Only admission failures run synchronously; successful callbacks receive the assigned token.
		var requestIdentifier: UUID?
		requestIdentifier = loader.load(
			url: url,
			viewIdentifier: uniqueIdentifier,
			lineNumber: lineNumber,
			linkIdentifier: linkIdentifier
		) { [weak self] result in
			switch result {
			case let .success(image):
				guard let self, acceptsRenderGeneration(generation), backingView?.addInlineImage(image) == true else {
					if let requestIdentifier {
						loader.cancelLoad(requestIdentifier)
					}
					return
				}
			case let .failure(error):
				let reason = (error as? InlineImageError)?.logDescription ?? error.localizedDescription
				inlineMediaLogger.error(
					"Inline image request failed for '\(address, privacy: .public)': \(reason, privacy: .public)"
				)
			}
		}
		return requestIdentifier
	}
}
