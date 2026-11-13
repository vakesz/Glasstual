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

/// Refusals and failures reach the unified log only: a refused preview leaves
/// the link as it was.
private func logInlineImageFailure(_ error: any Error, for url: URL) {
	let reason = (error as? InlineImageError)?.logDescription ?? error.localizedDescription
	inlineMediaLogger.error(
		"Inline image request failed for '\(url.absoluteString, privacy: .private(mask: .hash))':\(reason, privacy: .public)"
	)
}

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

	/** Starts the preview for one link, or draws the placeholder that waits
	 for the reader, as the session's route decides.

	 Answers with the request's token when a fetch started. */
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
		      let associatedSession,
		      backingView?.containsLine(identifier: lineNumber) == true else { return nil }
		// The image goes through the proxy the session's own connection is configured for.
		let route = InlineImageRoute(session: associatedSession)
		switch route.inlineImageFetch {
		case .automatic:
			return requestInlineImage(url, route: route, lineNumber: lineNumber, linkIdentifier: linkIdentifier)
		case .onRequest:
			/* A literal private address or a local name is refused on every
			 route, so it gets no placeholder to click either. */
			guard InlineImageHostPolicy.verdict(forHost: url.host(percentEncoded: false)) != .refused else {
				logInlineImageFailure(InlineImageError.hostNotAllowed, for: url)
				return nil
			}
			backingView?.addInlineImagePlaceholder(TranscriptInlineImagePlaceholder(
				lineNumber: lineNumber, linkIdentifier: linkIdentifier, sourceURL: url
			))
			return nil
		case .never:
			logInlineImageFailure(InlineImageError.proxyUnavailable, for: url)
			return nil
		}
	}

	/** Fetches the image a placeholder stands for, because the reader asked.

	 Everything a fetch on sight goes through still applies: the inline-media
	 settings as they are now, the session's route as it is now, which fails
	 closed when its proxy has no address, the host policy and every bound of
	 the loader. Answers with the request's token when a fetch started. */
	@discardableResult
	func loadInlineImageOnRequest(_ placeholder: TranscriptInlineImagePlaceholder) -> UUID? {
		let key = placeholder.key
		guard let associatedSession, let backingView,
		      backingView.containsLine(identifier: key.lineNumber)
		else { return nil }
		guard inlineMediaEnabledForView else {
			backingView.removeInlineImagePlaceholder(key)
			return nil
		}
		let route = InlineImageRoute(session: associatedSession)
		let requestIdentifier = requestInlineImage(
			placeholder.sourceURL, route: route, lineNumber: key.lineNumber, linkIdentifier: key.linkIdentifier
		) { [weak self] in
			self?.backingView?.setInlineImagePlaceholderState(.failed, for: key)
		}
		if requestIdentifier != nil {
			backingView.setInlineImagePlaceholderState(.loading, for: key)
		}
		return requestIdentifier
	}

	/// One fetch through the loader. `onFailure` runs after a refusal or a
	/// failed download, synchronously when the loader refuses at admission.
	private func requestInlineImage(
		_ url: URL,
		route: InlineImageRoute,
		lineNumber: String,
		linkIdentifier: String,
		onFailure: (@MainActor () -> Void)? = nil
	) -> UUID? {
		let generation = renderScheduler.generation
		let loader = inlineImageLoader
		// Only admission failures run synchronously; successful callbacks receive the assigned token.
		var requestIdentifier: UUID?
		requestIdentifier = loader.load(
			url: url,
			route: route,
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
					onFailure?()
					return
				}
			case let .failure(error):
				logInlineImageFailure(error, for: url)
				onFailure?()
			}
		}
		return requestIdentifier
	}
}
