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

import CocoaExtensions
import Observation
import SwiftUI

@MainActor
public protocol ServerEndpointListSheetDelegate: AnyObject {
	func serverEndpointListSheet(_ sender: ServerEndpointListSheet, onOk serverList: [Server])
	func serverEndpointListSheetWillClose(_ sender: ServerEndpointListSheet)
}

@MainActor
public final class ServerEndpointListSheet: MainWindowSheetSession {
	let model = ServerEndpointListModel()

	override public init(window: MainWindow?) {
		super.init(window: window)
		installSheet()
	}

	private func installSheet() {
		let rootView = ServerEndpointListView(
			model: model,
			submit: { [weak self] in self?.ok(nil) },
			cancel: { [weak self] in self?.cancel(nil) }
		)
		setContent(rootView)
	}

	public func start(with serverList: [Server]) {
		model.replace(with: serverList)
		startSheet()
	}

	override public func ok(_ sender: Any?) {
		guard let servers = model.validatedServers() else {
			return
		}

		(delegate as? any ServerEndpointListSheetDelegate)?.serverEndpointListSheet(self, onOk: servers)
		super.ok(sender)
	}

	override public func sheetDidEnd(withReturnCode _: Int) {
		(delegate as? any ServerEndpointListSheetDelegate)?.serverEndpointListSheetWillClose(self)
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

	init(server: Server) {
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

	func validatedServer() throws -> Server {
		try Server(
			uniqueIdentifier: id,
			serverAddress: ServerEndpointValidation.validatedAddress(address),
			serverPort: ServerEndpointValidation.validatedPort(port),
			prefersSecuredConnection: prefersSecuredConnection,
			pendingServerPassword: passwordWasEdited ? .edited(password) : storedPassword
		)
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

	func replace(with servers: [Server]) {
		entries = servers.map(ServerEndpointDraft.init)
		selectedID = nil
		clearValidation()
		loadPasswords(for: servers)
	}

	/// One keychain read for the whole list, off the main actor, instead of one
	/// synchronous read per endpoint while the sheet is being built.
	private func loadPasswords(for servers: [Server]) {
		passwordsTask?.cancel()
		passwordsTask = Task { [weak self] in
			let passwords = await KeychainSecretLoader.passwords(for: servers.map(\.keychainItem))
			self?.applyLoadedPasswords(passwords, for: servers)
		}
	}

	private func applyLoadedPasswords(_ passwords: [KeychainItem: String], for servers: [Server]) {
		guard Task.isCancelled == false else { return }

		for server in servers {
			/* A field the person has already typed into keeps what they typed —
			 an emptied one included, which is why this asks what was edited
			 rather than what is empty. */
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
		let entry = ServerEndpointDraft(server: Server())
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

	func removeEntries(at offsets: IndexSet) {
		let removedIDs = offsets.compactMap { entries.indices.contains($0) ? entries[$0].id : nil }
		entries.remove(atOffsets: offsets)
		invalidAddressIDs.subtract(removedIDs)
		invalidPortIDs.subtract(removedIDs)
		if let selectedID, removedIDs.contains(selectedID) {
			self.selectedID = nil
		}
	}

	func moveEntries(from offsets: IndexSet, to destination: Int) {
		entries.move(fromOffsets: offsets, toOffset: destination)
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
		var server = Server(
			uniqueIdentifier: entries[index].id,
			serverAddress: entries[index].address,
			serverPort: UInt16(entries[index].port) ?? ServerEndpointValidation.plainTextPort,
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

	func validatedServers() -> [Server]? {
		clearValidation()
		var servers: [Server] = []

		/* An empty address is an invalid address, not a row to drop: silently
		 discarding it loses whatever else the user typed into it. */
		for entry in entries {
			do {
				try servers.append(entry.validatedServer())
			} catch let error as NSError where error.code == ServerEndpointValidation.invalidAddressCode {
				invalidAddressIDs.insert(entry.id)
			} catch {
				invalidPortIDs.insert(entry.id)
			}
		}

		return invalidAddressIDs.isEmpty && invalidPortIDs.isEmpty ? servers : nil
	}

	private func clearValidation() {
		invalidAddressIDs = []
		invalidPortIDs = []
	}
}
