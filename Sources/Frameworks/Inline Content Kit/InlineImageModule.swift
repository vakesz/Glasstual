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
import Mustache

@objc(ICMInlineImageFoundation)
open class InlineImageFoundation: InlineContentModule {
	/** Renders through the framework's own template into an escaped attribute,
	 and carries no adult content of its own. */
	override open class var contentUntrusted: Bool {
		false
	}

	override open class var contentNotSafeForWork: Bool {
		false
	}

	override open class var contentImageOrVideo: Bool {
		true
	}

	override open var templateURL: URL? {
		Self.componentURL(named: "ICMInlineImage", extension: "mustache")
	}

	override open var styleResources: [URL]? {
		[Self.componentURL(named: "ICMInlineImage", extension: "css")].compactMap(\.self)
	}

	override open var scriptResources: [URL]? {
		[
			Bundle.main.url(forResource: "InlineImageLiveResize", withExtension: "js"),
			Self.componentURL(named: "ICMInlineImage", extension: "js"),
		].compactMap(\.self)
	}

	override open var entrypoint: String? {
		"_ICMInlineImage"
	}

	private static func componentURL(named name: String, extension pathExtension: String) -> URL? {
		Bundle.main.url(forResource: name, withExtension: pathExtension, subdirectory: "Components")
	}
}

@objc(ICMInlineImage)
open class InlineImageModule: InlineImageFoundation {
	private var imageCheck: MediaAssessor?

	@objc
	public func performAction() {
		performAction(withImageCheck: true)
	}

	@objc(performActionWithImageCheck:)
	public func performAction(withImageCheck checkImage: Bool) {
		if checkImage {
			performImageCheck()
		} else {
			completeImageLoad()
		}
	}

	@objc(performActionForURL:)
	public func performAction(for url: URL) {
		performAction(for: url, bypassImageCheck: false)
	}

	@objc(performActionForURL:bypassImageCheck:)
	public func performAction(for url: URL, bypassImageCheck: Bool) {
		precondition(imageCheck == nil, "Module already initialized")
		payload.urlToInline = url
		performAction(withImageCheck: !bypassImageCheck)
	}

	@objc(performActionForAddress:)
	public func performAction(forAddress address: String) {
		performAction(forAddress: address, bypassImageCheck: false)
	}

	@objc(performActionForAddress:bypassImageCheck:)
	public func performAction(forAddress address: String, bypassImageCheck: Bool) {
		guard let url = InlineContentHelpers.url(with: address) else { return cancel() }
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
			"preferredMaximumWidth": InlineContentPreferences.current.maximumWidth,
			"uniqueIdentifier": payload.uniqueIdentifier,
		]

		do {
			payload.html = try template.render(attributes)
			finalize()
		} catch {
			finalizeWithError(error)
		}
	}

	@objc
	public func notifyUnsafeToLoadImage() {
		cancel()
	}

	@objc(actionBlockURL:)
	public class func actionBlock(url: URL) -> InlineContentModuleActionBlock {
		actionBlock(url: url, bypassImageCheck: false)
	}

	@objc(actionBlockURL:bypassImageCheck:)
	public class func actionBlock(url: URL, bypassImageCheck: Bool) -> InlineContentModuleActionBlock {
		actionBlock(forAddress: url.absoluteString, bypassImageCheck: bypassImageCheck)
	}

	@objc(actionBlockForAddress:)
	public class func actionBlock(forAddress address: String) -> InlineContentModuleActionBlock {
		actionBlock(forAddress: address, bypassImageCheck: false)
	}

	@objc(actionBlockForAddress:bypassImageCheck:)
	public class func actionBlock(forAddress address: String,
	                              bypassImageCheck: Bool) -> InlineContentModuleActionBlock
	{
		{ module in
			(module as? InlineImageModule)?.performAction(
				forAddress: address,
				bypassImageCheck: bypassImageCheck
			)
		}
	}
}
