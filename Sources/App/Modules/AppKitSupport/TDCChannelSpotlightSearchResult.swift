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

@objc(TDCChannelSpotlightSearchResult)
public final class ChannelSpotlightSearchResult: NSObject {
	@objc public private(set) weak var channel: IRCChannel?
	@objc public private(set) var distance: NSNumber = 0

	@available(*, unavailable)
	override public init() {
		fatalError("init() is unavailable; use init(channel:)")
	}

	@objc(initWithChannel:)
	public init(channel: IRCChannel) {
		self.channel = channel
		super.init()
		distance = 0
	}

	@objc public var clientId: String {
		channel?.associatedClient?.uniqueIdentifier ?? ""
	}

	@objc(compare:)
	public func compare(_ other: ChannelSpotlightSearchResult) -> ComparisonResult {
		let localDistance = distance.doubleValue
		let remoteDistance = other.distance.doubleValue

		if localDistance > remoteDistance {
			return .orderedAscending
		}

		if localDistance < remoteDistance {
			return .orderedDescending
		}

		return .orderedSame
	}

	@objc(recalculateDistanceWith:)
	public func recalculateDistance(with searchString: String) {
		guard searchString.isEmpty == false, let channel else {
			distance = 0
			return
		}

		let distanceValue = (channel.name as NSString).compare(
			withWord: searchString,
			lengthPenaltyWeight: 1.0
		)

		distance = NSNumber(value: distanceValue)
	}
}
