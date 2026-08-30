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
import Synchronization

public enum InlineContentMediaType: UInt, Codable, Sendable {
	case unknown = 0
	case image
	case video
	case videoGif
	case other
}

/// What a module made of a link.
public enum InlineContentOutcome: Sendable {
	/// The module filled the payload in and is done with it.
	case finished(InlineContentPayloadValues)

	/// The module resolved a media URL and wants one of the built-in
	/// renderers to present it. `performCheck` asks that renderer to assess
	/// the URL first; a module that already assessed it passes `false`.
	case deferred(InlineContentPayloadValues, as: InlineContentMediaType, performCheck: Bool)

	/// Nothing to show. Not an error — most links are not media.
	case cancelled

	/// The module tried and could not finish; the client hears about it.
	case failed(InlineContentPayloadValues, NSError)
}

/// A module turns one link into inline content.
///
/// Modules are value producers: `run(payload:)` is handed the payload, does its
/// own network work with `async`, and returns what it made. A module owns no
/// mutable state and reaches back into nothing, so the service can drive as
/// many of them at once as it likes from a single actor.
public protocol InlineContentModule: Sendable {
	/// The hosts this module claims. `nil` means every host, and those modules
	/// are consulted only after the host-specific ones decline.
	static var domains: [String]? { get }

	/// Whether the module renders an image or a video, rather than markup.
	static var contentImageOrVideo: Bool { get }

	/// Whether the module inlines a file, rather than an embed of a page.
	static var contentIsFile: Bool { get }

	/// Whether the module puts markup it did not build itself into the log
	/// view. Defaults to the cautious answer, so forgetting to declare it
	/// costs a gated module rather than an ungated injection point.
	static var contentUntrusted: Bool { get }

	/// Whether the module's content is withheld when the user has asked for
	/// adult content to be limited. Defaults to the cautious answer.
	static var contentNotSafeForWork: Bool { get }

	/// The module that will handle `url`, or nil when this one will not.
	/// Whatever the match parsed out of the URL is carried on the returned
	/// value, so the URL is never parsed twice.
	static func module(for url: URL) -> (any InlineContentModule)?

	func run(payload: InlineContentPayloadValues) async -> InlineContentOutcome
}

public extension InlineContentModule {
	static var domains: [String]? {
		nil
	}

	static var contentImageOrVideo: Bool {
		false
	}

	static var contentIsFile: Bool {
		false
	}

	static var contentUntrusted: Bool {
		true
	}

	static var contentNotSafeForWork: Bool {
		true
	}
}

public enum InlineContentPreferences {
	public struct Values: Sendable {
		public let maximumImageFileSize: UInt64
		public let maximumHeight: UInt
		public let maximumWidth: UInt
		public let limitBasicsToFiles: Bool

		public init(
			maximumImageFileSize: UInt64,
			maximumHeight: UInt,
			maximumWidth: UInt,
			limitBasicsToFiles: Bool
		) {
			self.maximumImageFileSize = maximumImageFileSize
			self.maximumHeight = maximumHeight
			self.maximumWidth = maximumWidth
			self.limitBasicsToFiles = limitBasicsToFiles
		}
	}

	private static let provider = Mutex<@Sendable () -> Values>({
		Values(maximumImageFileSize: 2 * 1_048_576, maximumHeight: 0, maximumWidth: 0, limitBasicsToFiles: false)
	})

	/// The host installs its own reader once, at start-up.
	public static func install(_ load: @escaping @Sendable () -> Values) {
		provider.withLock { $0 = load }
	}

	public static var current: Values {
		let load = provider.withLock { $0 }
		return load()
	}
}
