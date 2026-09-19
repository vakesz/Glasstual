// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
import Observation
import SwiftUI

@MainActor
final class ServerEndpointListSheet: SheetSession {
	let model = ServerEndpointListModel()

	/// The endpoints the person accepted.
	private let onSave: ([ServerEndpoint]) -> Void

	init(window: MainWindow?, onSave: @escaping ([ServerEndpoint]) -> Void) {
		self.onSave = onSave
		super.init(window: window)
		installSheet()
	}

	private func installSheet() {
		let rootView = ServerEndpointListView(
			model: model,
			submit: { [weak self] in self?.submit() },
			cancel: { [weak self] in self?.cancel() }
		)
		setContent(rootView)
	}

	func start(with serverList: [ServerEndpoint]) {
		model.replace(with: serverList)
		startSheet()
	}

	override func submit() {
		guard let servers = model.validatedServers() else {
			return
		}

		onSave(servers)
		super.submit()
	}
}

struct ServerEndpointDraft: Identifiable, Equatable {
	let id: String
	var address: String
	var port: String
	var prefersSecuredConnection: Bool

	/// Typing into the field is what turns the draft's secret into an
	/// instruction for the keychain; see ``passwordWasEdited``.
	var password: String {
		didSet {
			guard password != oldValue else { return }
			passwordWasEdited = true
		}
	}

	/** Whether the person typed into the password field.

	 The stored secret arrives after the sheet is on screen, so a draft that
	 nobody has touched is showing an empty field for a secret that may well
	 exist. Submitting that field as an edit is what deleted it, which is why an
	 untouched draft hands back the edit its endpoint already carried. */
	private(set) var passwordWasEdited = false

	private let storedPassword: PendingKeychainSecret

	init(server: ServerEndpoint) {
		id = server.uniqueIdentifier
		address = server.serverAddress
		port = String(server.serverPort)
		prefersSecuredConnection = server.prefersSecuredConnection
		/* Only an unflushed edit: reading the stored one is a synchronous
		 keychain lookup, and a draft is built for every endpoint in the list.
		 `ServerEndpointListModel` fills the rest in off the main actor. */
		storedPassword = server.pendingServerPassword
		password = server.pendingServerPassword.value(orStored: nil) ?? ""
	}

	/// Shows what the one keychain read found, leaving the draft untouched as
	/// far as submission is concerned.
	mutating func showStoredPassword(_ stored: String?) {
		password = storedPassword.value(orStored: stored) ?? ""
		passwordWasEdited = false
	}

	func validatedServer() -> Result<ServerEndpoint, ServerEndpointFault> {
		guard let address = ServerEndpointValidation.validatedAddress(address) else {
			return .failure(.address)
		}
		guard let port = ServerEndpointValidation.validatedPort(port) else {
			return .failure(.port)
		}

		return .success(ServerEndpoint(
			uniqueIdentifier: id,
			serverAddress: address,
			serverPort: port,
			prefersSecuredConnection: prefersSecuredConnection,
			pendingServerPassword: passwordWasEdited ? .edited(password) : storedPassword
		))
	}
}

@Observable
final class ServerEndpointListModel {
	var entries: [ServerEndpointDraft] = []
	var selectedID: String?
	@ObservationIgnored private var passwordsTask: Task<Void, Never>?
	private(set) var invalidAddressIDs: Set<String> = []
	private(set) var invalidPortIDs: Set<String> = []

	var canMoveSelectionUp: Bool {
		guard let selectedIndex else { return false }
		return selectedIndex > entries.startIndex
	}

	var canMoveSelectionDown: Bool {
		guard let selectedIndex else { return false }
		return selectedIndex < entries.index(before: entries.endIndex)
	}

	private var selectedIndex: Int? {
		guard let selectedID else { return nil }
		return entries.firstIndex { $0.id == selectedID }
	}

