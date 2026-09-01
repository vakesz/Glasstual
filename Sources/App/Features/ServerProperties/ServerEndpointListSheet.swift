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

import AppKit
import Observation
import SwiftUI

@MainActor
public protocol ServerEndpointListSheetDelegate: AnyObject {
	func serverEndpointListSheet(_ sender: ServerEndpointListSheet, onOk serverList: [Server])
	func serverEndpointListSheetWillClose(_ sender: ServerEndpointListSheet)
}

@MainActor
public final class ServerEndpointListSheet: SheetBase, NSWindowDelegate {
	private static let contentSize = NSSize(width: 780, height: 440)

	let model = ServerEndpointListModel()

	override public init(window: NSWindow?) {
		super.init(window: window)
		installSheet()
	}

	private func installSheet() {
		let rootView = ServerEndpointListView(
			model: model,
			submit: { [weak self] in self?.ok(nil) },
			cancel: { [weak self] in self?.cancel(nil) }
		)
		let hostedSheet = NSWindow(
			contentRect: NSRect(origin: .zero, size: Self.contentSize),
			styleMask: [.titled, .resizable, .fullSizeContentView],
			backing: .buffered,
			defer: false
		)

		hostedSheet.contentViewController = NSHostingController(rootView: rootView)
		hostedSheet.contentMinSize = NSSize(width: 680, height: 360)
		hostedSheet.delegate = self
		hostedSheet.isReleasedWhenClosed = false
		hostedSheet.isRestorable = false
		hostedSheet.tabbingMode = .disallowed
		hostedSheet.preventsApplicationTerminationWhenModal = false
		hostedSheet.autorecalculatesKeyViewLoop = true
		hostedSheet.title = ServerEndpointStrings.windowTitle
		sheet = hostedSheet
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

	public func windowWillClose(_: Notification) {
		(delegate as? any ServerEndpointListSheetDelegate)?.serverEndpointListSheetWillClose(self)
	}
}

struct ServerEndpointDraft: Identifiable, Equatable {
	let id: String
	var address: String
	var port: String
	var prefersSecuredConnection: Bool
	var password: String

	init(server: Server) {
		id = server.uniqueIdentifier
		address = server.serverAddress
		port = String(server.serverPort)
		prefersSecuredConnection = server.prefersSecuredConnection
		password = server.serverPassword ?? ""
	}

	func validatedServer() throws -> Server {
		try Server(
			uniqueIdentifier: id,
			serverAddress: ServerEndpointValidation.validatedAddress(address),
			serverPort: ServerEndpointValidation.validatedPort(port),
			prefersSecuredConnection: prefersSecuredConnection,
			pendingServerPassword: password
		)
	}
}

@Observable
final class ServerEndpointListModel {
	var entries: [ServerEndpointDraft] = []
	var selectedID: String?
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
		var server = Server(
			uniqueIdentifier: entries[index].id,
			serverAddress: entries[index].address,
			serverPort: UInt16(entries[index].port) ?? ServerEndpointValidation.plainTextPort,
			prefersSecuredConnection: entries[index].prefersSecuredConnection,
			pendingServerPassword: entries[index].password
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

		for entry in entries where entry.address.isEmpty == false {
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
