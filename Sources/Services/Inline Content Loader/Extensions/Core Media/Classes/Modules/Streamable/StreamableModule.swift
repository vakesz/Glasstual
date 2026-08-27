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

@objc(ICMStreamable)
final class StreamableModule: InlineVideoModule {
	private func performAction(forVideo identifier: String) {
		let address = "https://api.streamable.com/videos/\(identifier)"
		_ = InlineContentHelpers.requestJSONObject(
			"url",
			ofType: NSString.self,
			inHierarchy: ["files", "mp4"],
			fromAddress: address
		) { [weak self] object in
			guard let self, let address = object as? String else {
				self?.notifyUnsafeToLoadVideo()
				return
			}
			performAction(forAddress: address)
		}
	}

	override static func actionBlock(for url: URL) -> InlineContentModuleActionBlock? {
		let identifier = url.path(percentEncoded: true).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
		guard !identifier.isEmpty,
		      identifier.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) })
		else { return nil }
		return { module in
			(module as? StreamableModule)?.performAction(forVideo: identifier)
		}
	}

	override static var domains: [String]? {
		["streamable.com", "www.streamable.com"]
	}

	override static var contentIsFile: Bool {
		true
	}

	override func finalizePreflight() {
		payload.classAttribute = "inlineStreamable"
	}
}
