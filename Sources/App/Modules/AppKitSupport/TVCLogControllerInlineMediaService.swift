/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\\_\\__|\\__,_|\\__,_|_|
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

private let inlineMediaLogger = Logger(
	subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
	category: "InlineMediaService"
)

@objc(TVCLogControllerInlineMediaService)
public final class LogControllerInlineMediaService: NSObject, InlineContentClientProtocol, @unchecked Sendable {
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
		guard let allowedLocationClasses = NSSet(objects: NSArray.self, NSURL.self) as? Set<AnyHashable> else {
			preconditionFailure("Unable to configure the inline-media XPC class allowlist")
		}

		remoteObjectInterface.setClasses(
			allowedLocationClasses,
			for: #selector((any InlineContentServerProtocol).warmServiceByLoadingPlugins(atLocations:)),
			argumentIndex: 0,
			ofReply: false
		)

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
		let defaults = TextualUserDefaults.shared().registeredDefaults
		remoteObjectProxy?.warmServiceByRegistering(defaults: defaults)
	}

	private func registerPlugins() {
		let pluginLocations = [applicationSupportInlineMediaPluginsURL()]
		remoteObjectProxy?.warmServiceByLoadingPlugins(atLocations: pluginLocations)
	}

	private func applicationSupportInlineMediaPluginsURL() -> URL {
		let sourceURL = PathInfo.groupContainerApplicationSupportURL!
		let baseURL = sourceURL.appendingPathComponent("Inline Media Modules/", isDirectory: true)
		PathInfo.createDirectory(at: baseURL)
		return baseURL
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
			guard let item = NSObject.applicationController().world.findItem(withId: payload.viewIdentifier) else {
				return
			}

			self.processingPayloadSucceeded(payload, forItem: item)
		}
	}

	@objc(processingPayload:failedWithError:)
	public func processingPayload(_ payload: InlineContentPayload, failedWithError error: Error) {
		let error = error as NSError
		performOnMain {
			guard let item = NSObject.applicationController().world.findItem(withId: payload.viewIdentifier) else {
				return
			}

			self.processingPayload(payload, forItem: item, failedWithError: error)
		}
	}

	@MainActor
	private func processingPayloadSucceeded(_ payload: InlineContentPayload, forItem item: IRCTreeItem) {
		(item.viewController as AnyObject as? LogController)?.processingInlineMediaPayloadSucceeded(payload)
	}

	@MainActor
	private func processingPayload(
		_ payload: InlineContentPayload,
		forItem item: IRCTreeItem,
		failedWithError error: NSError
	) {
		(item.viewController as AnyObject as? LogController)?.processingInlineMediaPayload(
			payload,
			failedWithError: error
		)
	}

	@objc(askPermissionToEnableInlineMediaWithCompletionBlock:)
	public static func askPermissionToEnableInlineMedia(completionBlock: @escaping @Sendable (Bool) -> Void) {
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
		let clientList = NSObject.applicationController().world.clientList
		let presentDialog = clientList.contains { client in
			client.config.proxyType != .none
		}

		if presentDialog == false {
			completionBlock(true)
			return
		}

		var window = NSApp.keyWindow
		if window == nil {
			window = NSObject.applicationController().mainWindow
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

	private func performOnMain(_ operation: @escaping @MainActor () -> Void) {
		performSynchronouslyOnMainQueue {
			MainActor.assumeIsolated {
				operation()
			}
		}
	}
}
