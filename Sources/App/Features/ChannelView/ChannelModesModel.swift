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

/// Channel modes edited by the channel-modes feature.
///
/// IRC mode letters are a wire-format boundary. Keeping that mapping here
/// prevents view and presentation code from passing unvalidated magic strings.
enum ChannelMode: String, CaseIterable, Sendable {
	case inviteOnly = "i"
	case moderated = "m"
	case noExternalMessages = "n"
	case privateChannel = "p"
	case secretChannel = "s"
	case operatorTopic = "t"
	case key = "k"
	case userLimit = "l"

	static let booleanModes: [Self] = [
		.secretChannel,
		.privateChannel,
		.noExternalMessages,
		.operatorTopic,
		.inviteOnly,
		.moderated,
	]

	var title: String {
		switch self {
		case .inviteOnly: ChannelModesStrings.inviteOnlyModeTitle
		case .moderated: ChannelModesStrings.moderatedModeTitle
		case .noExternalMessages: ChannelModesStrings.noExternalMessagesModeTitle
		case .privateChannel: ChannelModesStrings.privateChannelModeTitle
		case .secretChannel: ChannelModesStrings.secretChannelModeTitle
		case .operatorTopic: ChannelModesStrings.operatorTopicModeTitle
		case .key: ChannelModesStrings.channelKeyModeTitle
		case .userLimit: ChannelModesStrings.userLimitModeTitle
		}
	}
}

@MainActor
@Observable
final class ChannelModesModel {
	static let maximumUserLimit = 99999

	private let workingModes: ChannelModeContainer
	private var enabledModes: Set<ChannelMode>

	private(set) var secretKey: String
	private(set) var userLimit: String

	let maximumKeyLength: Int

	init(copying modes: ChannelModeContainer, maximumKeyLength: UInt) {
		guard let copiedModes = modes.copy() as? ChannelModeContainer else {
			preconditionFailure("Channel mode copies must preserve their model type")
		}

		workingModes = copiedModes
		self.maximumKeyLength = Int(clamping: maximumKeyLength)
		enabledModes = Set(
			ChannelMode.allCases.filter { mode in
				copiedModes.modeInfo(for: mode.rawValue)?.modeIsSet == true
			}
		)
		secretKey = copiedModes.modeInfo(for: ChannelMode.key.rawValue)?.modeParameter ?? ""
		userLimit = copiedModes.modeInfo(for: ChannelMode.userLimit.rawValue)?.modeParameter ?? ""
	}

	func isEnabled(_ mode: ChannelMode) -> Bool {
		enabledModes.contains(mode)
	}

	func setMode(_ mode: ChannelMode, enabled: Bool) {
		if enabled {
			enabledModes.insert(mode)

			// A server can report both historic visibility modes at once, so
			// initialization preserves that state. The first user interaction
			// with either mode restores the mutually exclusive editing policy.
			switch mode {
			case .secretChannel:
				enabledModes.remove(.privateChannel)
			case .privateChannel:
				enabledModes.remove(.secretChannel)
			default:
				break
			}
		} else {
			enabledModes.remove(mode)
		}
	}

	func updateSecretKey(_ secretKey: String) {
		self.secretKey = secretKey
	}

	/// How many octets of key the server still has room for, or `nil` where it
	/// named no limit. KEYLEN is an octet count, so the key is measured in
	/// UTF-8 bytes. Negative once the key no longer fits, which is what
	/// disables the button and turns the footer into a warning.
	var remainingKeyLength: Int? {
		maximumKeyLength > 0 ? maximumKeyLength - secretKey.utf8.count : nil
	}

	var fitsMaximumKeyLength: Bool {
		(remainingKeyLength ?? 0) >= 0
	}

	func updateUserLimit(_ userLimit: String) {
		let trimmed = userLimit.trimmingCharacters(in: .whitespaces)

		/* An empty field means "no limit" and has to stay empty; coercing it
		 to 0 made the text snap back the moment the user cleared it. */
		guard trimmed.isEmpty == false else {
			self.userLimit = ""
			return
		}

		/* Junk is rejected rather than silently turned into 0: leaving the
		 property alone makes the field revert to its last valid value. */
		guard let numericLimit = Int(trimmed) else {
			return
		}

		self.userLimit = String(min(max(numericLimit, 0), Self.maximumUserLimit))
	}

	func modesForSubmission() -> ChannelModeContainer {
		for mode in ChannelMode.allCases {
			let parameter: String? = switch mode {
			case .key:
				secretKey
			case .userLimit:
				userLimit
			default:
				nil
			}

			workingModes.changeMode(
				mode.rawValue,
				modeIsSet: isEnabled(mode),
				modeParameter: parameter
			)
		}

		return workingModes
	}
}
