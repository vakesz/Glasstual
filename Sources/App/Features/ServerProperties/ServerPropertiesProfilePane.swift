// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import SwiftUI

/// The Profile pane: what the user shows on this server beside their nickname.
struct ServerPropertiesProfilePane: View {
	@Bindable var profile: ServerProfileModel

	@FocusState private var focusedField: ServerProfileModel.Field?

	var body: some View {
		Form {
			if profile.availability != .ready {
				Section {
					statusRow
				}
			}

			Section {
				headerRow

				LabeledContent(.ServerProperties.profileDisplayNameLabel) {
					TextField(.ServerProperties.profileDisplayNamePlaceholder, text: $profile.displayName)
						.labelsHidden()
						.focused($focusedField, equals: .displayName)
						.accessibilityLabel(.ServerProperties.profileDisplayNameLabel)
						.accessibilityIdentifier(AccessibilityIdentifier.serverProfileDisplayName)
				}
				fieldError(.displayName, identifier: "server-profile-error-display-name")

				LabeledContent(.ServerProperties.profilePictureLabel) {
					TextField(.ServerProperties.profilePicturePlaceholder, text: $profile.avatarURL)
						.labelsHidden()
						.textContentType(.URL)
						.focused($focusedField, equals: .avatar)
						.accessibilityLabel(.ServerProperties.profilePictureLabel)
						.accessibilityIdentifier("server-profile-avatar-url")
				}
				fieldError(.avatar, identifier: "server-profile-error-avatar-url")

				Toggle(.ServerProperties.profileColorToggle, isOn: $profile.usesColor)
					.focused($focusedField, equals: .color)
					.accessibilityIdentifier("server-profile-color-enabled")
				LabeledContent(.ServerProperties.profileColorLabel) {
					HStack(spacing: UISpacing.regular) {
						Text(profile.color.hexString)
							.monospaced()
							.foregroundStyle(.secondary)
							.textSelection(.enabled)
							.accessibilityIdentifier("server-profile-color-hex")
						ColorPicker(String(localized: .ServerProperties.profileColorLabel), selection: colorBinding, supportsOpacity: false)
							.labelsHidden()
							.accessibilityValue(Text(profile.color.hexString))
							.accessibilityIdentifier("server-profile-color")
					}
				}
				.disabled(profile.usesColor == false)
				fieldError(.color, identifier: "server-profile-error-color")

				actionRow
			} header: {
				Text(.ServerProperties.profileSection)
			} footer: {
				Text(.ServerProperties.profileFootnote)
			}
			.disabled(profile.canEdit == false)

			Section {
				Button(.ServerProperties.profileRemove, role: .destructive) {
					profile.confirmRemoval()
				}
				.buttonStyle(.bordered)
				.disabled(profile.canEdit == false || profile.isUpdating || profile.serverValues.isEmpty)
				.accessibilityIdentifier(AccessibilityIdentifier.serverProfileClear)
			}
		}
		.formStyle(.grouped)
		.onChange(of: profile.focusRequest) { _, field in
			guard let field else { return }
			focusedField = field
			profile.didFocus()
		}
	}

	private var statusRow: some View {
		HStack(spacing: UISpacing.regular) {
			switch profile.availability {
			case .loading:
				ProgressView()
					.controlSize(.small)
				Text(.ServerProperties.profileLoading)
			case .unsupported:
				Label(
					String(localized: .ServerProperties.profileUnsupported(profile.networkName)),
					systemImage: "person.crop.circle.badge.xmark"
				)
			case .disconnected, .ready:
				Label(String(localized: .ServerProperties.profileDisconnected(profile.networkName)), systemImage: "bolt.slash")
			}
		}
		.foregroundStyle(.secondary)
		.frame(maxWidth: .infinity, alignment: .center)
		.accessibilityElement(children: .combine)
		.accessibilityIdentifier("server-profile-status")
	}

	private var headerRow: some View {
		HStack(spacing: UISpacing.wide) {
			MemberAvatar(
				nickname: profile.nickname,
				size: MemberListLayout.profileAvatarSize,
				profileColor: profile.usesColor ? profile.color : nil
			)
			.accessibilityHidden(true)
			VStack(alignment: .leading, spacing: 2) {
				Text(profile.editedValue(.displayName).map(TranscriptIsolate.isolated) ?? profile.nickname)
					.font(.headline)
					.lineLimit(1)
				Text(.ServerProperties.profileAlongsideNickname(profile.nickname))
					.font(.callout)
					.foregroundStyle(.secondary)
			}
		}
	}

	private var actionRow: some View {
		HStack(spacing: UISpacing.regular) {
			if let status = profile.statusText {
				if profile.isUpdating {
					ProgressView()
						.controlSize(.small)
				}
				Text(status)
					.foregroundStyle(.secondary)
					.accessibilityIdentifier("server-profile-progress")
			}
			Spacer()
			Button(.ServerProperties.profileRevert) {
				profile.revert()
			}
			.buttonStyle(.bordered)
			.disabled(profile.hasChanges == false)
			.accessibilityIdentifier("server-profile-revert")
			Button(.ServerProperties.profileUpdate) {
				profile.update()
			}
			.buttonStyle(.bordered)
			.disabled(profile.hasChanges == false || profile.isUpdating)
			.accessibilityIdentifier(AccessibilityIdentifier.serverProfileUpdate)
		}
	}

	@ViewBuilder
	private func fieldError(_ field: ServerProfileModel.Field, identifier: String) -> some View {
		if let message = profile.validationMessage(for: field) {
			ValidationMessageLabel(message)
				.accessibilityIdentifier(identifier)
		}
	}

	private var colorBinding: Binding<Color> {
		Binding {
			Color(nsColor: NSColor(
				srgbRed: CGFloat(profile.color.red) / 255,
				green: CGFloat(profile.color.green) / 255,
				blue: CGFloat(profile.color.blue) / 255,
				alpha: 1
			))
		} set: { color in
			guard let srgb = NSColor(color).usingColorSpace(.sRGB) else { return }
			profile.color = ProfileColor(
				red: UInt8((srgb.redComponent * 255).rounded().clamped(to: 0 ... 255)),
				green: UInt8((srgb.greenComponent * 255).rounded().clamped(to: 0 ... 255)),
				blue: UInt8((srgb.blueComponent * 255).rounded().clamped(to: 0 ... 255))
			)
		}
	}
}

private extension CGFloat {
	func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
		Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
	}
}
