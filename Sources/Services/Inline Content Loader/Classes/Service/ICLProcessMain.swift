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
import InlineContentKit
import os

@objc(ICLProcessMain)
final class InlineContentProcess: NSObject, InlineContentServerProtocol, InlineContentProcessHandling,
	@unchecked Sendable
{
	private static let logger = Logger(
		subsystem: "com.vakesz.glasstual.InlineContentLoader",
		category: "Process"
	)
	private static let warmLock = NSLock()
	private nonisolated(unsafe) static var loadedPlugins = false
	private nonisolated(unsafe) static var registeredDefaults = false

	private let stateLock = NSLock()
	private var serviceConnectionStorage: NSXPCConnection?
	private let moduleReferencesLock = NSLock()
	private var moduleReferences = Set<InlineContentModule>()
	private var modulesByDomainStorage: [String: [InlineContentModule.Type]]?

	/** Cleared from the invalidation handler while module callbacks still read it. */
	private var serviceConnection: NSXPCConnection? {
		get { stateLock.withLock { serviceConnectionStorage } }
		set { stateLock.withLock { serviceConnectionStorage = newValue } }
	}

	/** `process(_:)` is a concurrent XPC entry point and Swift's `lazy` is not thread
	 safe, so the table is memoised behind a lock instead. Bundled modules are only
	 registered once the service has been warmed, so this cannot be built in `init`. */
	private var modulesByDomain: [String: [InlineContentModule.Type]] {
		stateLock.withLock {
			if let modulesByDomainStorage {
				return modulesByDomainStorage
			}

			var mappedModules: [String: [InlineContentModule.Type]] = [:]

			for module in moduleClasses {
				let domains = module.domains
				for domain in domains?.isEmpty == false ? domains! : ["*"] {
					/* Lookups use a lowercased host, so the keys must match. */
					mappedModules[domain.lowercased(), default: []].append(module)
				}
			}

			modulesByDomainStorage = mappedModules
			return mappedModules
		}
	}

	private var moduleClasses: [InlineContentModule.Type] {
		let pluginModules = InlineContentPluginManager.shared.modules.compactMap { $0 as? InlineContentModule.Type }
		return pluginModules + [AssessedMediaModule.self]
	}

	@available(*, unavailable, message: "Use init(xpcConnection:)")
	override init() {
		fatalError("Use init(xpcConnection:)")
	}

	@objc(initWithXPCConnection:)
	init(xpcConnection: NSXPCConnection) {
		serviceConnectionStorage = xpcConnection
		super.init()
		InlineContentPreferences.install {
			InlineContentPreferences.Values(
				maximumImageFileSize: TextualPreferences.inlineImagesMaxFilesize(),
				maximumHeight: TextualPreferences.inlineMediaMaxHeight(),
				maximumWidth: TextualPreferences.inlineMediaMaxWidth(),
				limitBasicsToFiles: TextualPreferences.inlineMediaLimitBasicsToFiles()
			)
		}
	}

	@objc(processURL:withUniqueIdentifier:atLineNumber:index:inView:)
	func process(
		_ url: URL,
		withUniqueIdentifier uniqueIdentifier: String,
		atLineNumber lineNumber: String,
		index: UInt,
		inView viewIdentifier: String
	) {
		/* Links come from IRC messages; a `file:` URL must not abort the shared service. */
		guard !url.isFileURL else {
			Self.logger.error("Refusing to process a file URL")
			return
		}

		let payload = InlineContentPayloadMutable(
			url: url,
			withUniqueIdentifier: uniqueIdentifier,
			atLineNumber: lineNumber,
			index: index,
			inView: viewIdentifier
		)

		process(payload)
	}

	@objc(processPayload:)
	func process(_ payload: InlineContentPayload) {
		guard let scheme = payload.url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
			return
		}

		guard let mutablePayload = (payload as? InlineContentPayloadMutable)
			?? payload.mutableCopy() as? InlineContentPayloadMutable
		else {
			assertionFailure("Inline content payload did not produce its declared mutable copy type")
			return
		}
		let host = mutablePayload.url.host?.lowercased() ?? ""

		if process(mutablePayload, withModulesFor: host) {
			return
		}
		_ = process(mutablePayload, withModulesFor: "*")
	}

	private func process(_ payload: InlineContentPayloadMutable, withModulesFor domain: String) -> Bool {
		for module in modulesByDomain[domain] ?? [] where process(payload, using: module) {
			return true
		}
		return false
	}

	private func process(_ payload: InlineContentPayloadMutable, using moduleType: InlineContentModule.Type) -> Bool {
		if !moduleType.contentImageOrVideo, TextualPreferences.inlineMediaLimitToBasics() {
			return false
		}
		if !moduleType.contentIsFile,
		   TextualPreferences.inlineMediaLimitToBasics(),
		   TextualPreferences.inlineMediaLimitBasicsToFiles()
		{
			return false
		}
		if moduleType.contentNotSafeForWork, TextualPreferences.inlineMediaLimitNaughtyContent() {
			return false
		}
		if moduleType.contentUntrusted, TextualPreferences.inlineMediaLimitUnsafeContent() {
			return false
		}

		let actionBlock = moduleType.actionBlock(for: payload.url)
		let action = actionBlock == nil ? moduleType.action(for: payload.url) : nil
		guard actionBlock != nil || action != nil else { return false }

		let module = moduleType.init(payload: payload, inProcess: self)
		retain(module)

		if let actionBlock {
			actionBlock(module)
		} else if let action {
			_ = module.perform(action)
		}

		return true
	}

	func finalize(module: InlineContentModule, error originalError: NSError?) {
		guard let payload = module.payload.copy() as? InlineContentPayload else {
			assertionFailure("Inline content payload did not produce its declared immutable copy type")
			release(module)
			return
		}
		release(module)

		let error: NSError? = if payload.html.isEmpty, payload.scriptResources.isEmpty {
			NSError(
				domain: inlineContentErrorDomain,
				code: 1001,
				userInfo: [
					NSLocalizedDescriptionKey: "-[ICLPayload scriptResources] must contain at least one path if -[ICLPayload html] is empty",
				]
			)
		} else if payload.html.isEmpty, payload.entrypoint?.isEmpty != false {
			NSError(
				domain: inlineContentErrorDomain,
				code: 1002,
				userInfo: [
					NSLocalizedDescriptionKey: "-[ICLPayload html] and -[ICLPayload entrypoint] cannot both be empty",
				]
			)
		} else {
			originalError
		}

		guard let remoteObjectProxy else { return }
		if let error {
			remoteObjectProxy.processingPayload(payload, failedWithError: error)
		} else {
			remoteObjectProxy.processingPayloadSucceeded(payload)
		}
	}

	func cancel(module: InlineContentModule) {
		release(module)
	}

	func deferModule(_ module: InlineContentModule, as type: InlineContentMediaType, performCheck: Bool) {
		switch type {
		case .image:
			let image = InlineImageModule(deferredModule: module)
			retain(image)
			image.performAction(withImageCheck: performCheck)
		case .video:
			let video = InlineVideoModule(deferredModule: module)
			retain(video)
			video.performAction(withVideoCheck: performCheck)
		case .videoGif:
			let video = InlineGifVideoModule(deferredModule: module)
			retain(video)
			video.performAction(withVideoCheck: performCheck)
		default:
			Self.logger.error("Unexpected deferred media type: \(type.rawValue, privacy: .public)")
			return
		}
	}

	private func retain(_ module: InlineContentModule) {
		_ = moduleReferencesLock.withLock {
			moduleReferences.insert(module)
		}
	}

	private func release(_ module: InlineContentModule) {
		_ = moduleReferencesLock.withLock {
			moduleReferences.remove(module)
		}
	}

	@objc
	func connectionInvalidated() {
		Self.logger.debug("Connection invalidated")
		moduleReferencesLock.withLock {
			moduleReferences.removeAll()
		}
		serviceConnection = nil
	}

	@objc(warmServiceByLoadingPlugins)
	func warmServiceByLoadingPlugins() {
		Self.warmLock.withLock {
			guard !Self.loadedPlugins else { return }
			Self.loadedPlugins = true

			InlineContentPluginManager.shared.loadBundledPlugins()
		}
	}

	@objc(warmServiceWithPreferences:)
	func warmService(with preferences: InlineContentServicePreferences) {
		Self.warmLock.withLock {
			guard !Self.registeredDefaults else { return }
			Self.registeredDefaults = true
			TextualUserDefaults.shared().register(defaults: preferences.registrationDomain)
		}
	}

	private var remoteObjectProxy: (any InlineContentClientProtocol)? {
		serviceConnection?.remoteObjectProxy as? any InlineContentClientProtocol
	}
}
