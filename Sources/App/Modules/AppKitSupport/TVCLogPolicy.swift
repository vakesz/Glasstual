/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\\_\\__|\\__,_|\\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import AppKit
import CocoaExtensions
import os
import WebKit

private enum WebKit2MenuItemTag {
	static let inspectElement = 57
	static let lookupInDictionary = 22
	static let searchWithGoogle = 21
}

private struct WebKitMenuItems {
	var inspect: NSMenuItem?
	var lookup: NSMenuItem?
	var search: NSMenuItem?
}

@objc(TVCLogPolicyTarget)
public final class LogPolicyTarget: NSObject {
	@objc public var anchorURL: String?
	@objc public var channelName: String?
	@objc public var nickname: String?
	@objc public var lineNumber: String?
	@objc public var lineMessageIdentifier: String?
	@objc public var lineType: String?
	@objc public var lineNickname: String?
	@objc public var lineExcerpt: String?
}

@objc(TVCLogPolicy)
@MainActor
public final class LogPolicy: NSObject {
	private nonisolated static let logger = Logger(
		subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
		category: "LogPolicy"
	)

	@objc(displayContextMenuInWebView:)
	public func displayContextMenu(in webView: LogView) {
		let contextMenu = constructContextMenu(for: webView, withDefaultMenuItems: [])

		let webViewBacking = webView.webView

		guard let webViewWindow = webViewBacking.window else {
			return
		}

		let mouseLocationGlobal = NSEvent.mouseLocation
		let mouseLocationLocal = webViewWindow.convertFromScreen(
			NSRect(x: mouseLocationGlobal.x, y: mouseLocationGlobal.y, width: 0, height: 0)
		)

		let event = NSEvent.mouseEvent(
			with: .rightMouseUp,
			location: mouseLocationLocal.origin,
			modifierFlags: [],
			timestamp: 0,
			windowNumber: webViewWindow.windowNumber,
			context: nil,
			eventNumber: 0,
			clickCount: 0,
			pressure: 0
		)

		NSMenu.popUpContextMenu(contextMenu, with: event!, for: webViewBacking)
	}

	@objc(channelNameDoubleClickedInWebView:)
	public func channelNameDoubleClicked(in webView: LogView) {
		guard let channelName = webView.takeContextMenuTarget().channelName else {
			return
		}

		AppController.shared.menuController?.joinChannelClicked(channelName)
	}

	@objc(nicknameDoubleClickedInWebView:)
	public func nicknameDoubleClicked(in webView: LogView) {
		guard let nickname = webView.takeContextMenuTarget().nickname else {
			return
		}

		AppController.shared.menuController?.pointedNickname = nickname
		AppController.shared.menuController?.memberInChannelViewDoubleClicked(nil)
	}

	@objc public func topicBarDoubleClicked() {
		AppController.shared.menuController?.showChannelModifyTopicSheet(nil)
	}

