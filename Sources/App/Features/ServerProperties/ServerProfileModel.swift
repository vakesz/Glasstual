// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Accessibility
import AppKit
import Combine
import Foundation
import Observation

/** The Profile pane: the name, picture and colour the user shows on one server.

 It edits live values. Update sends only the keys that changed, straight to
 the server and outside the sheet's Save; the server's reply is what the pane
 shows afterwards, because a server may store something other than what was
 typed. The session remembers the choice for this server either way. */
@MainActor
@Observable
final class ServerProfileModel {
	enum Availability: Equatable {
		case disconnected
		case unsupported
		case loading
		case ready
	}

	enum Field: Hashable, CaseIterable {
		case displayName
		case avatar
		case color

		var key: String {
			switch self {
			case .displayName: MetadataKey.displayName
			case .avatar: MetadataKey.avatar
			case .color: MetadataKey.color
			}
		}
	}

	/// Where one field's last update stands.
	enum FieldState: Equatable {
		case idle
		case sending
		case waiting(seconds: Int)
		case failed(String)
		/// Stored; `rewritten` when the server stored something else than sent.
		case updated(rewritten: Bool)
	}

	/// The display name a server accepts when it advertises no limit.
	static let defaultMaximumDisplayNameBytes = 256

	private(set) var availability = Availability.disconnected
	let networkName: String
	private(set) var nickname: String

	var displayName = ""
	var avatarURL = ""
	var usesColor = false
	var color = ProfileColor(red: 0x30, green: 0x70, blue: 0xC0)

	private(set) var fieldStates: [Field: FieldState] = [:]
	/// What the server holds, by key.
	private(set) var serverValues: [String: String] = [:]
	private(set) var maximumValueBytes: Int?
	private(set) var maximumKeys: Int?
	/// The field the latest failure concerns, for the view to focus.
	private(set) var focusRequest: Field?

	@ObservationIgnored private weak var session: ServerSession?
	@ObservationIgnored private let notifications = NotificationSubscriptions()
	@ObservationIgnored private var loginObservation: Task<Void, Never>?
	private var submission = SubmissionGate()

	init(session: ServerSession) {
		self.session = session
		networkName = session.name
		nickname = session.userNickname
		refresh(resettingEdits: true)

		notifications.observe(SessionProfilesDidChange.self, of: session) { [weak self] _ in
			self?.refresh(resettingEdits: false)
		}
		notifications.observe(SessionCapabilitiesDidChange.self, of: session) { [weak self] _ in
			self?.refresh(resettingEdits: false)
		}
		loginObservation = Task.immediate { [weak self, weak session] in
			guard let session else { return }
			for await _ in session.publisher(for: \.isLoggedIn).bufferedValues {
				self?.connectionDidChange()
			}
		}
	}

	isolated deinit {
		loginObservation?.cancel()
	}

	// MARK: - Edited values

	/// The wire value each field would send; `nil` removes the key.
	func editedValue(_ field: Field) -> String? {
		switch field {
		case .displayName:
			let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
			return trimmed.isEmpty ? nil : trimmed
		case .avatar:
			let trimmed = avatarURL.trimmingCharacters(in: .whitespacesAndNewlines)
			return trimmed.isEmpty ? nil : trimmed
		case .color:
			return usesColor ? color.hexString : nil
		}
	}

	/// The fields whose edited value differs from the server's.
	var changedFields: [Field] {
		Field.allCases.filter { field in
			normalized(editedValue(field), for: field) != normalized(serverValues[field.key], for: field)
		}
	}

	var hasChanges: Bool {
		changedFields.isEmpty == false
	}

	var canEdit: Bool {
		availability == .ready
	}

	/// What is wrong with a field, once updating was tried.
	func validationMessage(for field: Field) -> String? {
		if case let .failed(message) = fieldStates[field] {
			return message
		}

		return submission.shown(localProblem(for: field))
	}

