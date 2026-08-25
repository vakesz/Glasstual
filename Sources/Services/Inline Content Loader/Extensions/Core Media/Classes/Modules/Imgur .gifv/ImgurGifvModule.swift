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

@objc(ICMImgurGifv)
final class ImgurGifvModule: ICMInlineGifVideo {
	private static let validFileExtensions = ["mp4", "gif", "gifv", "webp"]

	override class func actionBlock(for url: URL) -> ICLInlineContentModuleActionBlock? {
		guard let address = finalAddress(for: url) else { return nil }
		return super.actionBlock(forAddress: address)
	}

	private class func finalAddress(for url: URL) -> String? {
		let path = url.path(percentEncoded: true)
		guard path.count > 1 else { return nil }

		let filename = String(path.dropFirst()) as NSString
		guard validFileExtensions.contains(filename.pathExtension) else { return nil }

		let identifier = filename.deletingPathExtension
		guard identifier.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { return nil }
		return "https://i.imgur.com/\(identifier).mp4"
	}

	override class var domains: [String]? {
		["i.imgur.com"]
	}

	override class var contentIsFile: Bool {
		true
	}

	override func finalizePreflight() {
		payload.classAttribute = "inlineImgurGifv"
	}
}
