/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import Foundation

@objc(THOPluginDidPostNewMessageConcreteObject)
public final class PluginPostedMessage: NSObject {
	@objc public var isProcessedInBulk = false
	@objc public var messageContents = ""
	@objc public var lineNumber = ""
	@objc public var senderNickname: String?
	@objc public var lineType: TVCLogLineType = .undefined
	@objc public var memberType: TVCLogLineMemberType = .normal
	@objc public var receivedAt = Date()
	@objc public var listOfHyperlinks: [TLOLinkParserResult] = []
	@objc public var listOfUsers: Set<IRCChannelUser> = []
	@objc public var keywordMatchFound = false
}

@objc(THOPluginDidReceiveServerInputConcreteObject)
public final class PluginServerInput: NSObject {
	@objc public var senderIsServer = false
	@objc public var senderNickname = ""
	@objc public var senderUsername: String?
	@objc public var senderAddress: String?
	@objc public var senderHostmask = ""
	@objc public var receivedAt = Date()
	@objc public var messageSequence = ""
	@objc public var messageParameters: [String] = []
	@objc(messageParamaters) public var legacyMessageParameters: [String] {
		get { messageParameters }
		set { messageParameters = newValue }
	}

	@objc public var messageCommand = ""
	@objc public var messageCommandNumeric: UInt = 0
	@objc public var networkAddress: String?
	@objc public var networkName: String?
}

@objc(THOPluginWebViewJavaScriptPayloadConcreteObject)
public final class PluginJavaScriptPayload: NSObject {
	@objc public var payloadLabel = ""
	@objc public var payloadContents: Any?
}

@objc(THOPluginOutputSuppressionRule)
public final class PluginOutputSuppressionRule: NSObject {
	@objc public var match = ""
	@objc public var restrictConsole = false
	@objc public var restrictChannel = false
	@objc public var restrictPrivateMessage = false
}
