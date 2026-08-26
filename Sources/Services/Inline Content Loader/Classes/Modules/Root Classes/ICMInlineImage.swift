/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
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

@objc(ICMInlineImageFoundation)
class InlineImageFoundation: InlineContentModule {
	override class var contentImageOrVideo: Bool {
		true
	}

	override var templateURL: URL? {
		Self.componentURL(named: "ICMInlineImage", extension: "mustache")
	}

	override var styleResources: [URL]? {
		[Self.componentURL(named: "ICMInlineImage", extension: "css")].compactMap(\.self)
	}

	override var scriptResources: [URL]? {
		[
			Bundle.main.url(forResource: "InlineImageLiveResize", withExtension: "js"),
			Self.componentURL(named: "ICMInlineImage", extension: "js"),
		].compactMap(\.self)
	}

	override var entrypoint: String? {
		"_ICMInlineImage"
	}

	private static func componentURL(named name: String, extension pathExtension: String) -> URL? {
		Bundle.main.url(forResource: name, withExtension: pathExtension, subdirectory: "Components")
	}
}

@objc(ICMInlineImage)
class InlineImageModule: InlineImageFoundation {
	private var imageCheck: MediaAssessor?

	@objc
	func performAction() {
		performAction(withImageCheck: true)
	}

	@objc(performActionWithImageCheck:)
	func performAction(withImageCheck checkImage: Bool) {
		if checkImage {
			performImageCheck()
		} else {
			completeImageLoad()
		}
	}

	@objc(performActionForURL:)
	func performAction(for url: URL) {
		performAction(for: url, bypassImageCheck: false)
	}

	@objc(performActionForURL:bypassImageCheck:)
	func performAction(for url: URL, bypassImageCheck: Bool) {
		precondition(imageCheck == nil, "Module already initialized")
		payload.urlToInline = url
		performAction(withImageCheck: !bypassImageCheck)
	}

	@objc(performActionForAddress:)
	func performAction(forAddress address: String) {
		performAction(forAddress: address, bypassImageCheck: false)
	}

	@objc(performActionForAddress:bypassImageCheck:)
	func performAction(forAddress address: String, bypassImageCheck: Bool) {
		guard let url = ICLHelpers.url(with: address) else { return cancel() }
		performAction(for: url, bypassImageCheck: bypassImageCheck)
	}

	private func performImageCheck() {
		let assessor = MediaAssessor(
			url: payload.urlToInline,
			expectedType: .image
		) { [weak self] _, error in
			guard let self else { return }

			if let error {
				notifyUnsafeToLoadImage()
				MediaAssessor.logError(error)
			} else {
				completeImageLoad()
			}

			imageCheck = nil
		}

		imageCheck = assessor
		assessor.resume()
	}

	private func completeImageLoad() {
		guard let template else { return cancel() }

		let attributes: [String: Any] = [
			"anchorLink": payload.address,
			"classAttribute": payload.classAttribute,
			"imageURL": payload.addressToInline,
			"preferredMaximumWidth": TPCPreferences.inlineMediaMaxWidth(),
			"uniqueIdentifier": payload.uniqueIdentifier,
		]

		do {
			payload.html = try template.renderObject(attributes)
			finalize()
		} catch {
			finalizeWithError(error)
		}
	}

	@objc
	func notifyUnsafeToLoadImage() {
		cancel()
	}

	@objc(actionBlockURL:)
	class func actionBlock(url: URL) -> ICLInlineContentModuleActionBlock {
		actionBlock(url: url, bypassImageCheck: false)
	}

	@objc(actionBlockURL:bypassImageCheck:)
	class func actionBlock(url: URL, bypassImageCheck: Bool) -> ICLInlineContentModuleActionBlock {
		actionBlock(forAddress: url.absoluteString, bypassImageCheck: bypassImageCheck)
	}

	@objc(actionBlockForAddress:)
	class func actionBlock(forAddress address: String) -> ICLInlineContentModuleActionBlock {
		actionBlock(forAddress: address, bypassImageCheck: false)
	}

	@objc(actionBlockForAddress:bypassImageCheck:)
	class func actionBlock(forAddress address: String, bypassImageCheck: Bool) -> ICLInlineContentModuleActionBlock {
		{ module in
			(module as? InlineImageModule)?.performAction(
				forAddress: address,
				bypassImageCheck: bypassImageCheck
			)
		}
	}
}