	func replace(with servers: [ServerEndpoint]) {
		entries = servers.map(ServerEndpointDraft.init)
		selectedID = nil
		clearValidation()
		loadPasswords(for: servers)
	}

	/// One keychain read for the whole list, off the main actor, instead of one
	/// synchronous read per endpoint while the sheet is being built.
	private func loadPasswords(for servers: [ServerEndpoint]) {
		passwordsTask?.cancel()
		passwordsTask = Task { [weak self] in
			let passwords = await KeychainSecretLoader.passwords(for: servers.map(\.keychainItem))
			self?.applyLoadedPasswords(passwords, for: servers)
		}
	}

	private func applyLoadedPasswords(_ passwords: [KeychainItem: String], for servers: [ServerEndpoint]) {
		guard Task.isCancelled == false else { return }

		for server in servers {
			// See `ServerEndpointDraft.passwordWasEdited`: an emptied field is
			// an edit too, so this asks what was typed into, not what is empty.
			guard let index = entries.firstIndex(where: { $0.id == server.uniqueIdentifier }),
			      entries[index].passwordWasEdited == false
			else { continue }

			entries[index].showStoredPassword(passwords[server.keychainItem])
		}
	}

	isolated deinit {
		passwordsTask?.cancel()
	}

	func addEntry() {
		let entry = ServerEndpointDraft(server: ServerEndpoint())
		entries.append(entry)
		selectedID = entry.id
	}

	func removeSelection() {
		guard let selectedID else { return }
		entries.removeAll { $0.id == selectedID }
		invalidAddressIDs.remove(selectedID)
		invalidPortIDs.remove(selectedID)
		self.selectedID = nil
	}

	func moveEntries(from offsets: IndexSet, to destination: Int) {
		entries.move(fromOffsets: offsets, toOffset: destination)
	}

	/// The rows a drag carried, put back down at `destination`. A drop that
	/// names nothing this list holds — text dragged in from elsewhere — moves
	/// nothing.
	func moveEntries(identifiedBy identifiers: [String], to destination: Int) {
		let offsets = IndexSet(identifiers.compactMap { identifier in
			entries.firstIndex { $0.id == identifier }
		})
		guard offsets.isEmpty == false else { return }
		moveEntries(from: offsets, to: destination)
	}

	/// The address of one endpoint, by identity: a table column hands back the
	/// row's value rather than a binding into the list it came from.
	func address(for entryID: String) -> Binding<String> {
		binding(for: entryID, \.address) { $0.addressDidChange(for: entryID) }
	}

	func port(for entryID: String) -> Binding<String> {
		binding(for: entryID, \.port) { $0.portDidChange(for: entryID) }
	}

	func password(for entryID: String) -> Binding<String> {
		binding(for: entryID, \.password) { _ in }
	}

	func isSecured(for entryID: String) -> Binding<Bool> {
		Binding(
			get: { [weak self] in
				self?.entries.first { $0.id == entryID }?.prefersSecuredConnection ?? false
			},
			set: { [weak self] secured in self?.setSecured(secured, for: entryID) }
		)
	}

	private func binding(
		for entryID: String,
		_ keyPath: WritableKeyPath<ServerEndpointDraft, String>,
		didChange: @escaping (ServerEndpointListModel) -> Void
	) -> Binding<String> {
		Binding(
			get: { [weak self] in self?.entries.first { $0.id == entryID }?[keyPath: keyPath] ?? "" },
			set: { [weak self] value in
				guard let self, let index = entries.firstIndex(where: { $0.id == entryID }) else { return }
				entries[index][keyPath: keyPath] = value
				didChange(self)
			}
		)
	}

	func moveSelection(by offset: Int) {
		guard let selectedIndex else { return }
		let destination = selectedIndex + offset
		guard entries.indices.contains(destination) else { return }
		entries.swapAt(selectedIndex, destination)
	}

