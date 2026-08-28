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

import AppKit
import CocoaExtensions
import InlineContentKit
import os
import UniformTypeIdentifiers

private nonisolated let inlineMediaLogger = Logger(
	subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
	category: "InlineMediaService"
)

/* ISOLATION-EXCEPTION: `InlineContentClientProtocol` is an XPC protocol whose
 callbacks arrive on the connection's queue, so this type cannot be isolated.
 Everything it touches on the way in hops to the main actor below. Owned by the
 XPC-service task. */
@objc(TVCLogControllerInlineMediaService)
public final nonisolated class LogControllerInlineMediaService: NSObject, InlineContentClientProtocol,
	@unchecked Sendable
{
	private var serviceConnection: NSXPCConnection?

	@objc(sharedInstance)
	public static func shared() -> LogControllerInlineMediaService {
		enum Storage {
			static let instance = LogControllerInlineMediaService()
		}

		return Storage.instance
	}

	@objc public func warmProcessIfNeeded() {
		guard serviceConnection == nil else {
			return
		}

		inlineMediaLogger.debug("Warming process...")
		connectToService()
	}

	@objc public func invalidateProcess() {
		guard serviceConnection != nil else {
			return
		}

		inlineMediaLogger.debug("Invalidating process...")
		serviceConnection?.invalidate()
	}

	private func connectToService() {
		let serviceConnection = NSXPCConnection(serviceName: "com.vakesz.glasstual.InlineContentLoader")

		let remoteObjectInterface = NSXPCInterface(with: InlineContentServerProtocol.self)

		serviceConnection.remoteObjectInterface = remoteObjectInterface
		serviceConnection.exportedInterface = NSXPCInterface(with: InlineContentClientProtocol.self)
		serviceConnection.exportedObject = self

		serviceConnection.interruptionHandler = { [weak self] in
			DispatchQueue.main.async {
				self?.interruptionHandler()
			}

			inlineMediaLogger.log("Interruption handler called")
		}

		serviceConnection.invalidationHandler = { [weak self] in
			DispatchQueue.main.async {
				self?.invalidationHandler()
			}

			inlineMediaLogger.log("Invalidation handler called")
		}

		serviceConnection.resume()

		self.serviceConnection = serviceConnection

		registerDefaults()
		registerPlugins()
	}

	private func interruptionHandler() {
		invalidateProcess()
	}

	private func invalidationHandler() {
		serviceConnection = nil
	}

	@objc public func prepareForApplicationTermination() {
		inlineMediaLogger.log("Invalidating media service process")
		invalidateProcess()
	}

	private func registerDefaults() {
		remoteObjectProxy?.warmService(with: .current())
	}

	private func registerPlugins() {
		remoteObjectProxy?.warmServiceByLoadingPlugins()
	}

	private var remoteObjectProxy: InlineContentServerProtocol? {
		remoteObjectProxyWithErrorHandler(nil)
	}

	private func remoteObjectProxyWithErrorHandler(
		_ handler: ((NSError) -> Void)?
	) -> InlineContentServerProtocol? {
		serviceConnection?.remoteObjectProxyWithErrorHandler { error in
			inlineMediaLogger.error(
				"Error occurred while communicating with service: \(error.localizedDescription, privacy: .public)"
			)
			handler?(error as NSError)
		} as? InlineContentServerProtocol
	}

	@objc(processAddress:withUniqueIdentifier:atLineNumber:index:forItem:)
	@MainActor
	public func processAddress(
		_ address: String,
		withUniqueIdentifier uniqueIdentifier: String,
		atLineNumber lineNumber: String,
		index: UInt,
		forItem item: IRCTreeItem
	) {
		var url = URL(string: address, encodingInvalidCharacters: true)

		if url == nil {
			url = URLComponents(string: address, encodingInvalidCharacters: true)?.url
		}

		guard let url else {
			inlineMediaLogger.error("Address could not be normalized")
			return
		}

		processURL(
			url,
			withUniqueIdentifier: uniqueIdentifier,
			atLineNumber: lineNumber,
			index: index,
			forItem: item
		)
	}

	@objc(processURL:withUniqueIdentifier:atLineNumber:index:forItem:)
	@MainActor
	public func processURL(
		_ url: URL,
		withUniqueIdentifier uniqueIdentifier: String,
		atLineNumber lineNumber: String,
		index: UInt,
		forItem item: IRCTreeItem
	) {
		warmProcessIfNeeded()

		remoteObjectProxy?.process(
			url,
			withUniqueIdentifier: uniqueIdentifier,
			atLineNumber: lineNumber,
			index: index,
			inView: item.uniqueIdentifier
		)
	}

	@objc public func reloadService() {
		invalidateProcess()
	}

	@objc(processingPayloadSucceeded:)
	public func processingPayloadSucceeded(_ payload: InlineContentPayload) {
		performOnMain {
			guard let item = AppController.shared.world.findItem(withId: payload.viewIdentifier) else {
				return
			}

			self.processingPayloadSucceeded(payload, forItem: item)
		}
	}

	@objc(processingPayload:failedWithError:)
	public func processingPayload(_ payload: InlineContentPayload, failedWithError error: Error) {
		let error = error as NSError
		performOnMain {
			guard let item = AppController.shared.world.findItem(withId: payload.viewIdentifier) else {
				return
			}

			self.processingPayload(payload, forItem: item, failedWithError: error)
		}
	}

	@MainActor
	private func processingPayloadSucceeded(_ payload: InlineContentPayload, forItem item: IRCTreeItem) {
		item.logController?.processingInlineMediaPayloadSucceeded(payload)
	}

	@MainActor
	private func processingPayload(
		_ payload: InlineContentPayload,
		forItem item: IRCTreeItem,
		failedWithError error: NSError
	) {
		item.logController?.processingInlineMediaPayload(
			payload,
			failedWithError: error
		)
	}

	@objc(askPermissionToEnableInlineMediaWithCompletionBlock:)
	public static func askPermissionToEnableInlineMedia(completionBlock: @escaping @Sendable (Bool) -> Void) {
		/* ISOLATION-EXCEPTION: reached from the XPC callback queue; the alert has to
		 be raised on the main thread and callers expect it to have been presented
		 by the time this returns. */
		performSynchronouslyOnMainQueue {
			MainActor.assumeIsolated {
				askPermissionToEnableInlineMediaOnMain(completionBlock: completionBlock)
			}
		}
	}

	@MainActor
	private static func askPermissionToEnableInlineMediaOnMain(
		completionBlock: @escaping @Sendable (Bool) -> Void
	) {
		let clientList = AppController.shared.world.clientList
		let presentDialog = clientList.contains { client in
			client.config.proxyType != .none
		}

		if presentDialog == false {
			completionBlock(true)
			return
		}

		var window = NSApp.keyWindow
		if window == nil {
			window = AppController.shared.mainWindow
		}

		guard let window else {
			completionBlock(false)
			return
		}

		presentInlineMediaPermissionAlert(for: window, completionBlock: completionBlock)
	}

	@MainActor
	private static func presentInlineMediaPermissionAlert(
		for window: NSWindow,
		completionBlock: @escaping @Sendable (Bool) -> Void
	) {
		let alert = NSAlert()
		alert.alertStyle = .warning
		alert.messageText = PromptStrings.InlineMedia.title
		alert.informativeText = PromptStrings.InlineMedia.body
		alert.addButton(withTitle: PromptStrings.InlineMedia.turnOnButtonTitle)
		alert.addButton(withTitle: PromptStrings.Action.cancel)
		alert.addButton(withTitle: PromptStrings.InlineMedia.openSystemSettingsButtonTitle)

		alert.beginSheetModal(for: window) { response in
			if response == .alertThirdButtonReturn {
				PreferencesController.openProxySettingsInSystemPreferences()

				DispatchQueue.main.async {
					presentInlineMediaPermissionAlert(for: window, completionBlock: completionBlock)
				}

				return
			}

			completionBlock(response == .alertFirstButtonReturn)
		}
	}

	/* ISOLATION-EXCEPTION: the XPC callbacks below are nonisolated and their
	 results must land before the service's reply returns. */
	private func performOnMain(_ operation: @escaping @MainActor () -> Void) {
		performSynchronouslyOnMainQueue {
			MainActor.assumeIsolated {
				operation()
			}
		}
	}
}
