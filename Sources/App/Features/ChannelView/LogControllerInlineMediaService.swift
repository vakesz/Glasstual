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
import InlineContentKit
import os

private nonisolated let inlineMediaLogger = Logger( // nonisolated: let
	subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
	category: "InlineMediaService"
)

/** The app's side of the inline-content loader.

 Main-actor throughout: it normalises the address the renderer found, hands the
 work to `InlineMediaClient`, and applies the loader's answer to the view that
 asked for it. */
@MainActor
public final class LogControllerInlineMediaService {
	public static let sharedInstance = LogControllerInlineMediaService()

	public static func shared() -> LogControllerInlineMediaService {
		sharedInstance
	}

	// MARK: - Process life cycle

	public func warmProcessIfNeeded() {
		Task { await InlineMediaClient.shared.attach() }
	}

	public func invalidateProcess() {
		Task { await InlineMediaClient.shared.detach() }
	}

	public func prepareForApplicationTermination() {
		inlineMediaLogger.log("Invalidating media service process")
		invalidateProcess()
	}

	public func reloadService() {
		invalidateProcess()
	}

	// MARK: - Requests

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

	public func processURL(
		_ url: URL,
		withUniqueIdentifier uniqueIdentifier: String,
		atLineNumber lineNumber: String,
		index: UInt,
		forItem item: IRCTreeItem
	) {
		let viewIdentifier = item.uniqueIdentifier

		Task {
			await InlineMediaClient.shared.process(
				url,
				withUniqueIdentifier: uniqueIdentifier,
				atLineNumber: lineNumber,
				index: index,
				inView: viewIdentifier
			)
		}
	}

	// MARK: - Replies

	/// The loader finished with a payload. Awaited by the client actor, so the
	/// result lands on the main actor without a synchronous queue hop.
	static func deliverPayloadSucceeded(_ payload: InlineContentPayload) {
		guard let item = AppController.shared.world.findItem(withId: payload.viewIdentifier) else {
			return
		}

		item.logController?.processingInlineMediaPayloadSucceeded(payload)
	}

	static func deliverPayload(_ payload: InlineContentPayload, failedWith error: NSError) {
		guard let item = AppController.shared.world.findItem(withId: payload.viewIdentifier) else {
			return
		}

		item.logController?.processingInlineMediaPayload(payload, failedWithError: error)
	}

	// MARK: - Permission

	/** Asks whether inline media may be turned on while a proxy is configured.

	 Nothing here talks to the service: it is a main-actor alert, and it always
	 was — it used to be reached from the loader's callback queue and had to
	 block its way back onto the main thread. */
	public static func askPermissionToEnableInlineMedia(
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

				/* The sheet has to be off screen before the next one goes up. */
				Task { @MainActor in
					presentInlineMediaPermissionAlert(for: window, completionBlock: completionBlock)
				}

				return
			}

			completionBlock(response == .alertFirstButtonReturn)
		}
	}
}
