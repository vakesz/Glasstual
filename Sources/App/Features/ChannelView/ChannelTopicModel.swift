/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
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
	var formattedTopic: String

	let maximumLength: Int

	init(formattedTopic: String, maximumLength: UInt) {
		self.formattedTopic = formattedTopic
		self.maximumLength = Int(clamping: maximumLength)
	}

	/// TOPICLEN is an octet count, so the topic is measured in UTF-8 bytes.
	var formattedTopicLength: Int {
		formattedTopic.utf8.count
	}

	/// What the sheet counts down, or `nil` where the server named no limit.
	/// Negative once the topic no longer fits, which is what disables the
	/// button and turns the footer into a warning.
	var remainingLength: Int? {
		maximumLength > 0 ? maximumLength - formattedTopicLength : nil
	}

	var fitsMaximumLength: Bool {
		(remainingLength ?? 0) >= 0
	}

	var topicForSubmission: String {
		formattedTopic.replacingOccurrences(of: "\n", with: " ")
	}
}
