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

@objc(ICLMediaAssessment)
open class MediaAssessment: XRPortablePropertyObject, @unchecked Sendable {
	fileprivate var urlStorage = URL(string: "about:blank")!
	fileprivate var typeStorage = ICLMediaType.unknown
	fileprivate var contentTypeStorage = "application/binary"
	fileprivate var contentLengthStorage: UInt64 = 0

	@objc public var url: URL {
		urlStorage
	}

	@objc open var type: ICLMediaType {
		typeStorage
	}

	@objc open var contentType: String {
		contentTypeStorage
	}

	@objc open var contentLength: UInt64 {
		contentLengthStorage
	}

	@available(*, unavailable, message: "Use init(url:type:)")
	override public required init() {
		fatalError("Use init(url:type:)")
	}

	@objc(initWithURL:asType:)
	public init(url: URL, type: ICLMediaType) {
		precondition(!url.isFileURL)
		urlStorage = url
		typeStorage = type
		super.init()
	}

	public required init?(coder: NSCoder) {
		super.init(coder: coder)
	}

	override public class var supportsSecureCoding: Bool {
		true
	}

	override public func populate(withDecoder decoder: NSCoder) -> Bool {
		guard let decodedURL = decoder.decodeObject(of: NSURL.self, forKey: "url") as URL? else {
			return false
		}

		urlStorage = decodedURL
		typeStorage = ICLMediaType(rawValue: UInt(decoder.decodeInteger(forKey: "type"))) ?? .unknown
		contentTypeStorage = decoder.decodeObject(of: NSString.self, forKey: "contentType") as String?
			?? "application/binary"
		contentLengthStorage = decoder.decodeObject(of: NSNumber.self, forKey: "contentLength")?.uint64Value ?? 0
		return true
	}

	override public func encode(with coder: NSCoder) {
		coder.encode(urlStorage, forKey: "url")
		coder.encode(typeStorage.rawValue, forKey: "type")
		coder.encode(contentTypeStorage, forKey: "contentType")
		coder.encode(NSNumber(value: contentLengthStorage), forKey: "contentLength")
	}

	override public func copy(asMutable mutableCopy: Bool, uniquing _: Bool) -> Any {
		let copy: MediaAssessment = if mutableCopy {
			MediaAssessmentMutable(url: urlStorage, type: typeStorage)
		} else {
			MediaAssessment(url: urlStorage, type: typeStorage)
		}
		copy.contentTypeStorage = contentTypeStorage
		copy.contentLengthStorage = contentLengthStorage
		return copy
	}

	override public var mutableClass: XRPortablePropertyObject {
		unsafeBitCast(MediaAssessmentMutable.self, to: XRPortablePropertyObject.self)
	}
}

@objc(ICLMediaAssessmentMutable)
public final class MediaAssessmentMutable: MediaAssessment, @unchecked Sendable {
	override public class var isMutable: Bool {
		true
	}

	override public var immutableClass: XRPortablePropertyObject {
		unsafeBitCast(MediaAssessment.self, to: XRPortablePropertyObject.self)
	}

	@objc override public var type: ICLMediaType {
		get { typeStorage }
		set { typeStorage = newValue }
	}

	@objc override public var contentType: String {
		get { contentTypeStorage }
		set { contentTypeStorage = newValue }
	}

	@objc override public var contentLength: UInt64 {
		get { contentLengthStorage }
		set { contentLengthStorage = newValue }
	}
}
