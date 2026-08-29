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
import CoreGraphics
import Foundation
import os

public let inlineContentErrorDomain = "ICLInlineContentErrorDomain"

/// Everything a finished inline-content payload says about one link.
///
/// This is the value the two processes agree on, and the value modules produce.
/// `InlineContentPayload` is the `NSSecureCoding` envelope built around it at
/// the XPC boundary and adds no state of its own.
public struct InlineContentPayloadValues: Sendable, Equatable {
	public var url: URL
	public var urlToInline: URL
	public var uniqueIdentifier: String
	public var viewIdentifier: String
	public var lineNumber: String
	public var index: UInt
	public var contentLength: UInt64
	public var contentSize: CGSize
	public var styleResources: [URL]
	public var scriptResources: [URL]
	public var html: String
	public var entrypoint: String?
	public var classAttribute: String

	public init(
		url: URL,
		uniqueIdentifier: String,
		lineNumber: String,
		index: UInt,
		viewIdentifier: String
	) {
		self.url = url
		urlToInline = url
		self.uniqueIdentifier = uniqueIdentifier
		self.viewIdentifier = viewIdentifier
		self.lineNumber = lineNumber
		self.index = index
		contentLength = 0
		contentSize = .zero
		styleResources = []
		scriptResources = []
		html = ""
		entrypoint = nil
		classAttribute = ""
	}

	/// Sets the URL that will be rendered into a `src` attribute in the log
	/// view. Modules build it from strings a remote server supplied, so it is
	/// filtered here rather than trusted; an out-of-policy value is dropped
	/// and reported instead of aborting the service.
	@discardableResult
	public mutating func setURLToInline(_ url: URL) -> Bool {
		guard let scheme = url.scheme?.lowercased(),
		      InlineContentHelpers.permittedSchemes.contains(scheme)
		else {
			payloadLogger.error(
				"Refused inline URL with scheme '\(url.scheme ?? "(none)", privacy: .public)'"
			)

			return false
		}

		urlToInline = url

		return true
	}

	/// The values a deferred module inherits: what identifies the link, not
	/// what the module it was deferred from had produced.
	public var deferredCopy: InlineContentPayloadValues {
		var copy = InlineContentPayloadValues(
			url: url,
			uniqueIdentifier: uniqueIdentifier,
			lineNumber: lineNumber,
			index: index,
			viewIdentifier: viewIdentifier
		)

		copy.urlToInline = urlToInline
		copy.classAttribute = classAttribute

		return copy
	}
}

private let payloadLogger = Logger(
	subsystem: "com.vakesz.glasstual.InlineContentLoader",
	category: "Payload"
)

/// The immutable payload that crosses the XPC boundary.
///
/// Every stored property is a `let` of a `Sendable` type, so the class needs no
/// annotation to be sent between the application and the inline-content
/// service. It is `final` because a class with subclasses cannot be `Sendable`;
/// modules work on `InlineContentPayloadValues` and never see this at all.
@objc(ICLPayload)
public final class InlineContentPayload: NSObject, NSSecureCoding, Sendable {
	public let values: InlineContentPayloadValues

	public init(values: InlineContentPayloadValues) {
		precondition(!values.url.isFileURL)

		self.values = values

		super.init()
	}

	@objc(initWithURL:withUniqueIdentifier:atLineNumber:index:inView:)
	public convenience init(
		url: URL,
		withUniqueIdentifier uniqueIdentifier: String,
		atLineNumber lineNumber: String,
		index: UInt,
		inView viewIdentifier: String
	) {
		self.init(
			values: InlineContentPayloadValues(
				url: url,
				uniqueIdentifier: uniqueIdentifier,
				lineNumber: lineNumber,
				index: index,
				viewIdentifier: viewIdentifier
			)
		)
	}

	// MARK: - Accessors

	@objc public var url: URL {
		values.url
	}

	@objc public var address: String {
		values.url.absoluteString
	}

	@objc public var urlToInline: URL {
		values.urlToInline
	}

	@objc public var addressToInline: String {
		values.urlToInline.absoluteString
	}

	@objc public var uniqueIdentifier: String {
		values.uniqueIdentifier
	}

	@objc public var viewIdentifier: String {
		values.viewIdentifier
	}

