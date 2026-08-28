/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2017, 2020 Codeux Software, LLC & respective contributors.
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

@objc(ICLPayload)
/* ISOLATION-EXCEPTION: an NSSecureCoding transport object. It crosses the XPC
 boundary between the app and the inline-content service, where NSXPCConnection
 owns the copy on each side, and the mutable subclass is only ever edited by the
 module that created it. */
open class InlineContentPayload: PortablePropertyObject, @unchecked Sendable {
	fileprivate static let logger = Logger(
		subsystem: "com.vakesz.glasstual.InlineContentLoader",
		category: "Payload"
	)

	fileprivate var urlStorage = URL(string: "about:blank")!
	fileprivate var urlToInlineStorage = URL(string: "about:blank")!
	fileprivate var lineNumberStorage = ""
	fileprivate var uniqueIdentifierStorage = ""
	fileprivate var viewIdentifierStorage = ""
	fileprivate var indexStorage: UInt = 0
	fileprivate var contentLengthStorage: UInt64 = 0
	fileprivate var contentSizeStorage = NSSize.zero
	fileprivate var styleResourcesStorage: [URL] = []
	fileprivate var scriptResourcesStorage: [URL] = []
	fileprivate var htmlStorage = ""
	fileprivate var entrypointStorage: String?
	fileprivate var entrypointPayloadStorage: [String: Any]?
	fileprivate var classAttributeStorage = ""

	@objc public var url: URL {
		urlStorage
	}

	@objc public var address: String {
		urlStorage.absoluteString
	}

	@objc open var urlToInline: URL {
		urlToInlineStorage
	}

	@objc public var addressToInline: String {
		urlToInlineStorage.absoluteString
	}

	@objc public var uniqueIdentifier: String {
		uniqueIdentifierStorage
	}

	@objc public var viewIdentifier: String {
		viewIdentifierStorage
	}

	@objc public var lineNumber: String {
		lineNumberStorage
	}

	@objc public var index: UInt {
		indexStorage
	}

	@objc open var contentLength: UInt64 {
		contentLengthStorage
	}

	@objc open var contentSize: NSSize {
		contentSizeStorage
	}

	@objc open var styleResources: [URL] {
		styleResourcesStorage
	}

	@objc open var scriptResources: [URL] {
		scriptResourcesStorage
	}

	@objc open var html: String {
		htmlStorage
	}

	@objc open var entrypoint: String? {
		entrypointStorage
	}

	@objc open var classAttribute: String {
		classAttributeStorage
	}

	@objc open var entrypointPayload: [String: Any] {
		entrypointPayloadStorage ?? defaultEntrypointContext
	}

	override public required init() {
		super.init()
	}

	@objc(initWithURL:withUniqueIdentifier:atLineNumber:index:inView:)
	public init(
		url: URL,
		withUniqueIdentifier uniqueIdentifier: String,
		atLineNumber lineNumber: String,
		index: UInt,
		inView viewIdentifier: String
	) {
		precondition(!url.isFileURL)
		urlStorage = url
		urlToInlineStorage = url
		uniqueIdentifierStorage = uniqueIdentifier
		lineNumberStorage = lineNumber
		indexStorage = index
		viewIdentifierStorage = viewIdentifier
		super.init()
	}

	@objc(initWithDeferredPayload:)
	public init(deferredPayload payload: InlineContentPayload) {
		urlStorage = payload.urlStorage
		urlToInlineStorage = payload.urlToInlineStorage
		lineNumberStorage = payload.lineNumberStorage
		indexStorage = payload.indexStorage
		uniqueIdentifierStorage = payload.uniqueIdentifierStorage
		viewIdentifierStorage = payload.viewIdentifierStorage
		classAttributeStorage = payload.classAttributeStorage
		super.init()
	}

	public required init?(coder: NSCoder) {
		super.init(coder: coder)
	}

	override public class var supportsSecureCoding: Bool {
		true
	}

	override public func populate(with decoder: NSCoder) -> Bool {
		guard
			let url = decoder.decodeObject(of: NSURL.self, forKey: "url") as URL?,
			let lineNumber = decoder.decodeObject(of: NSString.self, forKey: "lineNumber") as String?,
			let uniqueIdentifier = decoder.decodeObject(of: NSString.self, forKey: "uniqueIdentifier") as String?,
			let viewIdentifier = decoder.decodeObject(of: NSString.self, forKey: "viewIdentifier") as String?
		else {
			return false
		}

		urlStorage = url
		urlToInlineStorage = decoder.decodeObject(of: NSURL.self, forKey: "urlToInline") as URL? ?? url
		lineNumberStorage = lineNumber
		uniqueIdentifierStorage = uniqueIdentifier
		viewIdentifierStorage = viewIdentifier
		indexStorage = UInt(decoder.decodeInteger(forKey: "index"))
		contentLengthStorage = decoder.decodeObject(of: NSNumber.self, forKey: "contentLength")?.uint64Value ?? 0
		contentSizeStorage = decoder.decodeSize(forKey: "contentSize")
		styleResourcesStorage = Self.decodeURLs(decoder, key: "styleResources")
		scriptResourcesStorage = Self.decodeURLs(decoder, key: "scriptResources")
		htmlStorage = decoder.decodeObject(of: NSString.self, forKey: "html") as String? ?? ""
		entrypointStorage = decoder.decodeObject(of: NSString.self, forKey: "entrypoint") as String?
		entrypointPayloadStorage = Self.decodeDictionary(decoder, key: "entrypointPayload")
		classAttributeStorage = decoder.decodeObject(of: NSString.self, forKey: "classAttribute") as String? ?? ""
		return true
	}

