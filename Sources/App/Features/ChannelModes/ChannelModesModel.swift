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
final class ChannelModesModel {
	static let maximumUserLimit = 99999

	private let workingModes: ChannelModeContainer
	private var enabledModes: Set<ChannelMode>

	private(set) var secretKey: String
	private(set) var userLimit: String
	private(set) var hasPresentedMaximumKeyLengthWarning = false

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

	@discardableResult
	func updateSecretKey(_ secretKey: String) -> Bool {
		self.secretKey = secretKey

		guard maximumKeyLength > 0,
		      secretKey.count > maximumKeyLength,
		      hasPresentedMaximumKeyLengthWarning == false
		else {
			return false
		}

		hasPresentedMaximumKeyLengthWarning = true
		return true
	}

	func updateUserLimit(_ userLimit: String) {
		let numericLimit = Int(userLimit) ?? 0
		let clampedLimit = min(max(numericLimit, 0), Self.maximumUserLimit)
		self.userLimit = String(clampedLimit)
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
