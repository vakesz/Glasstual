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
import Testing

/// Behaviour corpus for the URL matching performed by the Core Media modules.
///
/// Each module declares the hosts it claims (`domains`) and then decides, from
/// the URL alone, whether it can render the address (`module(for:)`). Only the
/// matching is exercised here — nothing is run and no request is made.
struct InlineMediaModuleCorpusTests {
	struct URLCase: Sendable {
		let address: String
		let matches: Bool

		init(_ address: String, _ matches: Bool) {
			self.address = address
			self.matches = matches
		}
	}

	private static func expectMatch(
		_ testCase: URLCase,
		_ module: any InlineContentModule.Type,
		sourceLocation: SourceLocation = #_sourceLocation
	) throws {
		let url = try #require(URL(string: testCase.address), sourceLocation: sourceLocation)

		#expect(
			(module.module(for: url) != nil) == testCase.matches,
			"\(module) and \(testCase.address)",
			sourceLocation: sourceLocation
		)
	}

	// MARK: - Host allowlists

	/// `domains` is the allowlist the loader keys its module table on. It is
	/// matched exactly, so lookalike hosts must not appear in it.
	@Test
	func moduleDomainsAreExactHosts() {
		#expect(YouTubeModule.domains == ["youtube.com", "www.youtube.com", "m.youtube.com", "youtu.be"])
		#expect(VimeoModule.domains == ["vimeo.com", "www.vimeo.com"])
		#expect(XkcdModule.domains == ["xkcd.com", "www.xkcd.com"])
		#expect(GyazoModule.domains == ["gyazo.com", "www.gyazo.com"])
		#expect(ImgurGifvModule.domains == ["i.imgur.com"])
		#expect(StreamableModule.domains == ["streamable.com", "www.streamable.com"])
		#expect(DailymotionModule.domains == [
			"dailymotion.com", "www.dailymotion.com", "mobile.dailymotion.com",
		])

		for module in Self.hostScopedModules {
			let domains = module.domains ?? []

			#expect(domains.contains("notyoutube.com") == false, "\(module)")
			#expect(domains.contains(where: { $0.hasPrefix(".") }) == false, "\(module)")
		}
	}

	private static let hostScopedModules: [any InlineContentModule.Type] = [
		DailymotionModule.self, GyazoModule.self, ImgurGifvModule.self, PornhubModule.self,
		StreamableModule.self, TweetModule.self, VimeoModule.self, XkcdModule.self, YouTubeModule.self,
	]

	@Test
	func wildcardModulesClaimEveryHost() {
		/* These two inspect the path, so they are offered every address. */
		#expect(CommonInlineImagesModule.domains == nil)
		#expect(CommonInlineVideosModule.domains == nil)
	}

	// MARK: - YouTube

	nonisolated static let youTubeCases: [URLCase] = [
		URLCase("https://www.youtube.com/watch?v=dQw4w9WgXcQ", true),
		URLCase("https://m.youtube.com/watch?v=dQw4w9WgXcQ", true),
		URLCase("https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=30", true),
		URLCase("https://youtu.be/dQw4w9WgXcQ", true),
		URLCase("https://youtu.be/dQw4w9WgXcQ?t=1m30s", true),
		/* Identifiers are exactly eleven characters. */
		URLCase("https://www.youtube.com/watch?v=short", false),
		URLCase("https://youtu.be/short", false),
		URLCase("https://youtu.be/", false),
		/* Only the /watch endpoint carries the identifier in a query item. */
		URLCase("https://www.youtube.com/embed/dQw4w9WgXcQ", false),
		URLCase("https://www.youtube.com/watch", false),
		URLCase("https://www.youtube.com/", false),
	]

	@Test(arguments: Self.youTubeCases)
	func matchesYouTubeAddresses(testCase: URLCase) throws {
		try Self.expectMatch(testCase, YouTubeModule.self)
	}

	/// The host check is a suffix test, so any domain ending in the string
	/// `youtube.com` is accepted by the module itself.
	@Test(
		.disabled("Phase 1: YouTubeModule matches hosts by hasSuffix(\"youtube.com\"), not against its allowlist"),
		arguments: [
			URLCase("https://notyoutube.com/watch?v=dQw4w9WgXcQ", false),
			URLCase("https://evilyoutube.com/watch?v=dQw4w9WgXcQ", false),
		]
	)
	func rejectsLookalikeYouTubeHosts(testCase: URLCase) throws {
		try Self.expectMatch(testCase, YouTubeModule.self)
	}

	// MARK: - Vimeo, xkcd, Streamable

	@Test(arguments: [
		URLCase("https://vimeo.com/123456789", true),
		URLCase("https://www.vimeo.com/123456789/", true),
		URLCase("https://vimeo.com/abc", false),
		URLCase("https://vimeo.com/123abc", false),
		URLCase("https://vimeo.com/channels/staffpicks/123456789", false),
		URLCase("https://vimeo.com/", false),
	])
	func matchesVimeoAddresses(testCase: URLCase) throws {
		try Self.expectMatch(testCase, VimeoModule.self)
	}

	@Test(arguments: [
		URLCase("https://xkcd.com/2000", true),
		URLCase("https://www.xkcd.com/2000/", true),
		URLCase("https://xkcd.com/about", false),
		URLCase("https://xkcd.com/2000/info.0.json", false),
		URLCase("https://xkcd.com/", false),
	])
	func matchesXkcdAddresses(testCase: URLCase) throws {
		try Self.expectMatch(testCase, XkcdModule.self)
	}

	@Test(arguments: [
		URLCase("https://streamable.com/abc123", true),
		URLCase("https://www.streamable.com/abc123/", true),
		URLCase("https://streamable.com/ABC123", true),
		URLCase("https://streamable.com/a-b", false),
		URLCase("https://streamable.com/a_b", false),
		URLCase("https://streamable.com/", false),
	])
	func matchesStreamableAddresses(testCase: URLCase) throws {
		try Self.expectMatch(testCase, StreamableModule.self)
	}

	// MARK: - Dailymotion, Pornhub, Twitter

	@Test(arguments: [
		URLCase("https://www.dailymotion.com/video/x7tgad0", true),
		URLCase("https://www.dailymotion.com/video/x7tgad0_a-video-title", true),
		URLCase("https://mobile.dailymotion.com/video/x7tgad0", true),
		URLCase("https://www.dailymotion.com/x7tgad0", false),
		URLCase("https://www.dailymotion.com/video/bad-identifier", false),
		URLCase("https://www.dailymotion.com/", false),
	])
	func matchesDailymotionAddresses(testCase: URLCase) throws {
		try Self.expectMatch(testCase, DailymotionModule.self)
	}

	/// An empty identifier is not an identifier.
	@Test(.disabled("Phase 1: DailymotionModule accepts /video/ with an empty identifier"))
	func rejectsDailymotionAddressesWithoutAnIdentifier() throws {
		try Self.expectMatch(URLCase("https://www.dailymotion.com/video/", false), DailymotionModule.self)
	}

	@Test(arguments: [
		URLCase("https://www.pornhub.com/view_video.php?viewkey=ph5d1d2f3a4b5c6", true),
		URLCase("https://pornhubpremium.com/view_video.php?viewkey=abc123", true),
		URLCase("https://www.pornhub.com/view_video.php?viewkey=bad-key", false),
		URLCase("https://www.pornhub.com/view_video.php", false),
		URLCase("https://www.pornhub.com/video?viewkey=abc123", false),
	])
	func matchesPornhubAddresses(testCase: URLCase) throws {
		try Self.expectMatch(testCase, PornhubModule.self)
	}

	@Test
	func pornhubIsMarkedNotSafeForWork() {
		#expect(PornhubModule.contentNotSafeForWork)
		#expect(VimeoModule.contentNotSafeForWork == false)
	}

	@Test(arguments: [
		URLCase("https://twitter.com/user/status/1234567890", true),
		URLCase("https://x.com/user/status/1234567890", true),
		URLCase("https://mobile.twitter.com/user/status/1234567890/photo/1", true),
		URLCase("https://twitter.com/user/statuses/1234567890", false),
		URLCase("https://twitter.com/user/status/not-a-number", false),
		URLCase("https://twitter.com/user", false),
		URLCase("https://twitter.com/", false),
	])
	func matchesTweetAddresses(testCase: URLCase) throws {
		try Self.expectMatch(testCase, TweetModule.self)
	}

	// MARK: - Gyazo and Imgur

	@Test(arguments: [
		/* A Gyazo path is a slash plus a 32-character identifier. */
		URLCase("https://gyazo.com/0123456789abcdef0123456789abcdef", true),
		URLCase("https://www.gyazo.com/0123456789ABCDEF0123456789abcdef", true),
		URLCase("https://gyazo.com/0123456789abcdef0123456789abcde", false),
		URLCase("https://gyazo.com/0123456789abcdef0123456789abcdeff", false),
		URLCase("https://gyazo.com/0123456789abcdef0123456789abcde-", false),
		URLCase("https://gyazo.com/", false),
	])
	func matchesGyazoAddresses(testCase: URLCase) throws {
		try Self.expectMatch(testCase, GyazoModule.self)
	}

	@Test(arguments: [
		URLCase("https://i.imgur.com/abc123.gifv", true),
		URLCase("https://i.imgur.com/abc123.mp4", true),
		URLCase("https://i.imgur.com/abc123.gif", true),
		URLCase("https://i.imgur.com/abc123.webp", true),
		URLCase("https://i.imgur.com/abc123.png", false),
		URLCase("https://i.imgur.com/abc-123.gifv", false),
		URLCase("https://i.imgur.com/abc123", false),
		URLCase("https://i.imgur.com/", false),
	])
	func matchesImgurGifvAddresses(testCase: URLCase) throws {
		try Self.expectMatch(testCase, ImgurGifvModule.self)
	}

	// MARK: - Wildcard image and video modules

	@Test(arguments: [
		URLCase("https://example.com/picture.png", true),
		URLCase("https://example.com/picture.JPEG", true),
		URLCase("https://example.com/picture.svg", true),
		URLCase("https://example.com/picture.exe", false),
		URLCase("https://example.com/", false),
		/* Wikipedia serves interstitials rather than the image itself. */
		URLCase("https://upload.wikimedia.org/picture.png", true),
		URLCase("https://en.wikipedia.org/picture.png", false),
		/* Dropbox links are rewritten rather than loaded directly. */
		URLCase("https://www.dropbox.com/s/abc/picture.png", true),
		URLCase("https://www.dropbox.com/other/picture.png", false),
		URLCase("https://pbs.twimg.com/media/abc.jpg:large", true),
		URLCase("https://d.pr/i/abc123", true),
		URLCase("https://d.pr/i/abc_123", false),
		URLCase("https://www.speedtest.net/result/123456", true),
		URLCase("https://www.speedtest.net/result/abcdef", false),
	])
	func matchesCommonImageAddresses(testCase: URLCase) throws {
		try Self.expectMatch(testCase, CommonInlineImagesModule.self)
	}

	@Test(arguments: [
		URLCase("https://example.com/clip.mp4", true),
		URLCase("https://example.com/clip.mov", true),
		URLCase("https://example.com/clip.m4v", true),
		URLCase("https://example.com/clip.mkv", false),
		URLCase("https://example.com/", false),
		URLCase("https://video.nest.com/clip/abc123.mp4", true),
		URLCase("https://video.nest.com/other/abc123.mp4", false),
	])
	func matchesCommonVideoAddresses(testCase: URLCase) throws {
		try Self.expectMatch(testCase, CommonInlineVideosModule.self)
	}

	// MARK: - Nico Video

	/// Nico Video has no module of its own: it is one of the address
	/// resolvers inside `CommonInlineImagesModule`.
	@Test(arguments: [
		URLCase("https://www.nicovideo.jp/watch/sm9", true),
		URLCase("https://nico.ms/sm9", true),
		URLCase("https://www.nicovideo.jp/watch/nm12345", true),
		/* Identifiers must carry the sm/nm prefix. */
		URLCase("https://www.nicovideo.jp/watch/so12345", false),
		URLCase("https://www.nicovideo.jp/watch/", false),
		URLCase("https://www.nicovideo.jp/user/123", false),
	])
	func matchesNicoVideoAddresses(testCase: URLCase) throws {
		try Self.expectMatch(testCase, CommonInlineImagesModule.self)
	}

	/// A slug whose body is not a number is not a Nico Video identifier. It
	/// currently parses as zero and resolves to a thumbnail for video 0.
	@Test(
		.disabled("Phase 1: a non-numeric Nico Video slug falls back to identifier 0 instead of being rejected"),
		arguments: [
			URLCase("https://www.nicovideo.jp/watch/smABCDEF", false),
			URLCase("https://nico.ms/nmXYZ", false),
		]
	)
	func rejectsNonNumericNicoVideoSlugs(testCase: URLCase) throws {
		try Self.expectMatch(testCase, CommonInlineImagesModule.self)
	}
}
