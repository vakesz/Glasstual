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
import WebKit

private enum WebKit2MenuItemTag {
	static let inspectElement = 57
	static let lookupInDictionary = 22
	static let searchWithGoogle = 21
}

@objc(TVCLogPolicyTarget)
public final class TVCLogPolicyTarget: NSObject {
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
public final class TVCLogPolicy: NSObject {
	@objc(displayContextMenuInWebView:)
	public func displayContextMenu(in webView: TVCLogView) {
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
	public func channelNameDoubleClicked(in webView: TVCLogView) {
		guard let channelName = webView.takeContextMenuTarget().channelName else {
			return
		}

		NSObject.masterController().menuController?.joinChannelClicked(channelName)
	}

	@objc(nicknameDoubleClickedInWebView:)
	public func nicknameDoubleClicked(in webView: TVCLogView) {
		guard let nickname = webView.takeContextMenuTarget().nickname else {
			return
		}

		NSObject.masterController().menuController?.pointedNickname = nickname
		NSObject.masterController().menuController?.memberInChannelViewDoubleClicked(nil)
	}

	@objc public func topicBarDoubleClicked() {
		NSObject.masterController().menuController?.showChannelModifyTopicSheet(nil)
	}

	@objc(webView2:logView:didReceiveAuthenticationChallenge:completionHandler:)
	public func webView2(
		_: WKWebView,
		logView _: TVCLogView,
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
		logView _: TVCLogView,
		decidePolicyFor navigationAction: WKNavigationAction,
		decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
	) {
		if navigationAction.navigationType == .linkActivated {
			decisionHandler(.cancel)

			guard let actionURL = navigationAction.request.url else {
				return
			}

			openWebpage(actionURL)
		} else {
			decisionHandler(.allow)
		}
	}

	@objc(webView2:logView:contextMenuWithDefaultMenu:)
	public func webView2(
		_: WKWebView,
		logView: TVCLogView,
		contextMenuWithDefaultMenu defaultMenu: NSMenu
	) -> NSMenu {
		constructContextMenu(for: logView, withDefaultMenuItems: defaultMenu.items)
	}

	private func constructContextMenu(for webView: TVCLogView, withDefaultMenuItems defaultMenuItems: [NSMenuItem])
		-> NSMenu
	{
		let contextMenu = NSMenu(title: "Context Menu")
		let menuItems = constructContextMenuItems(for: webView, defaultMenuItems: defaultMenuItems)

		for menuItem in menuItems {
			contextMenu.addItem(menuItem)
		}

		NSObject.masterController().menuController?.applySymbols(to: contextMenu)

		return contextMenu
	}

	private func constructContextMenuItems(
		for webView: TVCLogView,
		defaultMenuItems: [NSMenuItem]
	) -> [NSMenuItem] {
		let viewController = webView.viewController
		let target = webView.takeContextMenuTarget()
		let anchorURL = target.anchorURL
		let nickname = target.nickname
		let channelName = target.channelName
		var menuItems: [NSMenuItem] = []

		if let anchorURL {
			let urlMenu = NSObject.masterController().menuController?.channelViewURLMenu

			for item in urlMenu?.items ?? [] {
				guard let newItem = item.copy() as? NSMenuItem else {
					continue
				}

				newItem.setUserInfo(anchorURL, recursively: true)
				menuItems.append(newItem)
			}

			let shareURL = URL(string: anchorURL)
			let shareItems = shareURL.map { [$0] } ?? []

			menuItems.append(.separator())
			if let shareItem = NSObject.masterController().menuController?.shareMenuItem(forItems: shareItems) {
				menuItems.append(shareItem)
			}
		} else if let nickname {
			if viewController?.associatedChannel == nil || viewController?.associatedChannel?.isUtility == true {
				menuItems.append(
					NSMenuItem(
						title: LocalizedKey("BasicLanguage[7kc-mo]"),
						action: nil,
						keyEquivalent: ""
					)
				)
			} else {
				let memberMenu = NSObject.masterController().menuController?.userControlMenu

				for item in memberMenu?.items ?? [] {
					guard let newItem = item.copy() as? NSMenuItem else {
						continue
					}

					newItem.setUserInfo(nickname, recursively: true)
					menuItems.append(newItem)
				}

				menuItems.append(contentsOf: messageMenuItems(for: target as! TVCLogPolicyTarget, in: webView))
			}
		} else if let channelName {
			let chanMenu = NSObject.masterController().menuController?.channelViewChannelNameMenu

			for item in chanMenu?.items ?? [] {
				guard let newItem = item.copy() as? NSMenuItem else {
					continue
				}

				newItem.setUserInfo(channelName, recursively: true)
				menuItems.append(newItem)
			}
		} else {
			let menu = NSObject.masterController().menuController?.channelViewGeneralMenu

			var inspectElementItem: NSMenuItem?
			var lookupInDictionaryItem: NSMenuItem?
			var searchWithGoogleItem: NSMenuItem?

			for item in defaultMenuItems {
				switch item.tag {
				case WebKit2MenuItemTag.lookupInDictionary:
					lookupInDictionaryItem = item.copy() as? NSMenuItem
				case WebKit2MenuItemTag.inspectElement:
					inspectElementItem = item.copy() as? NSMenuItem
				case WebKit2MenuItemTag.searchWithGoogle:
					searchWithGoogleItem = item.copy() as? NSMenuItem
				default:
					break
				}
			}

			for item in menu?.items ?? [] {
				guard var newItem = item.copy() as? NSMenuItem else {
					continue
				}

				if newItem.tag == 1202, let searchWithGoogleItem {
					menuItems.append(searchWithGoogleItem)
					continue
				}

				if newItem.tag == 1203, let lookupInDictionaryItem {
					menuItems.append(lookupInDictionaryItem)
					continue
				}

				menuItems.append(newItem)
			}

			menuItems.append(contentsOf: messageMenuItems(for: target as! TVCLogPolicyTarget, in: webView))

			if TPCPreferences.developerModeEnabled() {
				let menuController = NSObject.masterController().menuController
				menuItems.append(.separator())
				menuItems.append(
					developerMenuItem(
						title: LocalizedKey("BasicLanguage[6cw-ni]"),
						action: #selector(TXMenuController.copyLogAsHtml(_:)),
						target: menuController
					)
				)
				menuItems.append(
					developerMenuItem(
						title: LocalizedKey("BasicLanguage[ngd-ms]"),
						action: #selector(TXMenuController.forceReloadTheme(_:)),
						target: menuController
					)
				)

				if let inspectElementItem {
					menuItems.append(inspectElementItem)
				} else {
					menuItems.append(
						developerMenuItem(
							title: LocalizedKey("BasicLanguage[tfj-m9]"),
							action: #selector(TXMenuController.openWebInspector(_:)),
							target: menuController
						)
					)
				}
			}
		}

		return menuItems
	}

	private func messageMenuItems(for target: TVCLogPolicyTarget, in webView: TVCLogView) -> [NSMenuItem] {
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

		return NSObject.masterController().menuController?.messageReplyMenuItems(
			forMessageIdentifier: messageIdentifier,
			nickname: target.lineNickname,
			excerpt: target.lineExcerpt
		) ?? []
	}

	@objc public func openWebpage(_ webpageURL: URL) {
		var openInBackground = TPCPreferences.openBrowserInBackground()

		let keyboardKeys = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
		if keyboardKeys.contains(.command) {
			openInBackground.toggle()
		}

		let scheme = webpageURL.scheme?.lowercased()
		if scheme == "http" || scheme == "https" || scheme == "glasstual" {
			OpenLink.open(url: webpageURL, inBackground: openInBackground)
			return
		}

		let applicationName = NSWorkspace.shared.nameOfApplication(toOpen: webpageURL) ?? ""

		let openLink = TDCAlert.modalAlert(
			withMessage: LocalizedKey("Prompts[5oq-vv]", webpageURL.absoluteString),
			title: LocalizedKey("Prompts[2ul-cl]", applicationName),
			defaultButton: LocalizedKey("Prompts[mvh-ms]"),
			alternateButton: LocalizedKey("Prompts[99q-gg]"),
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
