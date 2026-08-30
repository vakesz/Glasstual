/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import Foundation
import InlineContentKit
import os

private nonisolated let inlineMediaClientLogger = Logger( // nonisolated: let
	subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
	category: "InlineMediaClient"
)

/** Forwards the loader's callbacks into the actor.

 It holds nothing but the actor reference, which is why XPC may call it on
 whichever thread it likes. */
private final nonisolated class InlineMediaClientShim: NSObject, // nonisolated: xpc-shim
	InlineContentClientProtocol, Sendable
{
	private let client: InlineMediaClient

	init(client: InlineMediaClient) {
		self.client = client
		super.init()
	}

	func processingPayloadSucceeded(_ payload: InlineContentPayload) { // nonisolated: xpc-shim
		Task { await client.handlePayloadSucceeded(payload) }
	}

	func processingPayload( // nonisolated: xpc-shim
		_ payload: InlineContentPayload,
		failedWithError error: Error
	) {
		let error = error as NSError
		Task { await client.handlePayload(payload, failedWith: error) }
	}
}

/** Owns the connection to the inline-content loader.

 The connection is created here and never leaves the actor, and every reply the
 service sends arrives through `InlineMediaClientShim`, so nothing has to assert
 which thread it is on. */
actor InlineMediaClient {
	static let shared = InlineMediaClient()

	private var connection: NSXPCConnection?
	private var shim: InlineMediaClientShim?

	/// Whether a connection is currently attached. Test seam.
	var isAttached: Bool {
		connection != nil
	}

	/// Connects and warms the service, once. Idempotent.
	func attach() {
		guard connection == nil else {
			return
		}

		inlineMediaClientLogger.debug("Warming process...")
		connect()

		proxy?.warmService(with: .current())
		proxy?.warmServiceByLoadingPlugins()
	}

	/// Tears the connection down. Idempotent: detaching twice is one invalidation.
	func detach() {
		guard let connection else {
			return
		}

		inlineMediaClientLogger.debug("Invalidating process...")
		connection.invalidate()
	}

	private func connect() {
		let connection = NSXPCConnection(serviceName: "com.vakesz.glasstual.InlineContentLoader")
		let shim = InlineMediaClientShim(client: self)

		connection.remoteObjectInterface = NSXPCInterface(with: InlineContentServerProtocol.self)
		connection.exportedInterface = NSXPCInterface(with: InlineContentClientProtocol.self)
		connection.exportedObject = shim

		connection.interruptionHandler = { [weak self] in
			inlineMediaClientLogger.log("Interruption handler called")
			Task { await self?.detach() }
		}

		connection.invalidationHandler = { [weak self] in
			inlineMediaClientLogger.log("Invalidation handler called")
			Task { await self?.handleInvalidation() }
		}

		connection.resume()

		self.connection = connection
		self.shim = shim
	}

	private func handleInvalidation() {
		connection = nil
		shim = nil
	}

	private var proxy: InlineContentServerProtocol? {
		connection?.remoteObjectProxyWithErrorHandler { error in
			inlineMediaClientLogger.error(
				"Error occurred while communicating with service: \(error.localizedDescription, privacy: .public)"
			)
		} as? InlineContentServerProtocol
	}

	/// Asks the loader to fetch and assess one address.
	func process(
		_ url: URL,
		withUniqueIdentifier uniqueIdentifier: String,
		atLineNumber lineNumber: String,
		index: UInt,
		inView viewIdentifier: String
	) {
		attach()

		proxy?.process(
			url,
			withUniqueIdentifier: uniqueIdentifier,
			atLineNumber: lineNumber,
			index: index,
			inView: viewIdentifier
		)
	}

	func handlePayloadSucceeded(_ payload: InlineContentPayload) async {
		await LogControllerInlineMediaService.deliverPayloadSucceeded(payload)
	}

	func handlePayload(_ payload: InlineContentPayload, failedWith error: NSError) async {
		await LogControllerInlineMediaService.deliverPayload(payload, failedWith: error)
	}
}