	func setSecured(_ secured: Bool, for entryID: String) {
		guard let index = entries.firstIndex(where: { $0.id == entryID }) else { return }
		// Only the port and the flag come back out, so the secret plays no part.
		var server = ServerEndpoint(
			uniqueIdentifier: entries[index].id,
			serverAddress: entries[index].address,
			serverPort: UInt16(entries[index].port) ?? ConnectionDefaults.serverPort,
			prefersSecuredConnection: entries[index].prefersSecuredConnection,
			pendingServerPassword: .unchanged
		)
		server = ServerEndpointValidation.server(server, preferringSecuredConnection: secured)
		entries[index].prefersSecuredConnection = server.prefersSecuredConnection
		entries[index].port = String(server.serverPort)
		invalidPortIDs.remove(entryID)
	}

	func addressDidChange(for entryID: String) {
		invalidAddressIDs.remove(entryID)
	}

	func portDidChange(for entryID: String) {
		invalidPortIDs.remove(entryID)
	}

	/// The faults the last validation found, in the order the sheet shows them
	/// under the table. One message per kind, because a list that repeats
	/// "enter a server address" once per row says nothing extra.
	var faults: [ServerEndpointFault] {
		var faults: [ServerEndpointFault] = []
		if invalidAddressIDs.isEmpty == false {
			faults.append(.address)
		}
		if invalidPortIDs.isEmpty == false {
			faults.append(.port)
		}

		return faults
	}

	func validatedServers() -> [ServerEndpoint]? {
		clearValidation()
		var servers: [ServerEndpoint] = []

		/* An empty address is an invalid address, not a row to drop: silently
		 discarding it loses whatever else the user typed into it. */
		for entry in entries {
			switch entry.validatedServer() {
			case let .success(server):
				servers.append(server)
			case .failure(.address):
				invalidAddressIDs.insert(entry.id)
			case .failure(.port):
				invalidPortIDs.insert(entry.id)
			}
		}

		guard invalidAddressIDs.isEmpty, invalidPortIDs.isEmpty else {
			// Selecting the first refused row is what points at the message.
			selectedID = entries.first { invalidAddressIDs.contains($0.id) || invalidPortIDs.contains($0.id) }?.id
			return nil
		}

		return servers
	}

	private func clearValidation() {
		invalidAddressIDs = []
		invalidPortIDs = []
	}
}

/// Why an endpoint the person typed cannot become a `ServerEndpoint`. The sheet shows
/// one message per kind of fault, which is all a caller ever did with the
/// `NSError`s this used to throw: nobody read their domain, code, description
/// or recovery suggestion.
nonisolated enum ServerEndpointFault: Error, Hashable {
	case address
	case port

	var message: LocalizedStringResource {
		switch self {
		case .address: .ServerProperties.valueYouEnteredIsNot
		case .port: .ServerProperties.enterAWholeNumberBetween1
		}
	}
}

nonisolated enum ServerEndpointValidation {
	/// The address, or `nil` when it is not one. An empty address is not one
	/// either: a row nobody typed a host into cannot be connected to.
	static func validatedAddress(_ address: String) -> String? {
		address.isValidInternetAddress ? address : nil
	}

	static func validatedPort(_ port: String) -> UInt16? {
		guard port.isValidInternetPort else { return nil }

		return UInt16(port)
	}

	/** Moves the port with the switch, but only where it is still the default
	 for the other kind: a port the person chose is theirs to keep. */
	static func server(_ server: ServerEndpoint, preferringSecuredConnection prefers: Bool) -> ServerEndpoint {
		var updated = server
		updated.prefersSecuredConnection = prefers

		if prefers, server.serverPort == ConnectionDefaults.serverPort {
			updated.serverPort = ConnectionDefaults.serverPortSecure
		} else if prefers == false, server.serverPort == ConnectionDefaults.serverPortSecure {
			updated.serverPort = ConnectionDefaults.serverPort
		}

		return updated
	}
}
