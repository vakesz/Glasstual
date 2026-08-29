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

/// How the inline player is configured for one video.
public struct InlineVideoOptions: Sendable {
	public var autoplayEnabled = false
	public var controlsEnabled = true
	public var loopEnabled = false
	public var muteEnabled = false
	public var startTime: TimeInterval = 0
	public var playbackSpeed = 1.0

	public init() {}

	/// A silent, looping, chromeless player: what an animated image wants.
	public static var gif: InlineVideoOptions {
		var options = InlineVideoOptions()

		options.autoplayEnabled = true
		options.controlsEnabled = false
		options.loopEnabled = true
		options.muteEnabled = true

		return options
	}
}

/// Presents a URL as an inline video.
///
/// The framework's own template escapes everything it renders, so content that
/// reaches the log view through here is trusted and carries no adult content of
/// its own; a module that wraps this inherits both answers.
public enum InlineVideoContent {
	public static let entrypoint = "_ICMInlineVideo"

	public static var styleResources: [URL] {
		[InlineContentTemplate.componentURL(named: "ICMInlineVideo", extension: "css")].compactMap(\.self)
	}

	public static var scriptResources: [URL] {
		[InlineContentTemplate.componentURL(named: "ICMInlineVideo", extension: "js")].compactMap(\.self)
	}

	private static var templateURL: URL? {
		InlineContentTemplate.componentURL(named: "ICMInlineVideo", extension: "mustache")
	}

	/// Renders `values.urlToInline` as a video.
	public static func produce(
		_ values: InlineContentPayloadValues,
		options: InlineVideoOptions = InlineVideoOptions(),
		checkVideo: Bool = true
	) async -> InlineContentOutcome {
		var values = values

		if checkVideo {
			let assessment = await MediaAssessor.assess(values.urlToInline, expecting: .video)

			if case let .failure(error) = assessment {
				MediaAssessor.logError(error)

				return .cancelled
			}
		}

		values.styleResources = styleResources
		values.scriptResources = scriptResources
		values.entrypoint = entrypoint

		let playbackSpeed = (0.125 ... 6.0).contains(options.playbackSpeed) ? options.playbackSpeed : 1.0

		let attributes: [String: Any] = [
			"anchorLink": values.url.absoluteString,
			"classAttribute": values.classAttribute,
			"preferredMaximumWidth": InlineContentPreferences.current.maximumWidth,
			"uniqueIdentifier": values.uniqueIdentifier,
			"videoAutoplayEnabled": options.autoplayEnabled,
			"videoControlsEnabled": options.controlsEnabled,
			"videoLoopEnabled": options.loopEnabled,
			"videoMuteEnabled": options.muteEnabled,
			"videoPlaybackSpeed": playbackSpeed,
			"videoStartTime": options.startTime,
			"videoURL": values.urlToInline.absoluteString,
		]

		return InlineContentTemplate.outcome(templateURL, attributes, into: values)
	}

	/// Points the payload at `address` and renders it. Refuses an address that
	/// is outside the inline URL policy rather than trusting a remote string.
	public static func produce(
		_ values: InlineContentPayloadValues,
		address: String,
		options: InlineVideoOptions = InlineVideoOptions(),
		checkVideo: Bool = true
	) async -> InlineContentOutcome {
		var values = values

		guard let url = InlineContentHelpers.url(with: address), values.setURLToInline(url) else {
			return .cancelled
		}

		return await produce(values, options: options, checkVideo: checkVideo)
	}

	/// Renders a module's own template into the shared video container: the
	/// container's stylesheet, script and entrypoint, the module's markup.
	public static func embed(
		_ values: InlineContentPayloadValues,
		templateURL: URL?,
		attributes: [String: Any]
	) -> InlineContentOutcome {
		var values = values

		values.styleResources = styleResources
		values.scriptResources = scriptResources
		values.entrypoint = entrypoint

		return InlineContentTemplate.outcome(templateURL, attributes, into: values)
	}

	/// The seconds a `?t=` timestamp names, in either the bare-seconds form or
	/// the `1h2m3s` form YouTube and its imitators use.
	public static func parseTimestamp(_ timestamp: String) -> TimeInterval {
		if !timestamp.isEmpty, timestamp.allSatisfy(\.isNumber) {
			return TimeInterval(timestamp) ?? 0
		}

		// One `<number><unit>` pair. A local `let` rather than a stored static:
		// `Regex` is not `Sendable`, and the compiler has already parsed the
		// literal — what is left is a cheap constructor call.
		let component = /([0-9]+)([hmsHMS])/

		var value: TimeInterval = 0
		var matchedUnits = Set<String>()

		for match in timestamp.matches(of: component) {
			let unit = match.2.lowercased()

			guard matchedUnits.insert(unit).inserted else { continue }

			let component = TimeInterval(match.1) ?? 0

			switch unit {
			case "h": value += component * 3600
			case "m": value += component * 60
			case "s": value += component
			default: break
			}
		}

		return value
	}
}

/// The module that inlines any URL the caller has already decided is a video.
public struct InlineVideoModule: InlineContentModule {
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
	private let options: InlineVideoOptions
	private let checkVideo: Bool

	public init(address: String, options: InlineVideoOptions = InlineVideoOptions(), checkVideo: Bool = true) {
		self.address = address
		self.options = options
		self.checkVideo = checkVideo
	}

	public static func module(for url: URL) -> (any InlineContentModule)? {
		InlineVideoModule(address: url.absoluteString)
	}

	public func run(payload: InlineContentPayloadValues) async -> InlineContentOutcome {
		await InlineVideoContent.produce(payload, address: address, options: options, checkVideo: checkVideo)
	}
}
