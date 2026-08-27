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

import Foundation
import Observation

@MainActor
@Observable
final class ChannelTopicModel {
	private(set) var formattedTopic: String
	private(set) var hasPresentedMaximumLengthWarning = false

	let maximumLength: Int

	init(formattedTopic: String, maximumLength: UInt) {
		self.formattedTopic = formattedTopic
		self.maximumLength = Int(clamping: maximumLength)
	}

	var formattedTopicLength: Int {
		formattedTopic.utf16.count
	}

	var topicForSubmission: String {
		formattedTopic.replacingOccurrences(of: "\n", with: " ")
	}

	@discardableResult
	func updateFormattedTopic(_ topic: String) -> Bool {
		formattedTopic = topic

		guard maximumLength > 0,
		      formattedTopicLength > maximumLength,
		      hasPresentedMaximumLengthWarning == false
		else {
			return false
		}

		hasPresentedMaximumLengthWarning = true
		return true
	}
}