	private func localProblem(for field: Field) -> String? {
		guard let value = editedValue(field) else { return nil }

		switch field {
		case .displayName:
			let maximum = maximumValueBytes ?? Self.defaultMaximumDisplayNameBytes
			if value.utf8.count > maximum {
				return String(localized: .ServerProperties.profileErrorTooLong(maximum))
			}
			if value.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }) {
				return String(localized: .ServerProperties.profileErrorControlCharacters)
			}
			if ProfileDisplayName(wireValue: value) == nil {
				return String(localized: .ServerProperties.profileErrorBlank)
			}
		case .avatar:
			let maximum = maximumValueBytes ?? ProfileAvatar.maximumWireBytes
			if value.utf8.count > maximum {
				return String(localized: .ServerProperties.profileErrorTooLong(maximum))
			}
			if ProfileAvatar(wireValue: value) == nil {
				return String(localized: .ServerProperties.profileErrorAddress)
			}
		case .color:
			break
		}

		return nil
	}

	// MARK: - Status

	/// The status beside the buttons, from every field's state.
	var statusText: String? {
		let states = Field.allCases.compactMap { fieldStates[$0] }

		if states.contains(.sending) {
			return String(localized: .ServerProperties.profileUpdating)
		}
		if let seconds = states.compactMap({
			if case let .waiting(seconds) = $0 {
				seconds
			} else {
				nil
			}
		}).max() {
			return String(localized: .ServerProperties.profileWaiting(seconds))
		}
		if states.contains(.updated(rewritten: true)) {
			return String(localized: .ServerProperties.profileUpdatedRewritten)
		}
		if states.contains(.updated(rewritten: false)) {
			return String(localized: .ServerProperties.profileUpdated)
		}

		return nil
	}

	var isUpdating: Bool {
		fieldStates.values.contains { state in
			switch state {
			case .sending, .waiting: true
			default: false
			}
		}
	}

	// MARK: - Actions

	/// Puts the server's values back in the fields.
	func revert() {
		submission.reset()
		fieldStates.removeAll()
		applyServerValues()
	}

	/// Sends the changed keys.
	func update() {
		submission.attempt()

		if let invalid = Field.allCases.first(where: { localProblem(for: $0) != nil }) {
			focusRequest = invalid
			announce(localProblem(for: invalid))
			return
		}

		guard let session else { return }

		for field in changedFields {
			let value = editedValue(field)
			fieldStates[field] = .sending
			session.setOwnMetadata(key: field.key, value: value) { [weak self] outcome in
				self?.receive(outcome, for: field, sent: value)
			}
		}
		announce(statusText)
	}

	/// Asks before removing every key from the server, through the session's
	/// own prompt. Cancel is the default and the Escape button.
	func confirmRemoval() {
		guard let session else { return }

		session.requestResponse(AlertRequest(
			title: String(localized: .ServerProperties.profileRemoveTitle(networkName)),
			body: String(localized: .ServerProperties.profileRemoveBody),
			defaultButton: PromptStrings.Action.cancel,
			alternateButton: String(localized: .ServerProperties.profileRemoveButton),
			destructiveButton: .alternate,
			cancelButton: .default,
			style: .warning
		)) { [weak self] session, response in
			guard response == .alternate else { return }
			self?.removeProfile(on: session)
		}
	}

	func removeProfile(on session: ServerSession) {
		for field in Field.allCases {
			fieldStates[field] = .sending
		}
		session.clearOwnMetadata { [weak self] failure in
			guard let self else { return }
			for field in Field.allCases {
				fieldStates[field] = failure.map { .failed($0.localizedDescription) } ?? .updated(rewritten: false)
			}
			refresh(resettingEdits: failure == nil)
			announce(failure?.localizedDescription ?? String(localized: .ServerProperties.profileRemoved))
		}
	}

	func didFocus() {
		focusRequest = nil
	}

	// MARK: - Session

	private func receive(_ outcome: MetadataSetOutcome, for field: Field, sent: String?) {
		switch outcome {
		case let .stored(value):
			serverValues[field.key] = value
			fieldStates[field] = .updated(rewritten: normalized(value, for: field) != normalized(sent, for: field))
			apply(value, to: field)
		case let .rateLimited(seconds):
			fieldStates[field] = .waiting(seconds: seconds)
		case let .failed(failure):
			fieldStates[field] = .failed(failure.localizedDescription)
			focusRequest = field
		}
		announce(validationMessage(for: field) ?? statusText)
	}

	private func connectionDidChange() {
		refresh(resettingEdits: false)
	}

	private func isWaiting(_ state: FieldState) -> Bool {
		if case .waiting = state {
			return true
		}

		return false
	}

	/// Reads the session again. `resettingEdits` replaces the fields with the
	/// server's values; otherwise only unedited fields follow them.
	private func refresh(resettingEdits: Bool) {
		guard let session else {
			availability = .disconnected
			return
		}

		nickname = session.userNickname
		maximumValueBytes = session.metadataValues.maximumValueBytes
		maximumKeys = session.metadataValues.maximumKeys

		if session.isLoggedIn == false {
			availability = .disconnected
		} else if session.isCapabilityEnabled(.metadata) == false {
			availability = .unsupported
		} else {
			availability = session.metadata.ownProfileLoaded ? .ready : .loading
		}

		/* A disconnect drops what was waiting to go; the fields keep the edits. */
		if availability != .ready {
			for (field, state) in fieldStates where state == .sending || isWaiting(state) {
				fieldStates[field] = .idle
			}
		}

		let previous = serverValues
		serverValues = session.metadata.ownWireValues.filter { MetadataKey.profileKeys.contains($0.key) }

		if resettingEdits {
			applyServerValues()
		} else {
			for field in Field.allCases where normalized(editedValue(field), for: field)
				== normalized(previous[field.key], for: field)
			{
				apply(serverValues[field.key], to: field)
			}
		}
	}

	private func applyServerValues() {
		for field in Field.allCases {
			apply(serverValues[field.key], to: field)
		}
	}

	private func apply(_ value: String?, to field: Field) {
		switch field {
		case .displayName:
			displayName = value ?? ""
		case .avatar:
			avatarURL = value ?? ""
		case .color:
			if let value, let parsed = ProfileColor(wireValue: value) {
				usesColor = true
				color = parsed
			} else {
				usesColor = false
			}
		}
	}

	/// Colours compare by value, whatever case or `#` the server used.
	private func normalized(_ value: String?, for field: Field) -> String? {
		guard let value else { return nil }

		return field == .color ? ProfileColor(wireValue: value)?.hexString ?? value : value
	}

	private func announce(_ text: String?) {
		guard let text, text.isEmpty == false else { return }
		AccessibilityNotification.Announcement(text).post()
	}
}
