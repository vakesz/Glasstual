/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
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

@objc(ICMCommonInlineImages)
final class CommonInlineImagesModule: InlineImageModule {
	private static let validFileExtensions = ["jpg", "jpeg", "png", "gif", "tif", "tiff", "svg", "bmp"]

	override static func actionBlock(for url: URL) -> InlineContentModuleActionBlock? {
		guard let address = finalAddress(for: url) else { return nil }
		return super.actionBlock(forAddress: address)
	}

	private static func finalAddress(for url: URL) -> String? {
		let host = (url.host(percentEncoded: true) ?? "").lowercased()
		let path = url.path(percentEncoded: true)
		let pathExtension = (path as NSString).pathExtension.lowercased()
		let hasFileExtension = validFileExtensions.contains(pathExtension)

		if hasFileExtension {
			if hostMatches(host, domain: "wikipedia.org") {
				return nil
			}
			if !hostMatches(host, domain: "dropbox.com") {
				return url.absoluteString
			}
		}

		let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedQuery
		let pathAndQuery = query.map { "\(path)?\($0)" } ?? path
		let resolvers: [(URL, String, String, String, Bool) -> String?] = [
			dropboxAddress,
			twitterAddress,
			googleDriveAddress,
			instagramAddress,
			fourChanAddress,
			hatenaAddress,
			droplrAddress,
			nicoVideoAddress,
			youTubeThumbnailAddress,
			speedtestAddress,
			fuelRatsAddress,
		]

		return resolvers.lazy.compactMap { $0(url, host, path, pathAndQuery, hasFileExtension) }.first
	}

	private static func dropboxAddress(_: URL, host: String, _: String, pathAndQuery: String,
	                                   hasExtension: Bool) -> String?
	{
		if hostMatches(host, domain: "dropbox.com") {
			guard pathAndQuery.hasPrefix("/s/"), hasExtension else { return nil }
			return "https://dl.dropboxusercontent.com\(pathAndQuery)"
		}
		return nil
	}

	private static func twitterAddress(_: URL, host: String, path: String, _: String, _: Bool) -> String? {
		if host == "pbs.twimg.com" {
			guard !path.isEmpty else { return nil }
			let normalizedPath = path.replacingOccurrences(
				of: #"\:(large|medium|orig|small|thumb)$"#,
				with: "",
				options: .regularExpression
			)
			return "https://pbs.twimg.com\(normalizedPath):orig"
		}
		return nil
	}

	private static func googleDriveAddress(_: URL, host: String, path: String, _: String, _: Bool) -> String? {
		if host == "docs.google.com" {
			guard path.hasPrefix("/file/d/") else { return nil }
			let components = path.split(separator: "/", omittingEmptySubsequences: false)
			if components.count == 4 || components.count == 5 && components[4] == "edit" {
				return "https://docs.google.com/uc?id=\(components[3])"
			}
		}
		return nil
	}

	private static func instagramAddress(_: URL, host: String, path: String, _: String, _: Bool) -> String? {
		if hostMatches(host, domain: "instagram.com") || hostMatches(host, domain: "instagr.am") {
			guard path.hasPrefix("/p/") else { return nil }
			let identifier = String(path.dropFirst(3))
			guard identifier.isASCIIIdentifier(allowing: "_-") else { return nil }
			return "https://www.instagram.com/p/\(identifier)/media/?size=l"
		}
		return nil
	}

	private static func fourChanAddress(_ url: URL, host: String, path: String, _: String, _: Bool) -> String? {
		if hostMatches(host, domain: "i.4cdn.org") {
			guard path.hasSuffix(".webm"), let scheme = url.scheme else { return nil }
			let filename = (path as NSString).deletingPathExtension
			return "\(scheme)://\(host)\(filename)s.jpg"
		}
		return nil
	}

