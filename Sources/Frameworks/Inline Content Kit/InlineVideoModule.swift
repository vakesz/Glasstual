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

@objc(ICMInlineVideoFoundation)
open class InlineVideoFoundation: InlineContentModule {
	@objc public var videoAutoplayEnabled = false
	@objc public var videoControlsEnabled = true
	@objc public var videoLoopEnabled = false
	@objc public var videoMuteEnabled = false
	@objc public var videoStartTime: TimeInterval = 0
	@objc public var videoPlaybackSpeed = 1.0

	override open class var contentImageOrVideo: Bool {
		true
	}

	override open var templateURL: URL? {
		Self.componentURL(named: "ICMInlineVideo", extension: "mustache")
	}

	override open var styleResources: [URL]? {
		[Self.componentURL(named: "ICMInlineVideo", extension: "css")].compactMap(\.self)
	}

	override open var scriptResources: [URL]? {
		[Self.componentURL(named: "ICMInlineVideo", extension: "js")].compactMap(\.self)
	}

	override open var entrypoint: String? {
		"_ICMInlineVideo"
	}

	@objc(parseYouTubeEsqueTimestamp:)
	public class func parseYouTubeEsqueTimestamp(_ timestamp: String) -> TimeInterval {
		if !timestamp.isEmpty, timestamp.allSatisfy(\.isNumber) {
			return TimeInterval(timestamp) ?? 0
		}

		guard let expression = try? NSRegularExpression(
			pattern: "([0-9]+)([hms])",
			options: .caseInsensitive
		) else {
			return 0
		}

		var value: TimeInterval = 0
		var matchedUnits = Set<String>()
		let range = NSRange(timestamp.startIndex ..< timestamp.endIndex, in: timestamp)

		for match in expression.matches(in: timestamp, range: range) {
			guard
				let valueRange = Range(match.range(at: 1), in: timestamp),
				let unitRange = Range(match.range(at: 2), in: timestamp)
			else {
				continue
			}

			let unit = timestamp[unitRange].lowercased()
			guard matchedUnits.insert(unit).inserted else { continue }
			let component = TimeInterval(timestamp[valueRange]) ?? 0

			switch unit {
			case "h": value += component * 3600
			case "m": value += component * 60
			case "s": value += component
			default: break
			}
		}

		return value
	}

	private static func componentURL(named name: String, extension pathExtension: String) -> URL? {
		Bundle.main.url(forResource: name, withExtension: pathExtension, subdirectory: "Components")
	}
}

@objc(ICMInlineVideo)
open class InlineVideoModule: InlineVideoFoundation {
	private var videoCheck: MediaAssessor?

	@objc
	public func performAction() {
		performAction(withVideoCheck: true)
	}

	@objc(performActionWithVideoCheck:)
	public func performAction(withVideoCheck checkVideo: Bool) {
		if checkVideo {
			performVideoCheck()
		} else {
			completeVideoLoad()
		}
	}

	@objc(performActionForURL:)
	public func performAction(for url: URL) {
		performAction(for: url, bypassVideoCheck: false)
	}

	@objc(performActionForURL:bypassVideoCheck:)
	public func performAction(for url: URL, bypassVideoCheck: Bool) {
		precondition(videoCheck == nil, "Module already initialized")
		payload.urlToInline = url
		performAction(withVideoCheck: !bypassVideoCheck)
	}

	@objc(performActionForAddress:)
	public func performAction(forAddress address: String) {
		performAction(forAddress: address, bypassVideoCheck: false)
	}

	@objc(performActionForAddress:bypassVideoCheck:)
	public func performAction(forAddress address: String, bypassVideoCheck: Bool) {
		guard let url = InlineContentHelpers.url(with: address) else { return cancel() }
		performAction(for: url, bypassVideoCheck: bypassVideoCheck)
	}

	private func performVideoCheck() {
		let assessor = MediaAssessor(
			url: payload.urlToInline,
			expectedType: .video
		) { [weak self] _, error in
			guard let self else { return }

			if let error {
				notifyUnsafeToLoadVideo()
				MediaAssessor.logError(error)
			} else {
				completeVideoLoad()
			}

			videoCheck = nil
		}

		videoCheck = assessor
		assessor.resume()
	}

	private func completeVideoLoad() {
		guard let template else { return cancel() }
		let playbackSpeed = (0.125 ... 6.0).contains(videoPlaybackSpeed) ? videoPlaybackSpeed : 1.0

		let attributes: [String: Any] = [
			"anchorLink": payload.address,
			"classAttribute": payload.classAttribute,
			"preferredMaximumWidth": InlineContentPreferences.current.maximumWidth,
			"uniqueIdentifier": payload.uniqueIdentifier,
			"videoAutoplayEnabled": videoAutoplayEnabled,
			"videoControlsEnabled": videoControlsEnabled,
			"videoLoopEnabled": videoLoopEnabled,
			"videoMuteEnabled": videoMuteEnabled,
			"videoPlaybackSpeed": playbackSpeed,
			"videoStartTime": videoStartTime,
			"videoURL": payload.addressToInline,
		]

		do {
			payload.html = try template.render(attributes)
			finalize()
		} catch {
			finalizeWithError(error)
		}
	}

	@objc
	public func notifyUnsafeToLoadVideo() {
		cancel()
	}

	@objc(actionBlockForForURL:)
	public class func actionBlock(forFor url: URL) -> InlineContentModuleActionBlock {
		actionBlock(forFor: url, bypassVideoCheck: false)
	}

	@objc(actionBlockForForURL:bypassVideoCheck:)
	public class func actionBlock(forFor url: URL, bypassVideoCheck: Bool) -> InlineContentModuleActionBlock {
		actionBlock(forAddress: url.absoluteString, bypassVideoCheck: bypassVideoCheck)
	}

	@objc(actionBlockForAddress:)
	public class func actionBlock(forAddress address: String) -> InlineContentModuleActionBlock {
		actionBlock(forAddress: address, bypassVideoCheck: false)
	}

	@objc(actionBlockForAddress:bypassVideoCheck:)
	public class func actionBlock(forAddress address: String,
	                              bypassVideoCheck: Bool) -> InlineContentModuleActionBlock
	{
		{ module in
			(module as? InlineVideoModule)?.performAction(
				forAddress: address,
				bypassVideoCheck: bypassVideoCheck
			)
		}
	}
}

@objc(ICMInlineGifVideo)
open class InlineGifVideoModule: InlineVideoModule {
	public required init(payload: InlineContentPayloadMutable, inProcess process: any InlineContentProcessHandling) {
		super.init(payload: payload, inProcess: process)
		configurePlayback()
	}

	override public init(deferredModule module: InlineContentModule) {
		super.init(deferredModule: module)
		configurePlayback()
	}

	private func configurePlayback() {
		videoAutoplayEnabled = true
		videoControlsEnabled = false
		videoLoopEnabled = true
		videoMuteEnabled = true
	}
}
