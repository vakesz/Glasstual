/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2017, 2018 Codeux Software, LLC & respective contributors.
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
import Foundation
import os

/// Bounds on what a remote endpoint can cost the inline-content service.
///
/// Every request here is triggered by a message somebody else sent, so a slow
/// or hostile endpoint must not be able to hold a request open on the default
/// sixty-second/seven-day timeouts or hand back an unbounded body.
public enum InlineContentNetworkLimits {
	public static let requestTimeout: TimeInterval = 15
	public static let resourceTimeout: TimeInterval = 30

	/// oEmbed and similar metadata replies are a few kilobytes.
	public static let maximumJSONResponseSize = 1024 * 1024
}

public enum InlineContentHelpers {
	private static let logger = Logger(
		subsystem: "com.vakesz.glasstual.InlineContentLoader",
		category: "JSON"
	)

	/// Schemes a payload is allowed to fetch or render.
	///
	/// The value ends up in the `src` attribute of an element in the log view,
	/// so anything outside HTTP is either useless or a way to reach a local
	/// resource from a remote message.
	public static let permittedSchemes: Set<String> = ["http", "https"]

	public static func url(with address: String) -> URL? {
		guard let url = URL(string: address.hasPrefix("//") ? "https:\(address)" : address),
		      let scheme = url.scheme?.lowercased(),
		      permittedSchemes.contains(scheme)
		else {
			return nil
		}

		return url
	}

	public static var genericValidationFailedError: NSError {
		NSError(
			domain: inlineContentErrorDomain,
			code: 1003,
			userInfo: [NSLocalizedDescriptionKey: "Validation failed"]
		)
	}

	/// The string at `key`, optionally under a chain of nested objects.
	///
	/// Only strings are read back, because every caller wants one.
	public static func jsonString(
		_ key: String,
		inHierarchy hierarchy: [String]? = nil,
		from url: URL
	) async -> String? {
		guard var context = await jsonObject(from: url) else { return nil }

		for step in hierarchy ?? [] {
			guard let nested = context[step]?.object else { return nil }

			context = nested
		}

		return context[key]?.string
	}

	/// Every top-level string in the reply, which is all the modules that read
	/// more than one field need.
	public static func jsonStrings(from url: URL) async -> [String: String]? {
		guard let object = await jsonObject(from: url) else { return nil }

		return object.compactMapValues(\.string)
	}

	private static let session: URLSession = {
		let configuration = URLSessionConfiguration.ephemeral
		configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
		configuration.httpShouldSetCookies = false
		configuration.httpCookieAcceptPolicy = .never
		configuration.timeoutIntervalForRequest = InlineContentNetworkLimits.requestTimeout
		configuration.timeoutIntervalForResource = InlineContentNetworkLimits.resourceTimeout
		return URLSession(configuration: configuration)
	}()

	/// The decoded reply, narrowed out of the `Any` `JSONSerialization` returns.
	private static func jsonObject(from url: URL) async -> [String: JavaScriptValue]? {
		let data: Data?

		do {
			data = try await body(from: url)
		} catch {
			logger.error("Request failed: \(error.localizedDescription, privacy: .public)")

			return nil
		}

		guard let data else { return nil }

		do {
			return try (JSONSerialization.jsonObject(with: data) as? [AnyHashable: Any])
				.map(JavaScriptValue.object(bridging:))
		} catch {
			logger.error("Failed to decode response: \(error.localizedDescription, privacy: .public)")

			return nil
		}
	}

	/** The reply body, read in the chunks the network delivers and abandoned
	 the moment it passes the size limit.

	 Buffering the whole reply and measuring it afterwards means a hostile
	 endpoint decides how much memory the service spends: the cap only refuses
	 the body once it has already been paid for. `MediaAssessor` reads its
	 bodies through the same reader. */
	private static func body(from url: URL) async throws -> Data? {
		let maximum = InlineContentNetworkLimits.maximumJSONResponseSize

		let transfer: InlineContentBodyTransfer

		do {
			transfer = try await InlineContentBodyReader.begin(
				url,
				using: session,
				limit: InlineContentBodyLimit(maximumByteCount: maximum, refusesDeclaredOverrun: true)
			)
		} catch InlineContentBodyError.bodyTooLarge {
			logger.error("Refused a reply declaring more than \(maximum, privacy: .public) bytes")

			return nil
		}

		guard transfer.response.statusCode == 200 else {
			transfer.cancel()

			return nil
		}

		do {
			return try await transfer.data()
		} catch InlineContentBodyError.bodyTooLarge {
			logger.error("Discarded a response that exceeds the \(maximum, privacy: .public) byte limit")

			return nil
		}
	}
}
