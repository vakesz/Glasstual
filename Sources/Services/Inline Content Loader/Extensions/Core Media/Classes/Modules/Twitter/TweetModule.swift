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

import Foundation
import InlineContentKit

/// A tweet, embedded as the markup Twitter's oEmbed endpoint hands back.
///
/// The markup is theirs, not ours, so the module stays untrusted: the user's
/// "limit unsafe content" preference gates it.
struct TweetModule: InlineContentModule {
	static var domains: [String]? {
		[
			"twitter.com", "www.twitter.com", "mobile.twitter.com",
			"x.com", "www.x.com", "mobile.x.com",
		]
	}

	static var contentNotSafeForWork: Bool {
		false
	}

	static func module(for url: URL) -> (any InlineContentModule)? {
		guard isTweet(url) else { return nil }

		return TweetModule()
	}

	private static func isTweet(_ url: URL) -> Bool {
		let components = url.path(percentEncoded: true).split(separator: "/", omittingEmptySubsequences: true)
		guard components.count >= 3, components[1] == "status" else { return false }
		return components[2].allSatisfy { $0.isASCII && $0.isNumber }
	}

	func run(payload: InlineContentPayloadValues) async -> InlineContentOutcome {
		var components = URLComponents(string: "https://publish.twitter.com/oembed")
		components?.queryItems = [
			URLQueryItem(name: "dnt", value: "true"),
			URLQueryItem(name: "maxwidth", value: "500"),
			URLQueryItem(name: "omit_script", value: "true"),
			URLQueryItem(name: "url", value: payload.url.absoluteString),
		]

		guard let endpoint = components?.url,
		      let html = await InlineContentHelpers.jsonString("html", from: endpoint)
		else {
			return .cancelled
		}

		var values = payload
		values.classAttribute = "inlineTweet"

		let scripts = [
			URL(string: "https://platform.twitter.com/widgets.js"),
			CoreMediaBundle.current.url(forResource: "ICMTweet", withExtension: "js"),
		].compactMap(\.self)

		return InlineHTMLContent.produce(
			values,
			unescapedHTML: html,
			extraScriptResources: scripts,
			overrideEntrypoint: "_ICMTweet"
		)
	}
}