	@objc public var lineNumber: String {
		values.lineNumber
	}

	@objc public var index: UInt {
		values.index
	}

	@objc public var contentLength: UInt64 {
		values.contentLength
	}

	@objc public var contentSize: CGSize {
		values.contentSize
	}

	@objc public var styleResources: [URL] {
		values.styleResources
	}

	@objc public var scriptResources: [URL] {
		values.scriptResources
	}

	@objc public var html: String {
		values.html
	}

	@objc public var entrypoint: String? {
		values.entrypoint
	}

	@objc public var classAttribute: String {
		values.classAttribute
	}

	/// The context the entrypoint script is called with. Every module has been
	/// content with the defaults, so it is derived rather than stored.
	@objc public var entrypointPayload: [String: Any] {
		[
			"class": values.classAttribute,
			"html": values.html,
			"url": values.url,
			"urlToInline": values.urlToInline,
			"lineNumber": values.lineNumber,
			"uniqueIdentifier": values.uniqueIdentifier,
		]
	}

	// MARK: - Secure Coding

	public static var supportsSecureCoding: Bool {
		true
	}

	public required init?(coder decoder: NSCoder) {
		guard
			let url = decoder.decodeObject(of: NSURL.self, forKey: "url") as URL?,
			let lineNumber = decoder.decodeObject(of: NSString.self, forKey: "lineNumber") as String?,
			let uniqueIdentifier = decoder.decodeObject(of: NSString.self, forKey: "uniqueIdentifier") as String?,
			let viewIdentifier = decoder.decodeObject(of: NSString.self, forKey: "viewIdentifier") as String?
		else {
			return nil
		}

		var values = InlineContentPayloadValues(
			url: url,
			uniqueIdentifier: uniqueIdentifier,
			lineNumber: lineNumber,
			index: UInt(decoder.decodeInteger(forKey: "index")),
			viewIdentifier: viewIdentifier
		)

		values.urlToInline = decoder.decodeObject(of: NSURL.self, forKey: "urlToInline") as URL? ?? url
		values.contentLength = decoder.decodeObject(of: NSNumber.self, forKey: "contentLength")?.uint64Value ?? 0
		values.contentSize = decoder.decodeSize(forKey: "contentSize")
		values.styleResources = Self.decodeURLs(decoder, key: "styleResources")
		values.scriptResources = Self.decodeURLs(decoder, key: "scriptResources")
		values.html = decoder.decodeObject(of: NSString.self, forKey: "html") as String? ?? ""
		values.entrypoint = decoder.decodeObject(of: NSString.self, forKey: "entrypoint") as String?
		values.classAttribute = decoder.decodeObject(of: NSString.self, forKey: "classAttribute") as String? ?? ""

		self.values = values

		super.init()
	}

	public func encode(with coder: NSCoder) {
		coder.encode(NSNumber(value: values.contentLength), forKey: "contentLength")
		coder.encode(values.contentSize, forKey: "contentSize")
		coder.encode(values.styleResources, forKey: "styleResources")
		coder.encode(values.scriptResources, forKey: "scriptResources")
		coder.encode(values.html, forKey: "html")
		coder.encode(values.entrypoint, forKey: "entrypoint")
		coder.encode(values.url, forKey: "url")
		coder.encode(values.urlToInline, forKey: "urlToInline")
		coder.encode(values.lineNumber, forKey: "lineNumber")
		coder.encode(values.uniqueIdentifier, forKey: "uniqueIdentifier")
		coder.encode(values.viewIdentifier, forKey: "viewIdentifier")
		/* Int, not UInt: the UInt overload archives an NSNumber object, which
		 decodeInteger(forKey:) then refuses to read back. */
		coder.encode(Int(values.index), forKey: "index")
		coder.encode(values.classAttribute, forKey: "classAttribute")
	}

	private static func decodeURLs(_ decoder: NSCoder, key: String) -> [URL] {
		let classes: [AnyClass] = [NSArray.self, NSURL.self]

		return decoder.decodeObject(of: classes, forKey: key) as? [URL] ?? []
	}
}

// The scratch payload a module fills in while it runs.
//
// It never crosses a process or an isolation boundary: the service creates one
// per module and takes a `snapshot()` of it when the module finishes.
