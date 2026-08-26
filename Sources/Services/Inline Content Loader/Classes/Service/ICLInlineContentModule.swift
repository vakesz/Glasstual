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
import os

typealias ICLInlineContentModuleActionBlock = @convention(block) (InlineContentModule) -> Void

@objc(ICLInlineContentModule)
class InlineContentModule: NSObject {
	private static let logger = Logger(
		subsystem: "com.vakesz.glasstual.InlineContentLoader",
		category: "Modules"
	)

	@objc let payload: InlineContentPayloadMutable
	private weak var process: InlineContentProcess?
	private var moduleFinalized = false

	@available(*, unavailable, message: "Modules are created by Inline Content Loader")
	override init() {
		fatalError("Modules are created by Inline Content Loader")
	}

	@objc(initWithPayload:inProcess:)
	required init(payload: InlineContentPayloadMutable, inProcess process: InlineContentProcess) {
		self.payload = payload
		self.process = process
		super.init()
		mergePropertiesIntoPayload()
	}

	@objc(initWithDeferredModule:)
	init(deferredModule module: InlineContentModule) {
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

	@objc class var domains: [String]? {
		nil
	}

	@objc(actionBlockForURL:)
	class func actionBlock(for _: URL) -> ICLInlineContentModuleActionBlock? {
		nil
	}

	@objc(actionForURL:)
	class func action(for _: URL) -> Selector? {
		nil
	}

	@objc class var contentImageOrVideo: Bool {
		false
	}

	@objc class var contentIsFile: Bool {
		false
	}

	@objc class var contentUntrusted: Bool {
		false
	}

	@objc class var contentNotSafeForWork: Bool {
		false
	}

	@objc var styleResources: [URL]? {
		nil
	}

	@objc var scriptResources: [URL]? {
		nil
	}

	@objc var entrypoint: String? {
		nil
	}

	@objc var templateURL: URL? {
		nil
	}

	@objc var template: GRMustacheTemplate? {
		guard let templateURL, templateURL.isFileURL else { return nil }

		do {
			return try GRMustacheTemplate(fromContentsOf: templateURL)
		} catch {
			Self.logger.error(
				"Failed to load template '\(templateURL.standardizedFileURL.path, privacy: .public)': \(error.localizedDescription, privacy: .public)"
			)
			return nil
		}
	}

	override func finalize() {
		finalizeWithError(nil)
	}

	@objc(finalizeWithError:)
	func finalizeWithError(_ error: Error?) {
		precondition(!moduleFinalized, "Module already finalized")
		finalizePreflight()
		process?.finalize(module: self, error: error as NSError?)
		finishLifecycle()
	}

	@objc
	func cancel() {
		precondition(!moduleFinalized, "Module already cancelled")
		finalizePreflight()
		process?.cancel(module: self)
		finishLifecycle()
	}

	@objc(isTypeDeferrable:)
	class func isTypeDeferrable(_ type: ICLMediaType) -> Bool {
		type == .image || type == .video || type == .videoGif
	}

	@objc(deferAsType:)
	func deferContent(as type: ICLMediaType) {
		deferContent(as: type, performCheck: true)
	}

	@objc(deferAsType:performCheck:)
	func deferContent(as type: ICLMediaType, performCheck: Bool) {
		precondition(!moduleFinalized, "Module already deferred")
		precondition(Self.isTypeDeferrable(type), "Unsupported deferred media type")
		finalizePreflight()
		process?.deferModule(self, as: type, performCheck: performCheck)
		finishLifecycle()
	}

	@objc
	func finalizePreflight() {}

	private func finishLifecycle() {
		moduleFinalized = true
		process = nil
	}
}
