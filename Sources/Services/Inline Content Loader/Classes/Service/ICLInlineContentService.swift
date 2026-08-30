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
import InlineContentKit
import os

/// Runs modules and reports what they made.
///
/// One service exists per accepted XPC connection. It owns the in-flight work
/// and the warm-up flag; the module table is a `let` in
/// `InlineContentModuleRegistry`. Modules are values, so running several at
/// once costs nothing but a task each — none of them can reach back in here.
actor InlineContentService {
	private static let logger = Logger(
		subsystem: "com.vakesz.glasstual.InlineContentLoader",
		category: "Process"
	)

	/// The client half of the connection. `InlineContentClientProtocol` refines
	/// `Sendable`, which is what lets the proxy live in here at all.
	private var client: (any InlineContentClientProtocol)?

	/// Work that has not reported yet, so it can be dropped on invalidation.
	private var inFlight: [UUID: Task<Void, Never>] = [:]

	private var registeredDefaults = false

	// MARK: - Connection Lifecycle

	func attach(client: any InlineContentClientProtocol) {
		self.client = client
	}

	/// The application owns the connection's lifetime; this runs from its
	/// invalidation handler.
	func detach() {
		Self.logger.debug("Connection invalidated")

		client = nil

		for task in inFlight.values {
			task.cancel()
		}

		inFlight.removeAll()
	}

	// MARK: - Warm-up

	func warmService(with preferences: InlineContentServicePreferences) {
		guard registeredDefaults == false else { return }

		registeredDefaults = true

		TextualUserDefaults.suite().register(defaults: preferences.registrationDomain.propertyListObject)
	}

	// MARK: - Processing

	func process(_ values: InlineContentPayloadValues) {
		/* Links come from IRC messages; a `file:` URL must not abort the
		 shared service. */
		guard !values.url.isFileURL else {
			Self.logger.error("Refusing to process a file URL")

			return
		}

		guard TextualPreferences.permitsInlineMedia(at: values.url) else { return }

		guard let module = module(for: values.url) else { return }

		let identifier = UUID()

		inFlight[identifier] = Task { [weak self] in
			let outcome = await module.run(payload: values)

			await self?.finish(identifier, with: outcome)
		}
	}

	/// The first module that claims the URL and passes the user's content
	/// preferences. Host-specific modules are asked before the catch-alls.
	private func module(for url: URL) -> (any InlineContentModule)? {
		let host = url.host?.lowercased() ?? ""

		return module(for: url, in: host) ?? module(for: url, in: "*")
	}

	private func module(for url: URL, in domain: String) -> (any InlineContentModule)? {
		for moduleType in InlineContentModuleRegistry.modulesByDomain[domain] ?? [] {
			guard permitted(moduleType) else { continue }

			if let module = moduleType.module(for: url) {
				return module
			}
		}

		return nil
	}

	private func permitted(_ moduleType: any InlineContentModule.Type) -> Bool {
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

		return true
	}

	private func finish(_ identifier: UUID, with outcome: InlineContentOutcome) async {
		switch outcome {
		case let .finished(values):
			inFlight[identifier] = nil

			deliver(values, error: validationError(for: values))
		case let .failed(values, error):
			inFlight[identifier] = nil

			deliver(values, error: error)
		case .cancelled:
			inFlight[identifier] = nil
		case let .deferred(values, type, performCheck):
			/* The same slot stays in flight: the work continues, it is just a
			 different module doing it now. */
			await render(values, as: type, performCheck: performCheck, in: identifier)
		}
	}

	private func render(
		_ values: InlineContentPayloadValues,
		as type: InlineContentMediaType,
		performCheck: Bool,
		in identifier: UUID
	) async {
		let outcome: InlineContentOutcome = switch type {
		case .image:
			await InlineImageContent.produce(values, checkImage: performCheck)
		case .video:
			await InlineVideoContent.produce(values, checkVideo: performCheck)
		case .videoGif:
			await InlineVideoContent.produce(values, options: .gif, checkVideo: performCheck)
		default:
			.cancelled
		}

		if case .deferred = outcome {
			/* A renderer that deferred again would loop; the built-in ones
			 never do, so this is a programming error rather than a server's
			 doing. */
			Self.logger.error("A built-in renderer deferred, which is not allowed")

			inFlight[identifier] = nil

			return
		}

		await finish(identifier, with: outcome)
	}

	/// What the client would refuse to render, caught here so the failure names
	/// the module rather than surfacing as an empty element.
	private func validationError(for values: InlineContentPayloadValues) -> NSError? {
		if values.html.isEmpty, values.scriptResources.isEmpty {
			return NSError(
				domain: inlineContentErrorDomain,
				code: 1001,
				userInfo: [
					NSLocalizedDescriptionKey: "scriptResources must contain at least one path if html is empty",
				]
			)
		}

		if values.html.isEmpty, values.entrypoint?.isEmpty != false {
			return NSError(
				domain: inlineContentErrorDomain,
				code: 1002,
				userInfo: [NSLocalizedDescriptionKey: "html and entrypoint cannot both be empty"]
			)
		}

		return nil
	}

	private func deliver(_ values: InlineContentPayloadValues, error: NSError?) {
		guard let client else { return }

		let payload = InlineContentPayload(values: values)

		if let error {
			client.processingPayload(payload, failedWithError: error)
		} else {
			client.processingPayloadSucceeded(payload)
		}
	}
}
