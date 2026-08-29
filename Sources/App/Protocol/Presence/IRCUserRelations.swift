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

/** Which channels one person is in.

 It used to map each channel to the person's `ChannelUser` as well, so the same
 member object lived in two places. A member is a value now and the channel's
 member list owns it, so this records only where to look: ask the channel. */
@MainActor
public final class UserRelations {
	private var storage: [IRCChannel: Void] = [:]

	public init() {}

	public var relatedChannels: [IRCChannel] {
		Array(storage.keys)
	}

	public var numberOfRelations: Int {
		storage.count
	}

	public func associate(with channel: IRCChannel) {
		guard channel.isChannel else {
			return
		}

		storage[channel] = ()
	}

	public func disassociate(from channel: IRCChannel) {
		storage.removeValue(forKey: channel)
	}

	public func isAssociated(with channel: IRCChannel) -> Bool {
		storage[channel] != nil
	}
}