	@objc(webView2:logView:didReceiveAuthenticationChallenge:completionHandler:)
	public func webView2(
		_: WKWebView,
		logView _: LogView,
		didReceive challenge: URLAuthenticationChallenge,
		completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
	) {
		if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
			completionHandler(.performDefaultHandling, nil)
		} else {
			completionHandler(.cancelAuthenticationChallenge, nil)
		}
	}

	@objc(webView2:logView:decidePolicyForNavigationAction:decisionHandler:)
	public func webView2(
		_: WKWebView,
		logView _: LogView,
		decidePolicyFor navigationAction: WKNavigationAction,
		decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
	) {
		if navigationAction.navigationType == .linkActivated {
			decisionHandler(.cancel)

			guard let actionURL = navigationAction.request.url else {
				return
			}

			openWebpage(actionURL)
			return
		}

		/* A missing target frame means a new window, which the log view never
		 opens, so it is held to the main frame's rules. */
		let inMainFrame = navigationAction.targetFrame?.isMainFrame ?? true
		let actionURL = navigationAction.request.url
		guard LogViewContentPolicy.permitsNavigation(to: actionURL, inMainFrame: inMainFrame) else {
			let address = actionURL?.absoluteString ?? "(no address)"
			Self.logger.error("Cancelled a navigation out of the log view: \(address, privacy: .public)")
			decisionHandler(.cancel)
			return
		}

		decisionHandler(.allow)
	}

	@objc(webView2:logView:contextMenuWithDefaultMenu:)
	public func webView2(
		_: WKWebView,
		logView: LogView,
		contextMenuWithDefaultMenu defaultMenu: NSMenu
	) -> NSMenu {
		constructContextMenu(for: logView, withDefaultMenuItems: defaultMenu.items)
	}

	private func constructContextMenu(for webView: LogView, withDefaultMenuItems defaultMenuItems: [NSMenuItem])
		-> NSMenu
	{
		let contextMenu = NSMenu(title: "Context Menu")
		let menuItems = constructContextMenuItems(for: webView, defaultMenuItems: defaultMenuItems)

		for menuItem in menuItems {
			contextMenu.addItem(menuItem)
		}

		AppController.shared.menuController?.applySymbols(to: contextMenu)

		return contextMenu
	}

	private func constructContextMenuItems(
		for webView: LogView,
		defaultMenuItems: [NSMenuItem]
	) -> [NSMenuItem] {
		let target = webView.takeContextMenuTarget()
		if let anchorURL = target.anchorURL {
			return linkMenuItems(for: anchorURL)
		}
		if let nickname = target.nickname {
			return nicknameMenuItems(for: nickname, target: target, in: webView)
		}
		if let channelName = target.channelName {
			return copiedMenuItems(
				from: AppController.shared.menuController?.channelViewChannelNameMenu,
				userInfo: channelName
			)
		}
		return generalMenuItems(target: target, in: webView, defaultMenuItems: defaultMenuItems)
	}

	private func linkMenuItems(for address: String) -> [NSMenuItem] {
		var menuItems = copiedMenuItems(
			from: AppController.shared.menuController?.channelViewURLMenu,
			userInfo: address
		)
		menuItems.append(.separator())
		let shareItems = URL(string: address).map { [$0] } ?? []
		if let shareItem = AppController.shared.menuController?.shareMenuItem(forItems: shareItems) {
			menuItems.append(shareItem)
		}
		return menuItems
	}

	private func nicknameMenuItems(
		for nickname: String,
		target: LogPolicyTarget,
		in webView: LogView
	) -> [NSMenuItem] {
		guard let channel = webView.viewController?.associatedChannel, channel.isUtility == false else {
			return [NSMenuItem(title: ApplicationStrings.noActionsAvailable, action: nil, keyEquivalent: "")]
		}
		var menuItems = copiedMenuItems(
			from: AppController.shared.menuController?.userControlMenu,
			userInfo: nickname
		)
		menuItems.append(contentsOf: messageMenuItems(for: target, in: webView))
		return menuItems
	}

	private func copiedMenuItems(from menu: NSMenu?, userInfo: String) -> [NSMenuItem] {
		menu?.items.compactMap { item in
			guard let copy = item.copy() as? NSMenuItem else {
				return nil
			}
			copy.textual_setUserInfo(userInfo, recursively: true)
			return copy
		} ?? []
	}

	private func generalMenuItems(
		target: LogPolicyTarget,
		in webView: LogView,
		defaultMenuItems: [NSMenuItem]
	) -> [NSMenuItem] {
		let webKitItems = webKitMenuItems(from: defaultMenuItems)
		let menu = AppController.shared.menuController?.channelViewGeneralMenu
		var menuItems = menu?.items.compactMap { item -> NSMenuItem? in
			guard let copy = item.copy() as? NSMenuItem else {
				return nil
			}
			if copy.tag == 1202, let search = webKitItems.search {
				return search
			}
			if copy.tag == 1203, let lookup = webKitItems.lookup {
				return lookup
			}
			return copy
		} ?? []
		menuItems.append(contentsOf: messageMenuItems(for: target, in: webView))
		if TextualPreferences.developerModeEnabled() {
			menuItems.append(contentsOf: developerMenuItems(inspectElementItem: webKitItems.inspect))
		}
		return menuItems
	}

	private func webKitMenuItems(from items: [NSMenuItem]) -> WebKitMenuItems {
		var result = WebKitMenuItems()
		for item in items {
			switch item.tag {
			case WebKit2MenuItemTag.lookupInDictionary: result.lookup = item.copy() as? NSMenuItem
			case WebKit2MenuItemTag.inspectElement: result.inspect = item.copy() as? NSMenuItem
			case WebKit2MenuItemTag.searchWithGoogle: result.search = item.copy() as? NSMenuItem
			default: break
			}
		}
		return result
	}

	private func developerMenuItems(inspectElementItem: NSMenuItem?) -> [NSMenuItem] {
		let menuController = AppController.shared.menuController
		let inspectItem = inspectElementItem ?? developerMenuItem(
			title: ApplicationStrings.openWebInspector,
			action: #selector(TXMenuController.openWebInspector(_:)),
			target: menuController
		)
		return [
			.separator(),
			developerMenuItem(
				title: ApplicationStrings.copyLogAsHTML,
				action: #selector(TXMenuController.copyLogAsHtml(_:)),
				target: menuController
			),
			developerMenuItem(
				title: ApplicationStrings.forceReloadStyle,
				action: #selector(TXMenuController.forceReloadTheme(_:)),
				target: menuController
			),
			inspectItem,
		]
	}

	private func messageMenuItems(for target: LogPolicyTarget, in webView: LogView) -> [NSMenuItem] {
		guard
			let messageIdentifier = target.lineMessageIdentifier,
			messageIdentifier.isEmpty == false,
			let lineType = target.lineType,
			lineType == "privmsg" || lineType == "action" || lineType == "notice",
			let channel = webView.viewController?.associatedChannel,
			channel.isUtility == false
		else {
			return []
		}

		return AppController.shared.menuController?.messageReplyMenuItems(
			forMessageIdentifier: messageIdentifier,
			nickname: target.lineNickname,
			excerpt: target.lineExcerpt
		) ?? []
	}

	@objc public func openWebpage(_ webpageURL: URL) {
		var openInBackground = TextualPreferences.openBrowserInBackground()

		let keyboardKeys = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
		if keyboardKeys.contains(.command) {
			openInBackground.toggle()
		}

		let scheme = webpageURL.scheme?.lowercased()
		if scheme == "http" || scheme == "https" || scheme == "glasstual" {
			OpenLink.open(url: webpageURL, inBackground: openInBackground)
			return
		}

		let applicationName = NSWorkspace.shared.textual_nameOfApplication(toOpen: webpageURL) ?? ""

		let openLink = TDCAlert.modalAlert(
			withMessage: PromptStrings.ExternalApplication.body(url: webpageURL.absoluteString),
			title: PromptStrings.ExternalApplication.title(applicationName: applicationName),
			defaultButton: PromptStrings.Action.yes,
			alternateButton: PromptStrings.Action.no,
			suppressionKey: "open_non_http_url_warning",
			suppressionText: nil
		)

		if openLink {
			OpenLink.open(url: webpageURL, inBackground: openInBackground)
		}
	}

	private func developerMenuItem(title: String, action: Selector, target: TXMenuController?) -> NSMenuItem {
		let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
		item.target = target
		return item
	}
}
