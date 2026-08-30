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

/// Presents a URL as an inline image.
///
/// The framework's own template escapes everything it renders, so content that
/// reaches the log view through here is trusted and carries no adult content of
/// its own; a module that wraps this inherits both answers.
public enum InlineImageContent {
	public static let entrypoint = "_ICMInlineImage"

	public static var styleResources: [URL] {
		[InlineContentTemplate.componentURL(named: "ICMInlineImage", extension: "css")].compactMap(\.self)
	}

	public static var scriptResources: [URL] {
		[
			Bundle.main.url(forResource: "InlineImageLiveResize", withExtension: "js"),
			InlineContentTemplate.componentURL(named: "ICMInlineImage", extension: "js"),
		].compactMap(\.self)
	}

	private static var templateURL: URL? {
		InlineContentTemplate.componentURL(named: "ICMInlineImage", extension: "mustache")
	}

	/// Renders `values.urlToInline` as an image.
	///
	/// `checkImage` asks for the assessment first; a caller that has already
	/// assessed the URL — the assessed-media module, or anything that deferred
	/// after its own check — passes `false`.
	public static func produce(
		_ values: InlineContentPayloadValues,
		checkImage: Bool = true
	) async -> InlineContentOutcome {
		var values = values

		if checkImage {
			let assessment = await MediaAssessor.assess(values.urlToInline, expecting: .image)

			if case let .failure(error) = assessment {
				MediaAssessor.logError(error)

				return .cancelled
			}
		}

		values.styleResources = styleResources
		values.scriptResources = scriptResources
		values.entrypoint = entrypoint

		let attributes: [String: JavaScriptValue] = [
			"anchorLink": .string(values.url.absoluteString),
			"classAttribute": .string(values.classAttribute),
			"imageURL": .string(values.urlToInline.absoluteString),
			"preferredMaximumWidth": .integer(Int(InlineContentPreferences.current.maximumWidth)),
			"uniqueIdentifier": .string(values.uniqueIdentifier),
		]

		return InlineContentTemplate.outcome(templateURL, attributes, into: values)
	}

	/// Points the payload at `address` and renders it. Refuses an address that
	/// is outside the inline URL policy rather than trusting a remote string.
	public static func produce(
		_ values: InlineContentPayloadValues,
		address: String,
		checkImage: Bool = true
	) async -> InlineContentOutcome {
		var values = values

		guard let url = InlineContentHelpers.url(with: address), values.setURLToInline(url) else {
			return .cancelled
		}

		return await produce(values, checkImage: checkImage)
	}
}

/// The module that inlines any URL the caller has already decided is an image.
public struct InlineImageModule: InlineContentModule {
	public static var contentImageOrVideo: Bool {
		true
	}

	public static var contentUntrusted: Bool {
		false
	}

	public static var contentNotSafeForWork: Bool {
		false
	}

	private let address: String
	private let checkImage: Bool

	public init(address: String, checkImage: Bool = true) {
		self.address = address
		self.checkImage = checkImage
	}

	public static func module(for url: URL) -> (any InlineContentModule)? {
		InlineImageModule(address: url.absoluteString)
	}

	public func run(payload: InlineContentPayloadValues) async -> InlineContentOutcome {
		await InlineImageContent.produce(payload, address: address, checkImage: checkImage)
	}
}
