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
import Mustache
import os

public typealias InlineContentModuleActionBlock = @convention(block) (InlineContentModule) -> Void

@objc(ICLInlineContentModule)
open class InlineContentModule: NSObject {
	private static let logger = Logger(
		subsystem: "com.vakesz.glasstual.InlineContentLoader",
		category: "Modules"
	)

	@objc public let payload: InlineContentPayloadMutable
	private weak var process: (any InlineContentProcessHandling)?
	private var moduleFinalized = false

	@available(*, unavailable, message: "Modules are created by Inline Content Loader")
	override init() {
		fatalError("Modules are created by Inline Content Loader")
	}

	@objc(initWithPayload:inProcess:)
	public required init(payload: InlineContentPayloadMutable, inProcess process: any InlineContentProcessHandling) {
		self.payload = payload
		self.process = process
		super.init()
		mergePropertiesIntoPayload()
	}

	@objc(initWithDeferredModule:)
	public init(deferredModule module: InlineContentModule) {
		payload = InlineContentPayloadMutable(deferredPayload: module.payload)
		process = module.process
		super.init()
		mergePropertiesIntoPayload()
	}

	private func mergePropertiesIntoPayload() {
		if let scriptResources {
			payload.scriptResources = scriptResources
		}
		if let styleResources {
			payload.styleResources = styleResources
		}
		if let entrypoint {
			payload.entrypoint = entrypoint
		}
	}

	@objc open class var domains: [String]? {
		nil
	}

	@objc(actionBlockForURL:)
	open class func actionBlock(for _: URL) -> InlineContentModuleActionBlock? {
		nil
	}

	@objc(actionForURL:)
	open class func action(for _: URL) -> Selector? {
		nil
	}

	@objc open class var contentImageOrVideo: Bool {
		false
	}

	@objc open class var contentIsFile: Bool {
		false
	}

	/// Whether the module puts markup it did not build itself into the log view.
	///
	/// Defaults to the cautious answer: a module that never says otherwise is
	/// treated as untrusted, so forgetting to declare it costs a gated module
	/// rather than an ungated injection point.
	@objc open class var contentUntrusted: Bool {
		true
	}

	/// Whether the module's content should be withheld when the user has asked
	/// for adult content to be limited. Defaults to the cautious answer.
	@objc open class var contentNotSafeForWork: Bool {
		true
	}

	@objc open var styleResources: [URL]? {
		nil
	}

	@objc open var scriptResources: [URL]? {
		nil
	}

	@objc open var entrypoint: String? {
		nil
	}

	@objc open var templateURL: URL? {
		nil
	}

	open var template: Template? {
		guard let templateURL, templateURL.isFileURL else { return nil }

		do {
			return try Template(URL: templateURL)
		} catch {
			Self.logger.error(
				"Failed to load template '\(templateURL.standardizedFileURL.path, privacy: .public)': \(error.localizedDescription, privacy: .public)"
			)
			return nil
		}
	}

	override open func finalize() {
		finalizeWithError(nil)
	}

	@objc(finalizeWithError:)
	public func finalizeWithError(_ error: Error?) {
		precondition(!moduleFinalized, "Module already finalized")
		finalizePreflight()
		process?.finalize(module: self, error: error as NSError?)
		finishLifecycle()
	}

	@objc
	public func cancel() {
		precondition(!moduleFinalized, "Module already cancelled")
		finalizePreflight()
		process?.cancel(module: self)
		finishLifecycle()
	}

	@objc(isTypeDeferrable:)
	public class func isTypeDeferrable(_ type: InlineContentMediaType) -> Bool {
		type == .image || type == .video || type == .videoGif
	}

	@objc(deferAsType:)
	public func deferContent(as type: InlineContentMediaType) {
		deferContent(as: type, performCheck: true)
	}

	@objc(deferAsType:performCheck:)
	public func deferContent(as type: InlineContentMediaType, performCheck: Bool) {
		precondition(!moduleFinalized, "Module already deferred")
		precondition(Self.isTypeDeferrable(type), "Unsupported deferred media type")
		finalizePreflight()
		process?.deferModule(self, as: type, performCheck: performCheck)
		finishLifecycle()
	}

	@objc
	open func finalizePreflight() {}

	private func finishLifecycle() {
		moduleFinalized = true
		process = nil
	}
}
