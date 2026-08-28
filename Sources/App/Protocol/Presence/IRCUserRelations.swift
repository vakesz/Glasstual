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

@objc(IRCUserRelations)
@MainActor
public final class UserRelations: NSObject {
	private let lock = NSLock()
	private var storage: [IRCChannel: ChannelUser] = [:]

	@objc public var relations: [IRCChannel: ChannelUser] {
		withLock { storage }
	}

	@objc public var relatedChannels: [IRCChannel] {
		withLock { Array(storage.keys) }
	}

	@objc public var relatedUsers: [ChannelUser] {
		withLock { Array(storage.values) }
	}

	@objc public var numberOfRelations: UInt {
		withLock { UInt(storage.count) }
	}

	@objc(associateUser:withChannel:)
	public func associate(_ user: ChannelUser, with channel: IRCChannel) {
		guard channel.isChannel else {
			return
		}

		withLock {
			storage[channel] = user
		}
	}

	@objc(disassociateUserWithChannel:)
	public func disassociateUser(with channel: IRCChannel) {
		guard channel.isChannel else {
			return
		}

		withLock {
			storage.removeValue(forKey: channel)
		}
	}

	@objc(userAssociatedWithChannel:)
	public func userAssociated(with channel: IRCChannel) -> ChannelUser? {
		guard channel.isChannel else {
			return nil
		}

		return withLock { storage[channel] }
	}

	@objc(enumerateRelations:)
	public func enumerateRelations(
		_ block: (IRCChannel, ChannelUser, UnsafeMutablePointer<ObjCBool>) -> Void
	) {
		let snapshot = relations
		var stop = ObjCBool(false)

		withUnsafeMutablePointer(to: &stop) { stopPointer in
			for (channel, member) in snapshot {
				block(channel, member, stopPointer)

				if stopPointer.pointee.boolValue {
					break
				}
			}
		}
	}

	@discardableResult
	private func withLock<Result>(_ operation: () -> Result) -> Result {
		lock.lock()
		defer { lock.unlock() }

		return operation()
	}
}