	override public func encode(with coder: NSCoder) {
		coder.encode(NSNumber(value: contentLengthStorage), forKey: "contentLength")
		coder.encode(contentSizeStorage, forKey: "contentSize")
		coder.encode(styleResourcesStorage, forKey: "styleResources")
		coder.encode(scriptResourcesStorage, forKey: "scriptResources")
		coder.encode(htmlStorage, forKey: "html")
		coder.encode(entrypointStorage, forKey: "entrypoint")
		coder.encode(entrypointPayloadStorage, forKey: "entrypointPayload")
		coder.encode(urlStorage, forKey: "url")
		coder.encode(urlToInlineStorage, forKey: "urlToInline")
		coder.encode(lineNumberStorage, forKey: "lineNumber")
		coder.encode(uniqueIdentifierStorage, forKey: "uniqueIdentifier")
		coder.encode(viewIdentifierStorage, forKey: "viewIdentifier")
		coder.encode(indexStorage, forKey: "index")
		coder.encode(classAttributeStorage, forKey: "classAttribute")
	}

	override public func copy(asMutable mutableCopy: Bool, uniquing _: Bool) -> Any {
		let copy: InlineContentPayload = if mutableCopy {
			InlineContentPayloadMutable()
		} else {
			InlineContentPayload()
		}
		copy.copyValues(from: self)
		return copy
	}

	override public var mutableClass: PortablePropertyObject {
		unsafeBitCast(InlineContentPayloadMutable.self, to: PortablePropertyObject.self)
	}

	private var defaultEntrypointContext: [String: Any] {
		[
			"class": classAttributeStorage,
			"html": htmlStorage,
			"url": urlStorage,
			"urlToInline": urlToInlineStorage,
			"lineNumber": lineNumberStorage,
			"uniqueIdentifier": uniqueIdentifierStorage,
		]
	}

	fileprivate func setEntrypointPayload(_ payload: [String: Any]?) {
		guard let payload else {
			entrypointPayloadStorage = nil
			return
		}
		entrypointPayloadStorage = payload.merging(defaultEntrypointContext) { _, requiredValue in requiredValue }
	}

	private func copyValues(from payload: InlineContentPayload) {
		urlStorage = payload.urlStorage
		urlToInlineStorage = payload.urlToInlineStorage
		lineNumberStorage = payload.lineNumberStorage
		uniqueIdentifierStorage = payload.uniqueIdentifierStorage
		viewIdentifierStorage = payload.viewIdentifierStorage
		indexStorage = payload.indexStorage
		contentLengthStorage = payload.contentLengthStorage
		contentSizeStorage = payload.contentSizeStorage
		styleResourcesStorage = payload.styleResourcesStorage
		scriptResourcesStorage = payload.scriptResourcesStorage
		htmlStorage = payload.htmlStorage
		entrypointStorage = payload.entrypointStorage
		entrypointPayloadStorage = payload.entrypointPayloadStorage
		classAttributeStorage = payload.classAttributeStorage
	}

	private static func decodeURLs(_ decoder: NSCoder, key: String) -> [URL] {
		let classes: [AnyClass] = [NSArray.self, NSURL.self]
		return decoder.decodeObject(of: classes, forKey: key) as? [URL] ?? []
	}

	private static func decodeDictionary(_ decoder: NSCoder, key: String) -> [String: Any]? {
		let classes: [AnyClass] = [
			NSDictionary.self, NSArray.self, NSString.self, NSNumber.self, NSURL.self, NSNull.self,
		]
		return decoder.decodeObject(of: classes, forKey: key) as? [String: Any]
	}
}

@objc(ICLPayloadMutable)
/* ISOLATION-EXCEPTION: see `InlineContentPayload`. */
public final class InlineContentPayloadMutable: InlineContentPayload, @unchecked Sendable {
	override public static var isMutable: Bool {
		true
	}

	override public var immutableClass: PortablePropertyObject {
		unsafeBitCast(InlineContentPayload.self, to: PortablePropertyObject.self)
	}

	@objc override public var urlToInline: URL {
		get { urlToInlineStorage }
		set {
			/* This value is rendered into a `src` attribute in the log view.
			 Modules build it from strings a remote server supplied, so it is
			 filtered here rather than trusted — and an out-of-policy value is
			 dropped instead of aborting the service process. */
			guard let scheme = newValue.scheme?.lowercased(),
			      InlineContentHelpers.permittedSchemes.contains(scheme)
			else {
				InlineContentPayload.logger.error(
					"Refused inline URL with scheme '\(newValue.scheme ?? "(none)", privacy: .public)'"
				)

				return
			}

			urlToInlineStorage = newValue
		}
	}

	@objc override public var contentLength: UInt64 {
		get { contentLengthStorage }
		set { contentLengthStorage = newValue }
	}

	@objc override public var contentSize: NSSize {
		get { contentSizeStorage }
		set { contentSizeStorage = newValue }
	}

	@objc override public var styleResources: [URL] {
		get { styleResourcesStorage }
		set { styleResourcesStorage = newValue }
	}

	@objc override public var scriptResources: [URL] {
		get { scriptResourcesStorage }
		set { scriptResourcesStorage = newValue }
	}

	@objc override public var html: String {
		get { htmlStorage }
		set { htmlStorage = newValue }
	}

	@objc override public var entrypoint: String? {
		get { entrypointStorage }
		set { entrypointStorage = newValue }
	}

	@objc override public var entrypointPayload: [String: Any] {
		get { super.entrypointPayload }
		set { setEntrypointPayload(newValue) }
	}

	@objc override public var classAttribute: String {
		get { classAttributeStorage }
		set { classAttributeStorage = newValue }
	}
}
