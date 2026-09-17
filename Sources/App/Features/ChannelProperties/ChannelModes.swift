// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
import Observation
import SwiftUI

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

	var title: LocalizedStringResource {
		switch self {
		case .inviteOnly: .ChannelProperties.inviteOnlyMode
		case .moderated: .ChannelProperties.moderatedMode
		case .noExternalMessages: .ChannelProperties.noExternalMessagesMode
		case .privateChannel: .ChannelProperties.privateChannelMode
		case .secretChannel: .ChannelProperties.secretChannelMode
		case .operatorTopic: .ChannelProperties.operatorTopicMode
		case .key: .ChannelProperties.channelKeyMode
		case .userLimit: .ChannelProperties.userLimitMode
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

@MainActor
final class ChannelModesSheet: SheetSession, ChannelScoped {
	private(set) var client: Client?
	private(set) var channel: Channel?
	private(set) var clientId: String?
	private(set) var channelId: String?

	let model: ChannelModesModel

	/// The modes the person chose to set.
	private let onSubmitModes: (ChannelModeContainer) -> Void

	init(channel: Channel, onSubmitModes: @escaping (ChannelModeContainer) -> Void) {
		self.onSubmitModes = onSubmitModes
		guard let client = channel.associatedClient else {
			preconditionFailure("ChannelModesSheet requires an associated client")
		}

		self.client = client
		self.channel = channel
		clientId = client.uniqueIdentifier
		channelId = channel.uniqueIdentifier

		let sourceModes = channel.modeInfo?.modes ?? ChannelModeContainer(client: client)
		model = ChannelModesModel(
			copying: sourceModes,
			maximumKeyLength: client.supportInfo.maximumKeyLength
		)

		super.init(window: nil)
		setContent(ChannelModesView(
			model: model,
			channelName: channel.name,
			submit: { [weak self] in self?.submit() },
			cancel: { [weak self] in self?.cancel() }
		))
	}

	func start() {
		startSheet()
	}

	override func submit() {
		guard model.fitsMaximumKeyLength else { return }
		onSubmitModes(model.modesForSubmission())

		super.submit()
	}
}

/// The footer under the channel key field, which says how far past the
/// server's limit the key is; below the limit there is nothing to say.
extension ChannelModesModel {
	static func keyLengthWarning(remaining: Int) -> String? {
		remaining < 0
			? String(localized: .ChannelProperties.channelKeyCharactersOverLimit(arg1: -remaining))
			: nil
	}
}