	private static func hatenaAddress(_: URL, host: String, path: String, _: String, _: Bool) -> String? {
		if hostMatches(host, domain: "f.hatena.ne.jp") {
			let components = path.split(separator: "/", omittingEmptySubsequences: false)
			guard components.count >= 3 else { return nil }
			let userID = String(components[1])
			let photoID = String(components[2])
			guard let userHead = userID.first,
			      photoID.count >= 8,
			      photoID.isASCIINumeric
			else { return nil }
			return "https://img.f.hatena.ne.jp/images/fotolife/\(userHead)/\(userID)/\(photoID.prefix(8))/\(photoID).jpg"
		}
		return nil
	}

	private static func droplrAddress(_: URL, host: String, path: String, _: String, _: Bool) -> String? {
		if hostMatches(host, domain: "d.pr") {
			guard path.hasPrefix("/i/") else { return nil }
			let identifier = String(path.dropFirst(3))
			guard identifier.isASCIIIdentifier() else { return nil }
			return "https://d.pr/i/\(identifier).png"
		}
		return nil
	}

	private static func nicoVideoAddress(_: URL, host: String, path: String, _: String, _: Bool) -> String? {
		if hostMatches(host, domain: "nicovideo.jp") || host == "nico.ms" {
			let candidate: String? = if host == "nico.ms" {
				String(path.dropFirst())
			} else if path.hasPrefix("/watch/") {
				String(path.dropFirst(7))
			} else {
				nil
			}
			guard let candidate,
			      candidate.count >= 3,
			      candidate.hasPrefix("sm") || candidate.hasPrefix("nm")
			else { return nil }
			let number = Int64(candidate.dropFirst(2)) ?? 0
			return "https://tn-skr\((number % 4) + 1).smilevideo.jp/smile?i=\(number)"
		}
		return nil
	}

	private static func youTubeThumbnailAddress(_ url: URL, host: String, path: String, _: String, _: Bool) -> String? {
		if hostMatches(host, domain: "youtube.com") || host == "youtu.be" {
			guard InlineContentPreferences.current.limitBasicsToFiles, !path.isEmpty else { return nil }
			let identifier: String? = if host == "youtu.be" {
				String(path.dropFirst())
			} else {
				URLComponents(url: url, resolvingAgainstBaseURL: false)?
					.queryItems?
					.first(where: { $0.name == "v" })?
					.value
			}
			guard let identifier, identifier.count >= 11 else { return nil }
			return "https://i.ytimg.com/vi/\(identifier.prefix(11))/mqdefault.jpg"
		}
		return nil
	}

	private static func speedtestAddress(_: URL, host: String, path: String, _: String, _: Bool) -> String? {
		if hostMatches(host, domain: "speedtest.net") {
			let components = path.split(separator: "/", omittingEmptySubsequences: false)
			guard components.count >= 3, components[1] == "result" else { return nil }
			let identifier = String(components[2])
			guard identifier.isASCIINumeric else { return nil }
			return "https://www.speedtest.net/result/\(identifier).png"
		}
		return nil
	}

	private static func fuelRatsAddress(_: URL, host: String, path: String, _: String, _: Bool) -> String? {
		if host == "fuelrats.cloud" {
			guard path.hasPrefix("/s/") else { return nil }
			let identifier = String(path.dropFirst(3))
			guard identifier.isASCIIIdentifier() else { return nil }
			return "https://fuelrats.cloud/s/\(identifier)/preview"
		}
		return nil
	}

	private static func hostMatches(_ host: String, domain: String) -> Bool {
		host == domain || host.hasSuffix(".\(domain)")
	}

	override static var contentIsFile: Bool {
		true
	}
}

private extension String {
	var isASCIINumeric: Bool {
		!isEmpty && allSatisfy { $0.isASCII && $0.isNumber }
	}

	func isASCIIIdentifier(allowing additionalCharacters: String = "") -> Bool {
		let additionalCharacters = Set(additionalCharacters)
		return !isEmpty && allSatisfy {
			$0.isASCII && ($0.isLetter || $0.isNumber || additionalCharacters.contains($0))
		}
	}
}
