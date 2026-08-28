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

import Foundation

@objc(TLOSpokenNotification)
public final nonisolated class SpokenNotification: NSObject, @unchecked Sendable {
	@objc public private(set) weak var client: IRCClient!
	@objc public private(set) weak var channel: IRCChannel!
	@objc public private(set) var nickname: String!
	@objc public private(set) var text: String!
	@objc public private(set) var lineType: TVCLogLineType
	@objc public private(set) var notificationType: TXNotificationType
	/** The text the synthesizer speaks. Formatting reads main-actor client state,
	 so the producer fills it in before the notification is queued. */
	@objc public var spokenText: String?

	@objc(initWithNotification:lineType:target:nickname:text:)
	@MainActor
	public init(
		notificationType: TXNotificationType,
		lineType: TVCLogLineType,
		target: IRCTreeItem!,
		nickname: String!,
		text: String!
	) {
		self.notificationType = notificationType
		self.lineType = lineType

		if target?.isClient == true {
			client = target as? IRCClient
		} else {
			client = target?.associatedClient
			channel = (target as AnyObject?) as? IRCChannel
		}

		self.nickname = nickname
		self.text = text

		super.init()
	}
}
