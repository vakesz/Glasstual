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

@objc(ICMGyazo)
final class GyazoModule: InlineContentModule {
	/** Renders through the framework's own template into an escaped attribute,
	 and carries no adult content of its own. */
	override static var contentUntrusted: Bool {
		false
	}

	override static var contentNotSafeForWork: Bool {
		false
	}

	private var contentIdentifier = ""

	private func loadContent() {
		var components = URLComponents(string: "https://api.gyazo.com/api/oembed")
		components?.queryItems = [URLQueryItem(name: "url", value: payload.address)]
		guard let url = components?.url else { return cancel() }

		_ = InlineContentHelpers.requestJSONData(from: url) { [weak self] success, data in
			guard let self, success, let data else {
				self?.cancel()
				return
			}
			process(data)
		}
	}

	private func process(_ data: [String: Any]) {
		guard let type = data["type"] as? String else { return cancel() }

		switch type {
		case "photo":
			guard
				let address = data["url"] as? String,
				let url = InlineContentHelpers.url(with: address),
				!url.isFileURL
			else {
				return cancel()
			}
			payload.urlToInline = url
			deferContent(as: .image)
		case "video":
			guard let url = InlineContentHelpers.url(with: "https://i.gyazo.com/\(contentIdentifier).mp4") else {
				return cancel()
			}
			payload.urlToInline = url
			deferContent(as: .videoGif)
		default:
			cancel()
		}
	}

	override static func actionBlock(for url: URL) -> InlineContentModuleActionBlock? {
		let path = url.path(percentEncoded: true)
		guard path.count == 33 else { return nil }
		let identifier = String(path.dropFirst())
		guard identifier.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { return nil }
		return { module in
			guard let module = module as? GyazoModule else { return }
			module.contentIdentifier = identifier
			module.loadContent()
		}
	}

	override static var domains: [String]? {
		["gyazo.com", "www.gyazo.com"]
	}

	override static var contentImageOrVideo: Bool {
		true
	}

	override static var contentIsFile: Bool {
		true
	}

	override func finalizePreflight() {
		payload.classAttribute = "inlineGyazo"
	}
}
