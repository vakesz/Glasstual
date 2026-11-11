// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import SwiftUI

/// What the Known Certificates sheet lists: this user's certificate on each
/// network, and the certificates trusted for other people.
@MainActor
@Observable
final class DCCKnownCertificatesModel {
	struct Network: Equatable {
		let id: String
		let name: String
	}

	struct OwnCertificate: Identifiable, Equatable {
		let network: Network
		var fingerprint: DCCCertificateFingerprint?

		var id: String {
			network.id
		}
	}

	struct TrustedCertificate: Identifiable, Hashable {
		let network: String
		let networkName: String
		/// The key the store files the pin under.
		let nicknameKey: String
		let nickname: String
		let fingerprint: DCCCertificateFingerprint
		let firstTrusted: Date
		let lastSeen: Date

		var id: String {
			"\(network)\u{1F}\(nicknameKey)\u{1F}\(fingerprint.formatted)"
		}
	}

	private(set) var own: [OwnCertificate] = []
	private(set) var trusted: [TrustedCertificate] = []
	var selection: Set<TrustedCertificate.ID> = []
	var searchText = ""
	var failure: String?
	/// The network whose certificate the user asked to replace, while the
	/// confirmation is up.
	var pendingReplacement: OwnCertificate?
	var confirmsRemoveAll = false

	private let networks: [Network]
	private let identities: DCCLocalIdentityStore
	private let pins: DCCPeerCertificateStore

	init(networks: [Network], identities: DCCLocalIdentityStore, pins: DCCPeerCertificateStore) {
		self.networks = networks
		self.identities = identities
		self.pins = pins
	}

	/// The application's networks and stores.
	static func application() -> DCCKnownCertificatesModel {
		let networks = (AppServices.chatSession?.sessions ?? []).map {
			Network(id: $0.config.uniqueIdentifier, name: $0.config.connectionName)
		}
		return DCCKnownCertificatesModel(networks: networks, identities: .shared, pins: .shared)
	}

	var visibleTrusted: [TrustedCertificate] {
		let query = searchText.trimmingCharacters(in: .whitespaces)
		guard query.isEmpty == false else { return trusted }
		return trusted.filter {
			$0.nickname.localizedCaseInsensitiveContains(query)
				|| $0.networkName.localizedCaseInsensitiveContains(query)
				|| $0.fingerprint.formatted.localizedCaseInsensitiveContains(query)
		}
	}

	func load() async {
		var own: [OwnCertificate] = []
		for network in networks {
			let identity = try? await identities.existingIdentity(forNetwork: network.id)
			own.append(OwnCertificate(network: network, fingerprint: identity?.fingerprint))
		}
		self.own = own

		let names = Dictionary(networks.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
		trusted = await pins.all().flatMap { network, nicknames in
			nicknames.flatMap { key, pins in
				pins.map {
					TrustedCertificate(
						network: network, networkName: names[network] ?? network, nicknameKey: key,
						nickname: $0.nickname, fingerprint: $0.fingerprint,
						firstTrusted: $0.firstTrusted, lastSeen: $0.lastSeen
					)
				}
			}
		}
		.sorted { ($0.networkName, $0.nickname.lowercased()) < ($1.networkName, $1.nickname.lowercased()) }
		selection.formIntersection(trusted.map(\.id))
	}

	func copy(_ fingerprint: DCCCertificateFingerprint) {
		NSPasteboard.general.clearContents()
		NSPasteboard.general.setString(fingerprint.formatted, forType: .string)
	}

	func replaceCertificate(of certificate: OwnCertificate) async {
		await perform { _ = try await identities.regenerate(forNetwork: certificate.network.id) }
	}

	func removeSelected() async {
		let removed = trusted.filter { selection.contains($0.id) }
		await perform {
			for certificate in removed {
				try await pins.remove(certificate.fingerprint, network: certificate.network, nicknameKey: certificate.nicknameKey)
			}
		}
	}

	func removeAll() async {
		await perform { try await pins.forgetAll() }
	}

	private func perform(_ change: () async throws -> Void) async {
		do {
			try await change()
		} catch {
			failure = String(localized: .Settings.knownCertificatesChangeFailed(error.localizedDescription))
		}
		await load()
	}
}

/** The sheet Settings ▸ File Transfers opens from Known Certificates….

 This user's own certificates come first, because their fingerprints are what
 the other person reads back; the people this user trusts follow in a table
 that can be searched and pruned. */
struct DCCKnownCertificatesSheet: View {
	@State var model: DCCKnownCertificatesModel
	@Environment(\.dismiss) private var dismiss

	var body: some View {
		NavigationStack {
			VStack(alignment: .leading, spacing: UISpacing.comfortable) {
				ownCertificates
				Text(.Settings.knownCertificatesTrusted)
					.font(.headline)
				trustedTable
			}
			.padding(UISpacing.wide)
			.navigationTitle(Text(.Settings.knownCertificatesTitle))
			.searchable(text: $model.searchText)
			.toolbar {
				ToolbarItem(placement: .confirmationAction) {
					Button(.Settings.knownCertificatesDone) { dismiss() }
						.keyboardShortcut(.defaultAction)
						.accessibilityIdentifier("known-certificates-done")
				}
			}
		}
		.frame(minWidth: 680, minHeight: 520)
		.task { await model.load() }
		.alert(
			Text(verbatim: model.failure ?? ""),
			isPresented: Binding(get: { model.failure != nil }, set: {
				if $0 == false {
					model.failure = nil
				}
			})
		) {
			Button(PromptStrings.Action.confirmation) { model.failure = nil }
		}
	}

	private var ownCertificates: some View {
		GroupBox {
			VStack(alignment: .leading, spacing: UISpacing.comfortable) {
				ForEach(model.own) { certificate in
					LabeledContent {
						ownCertificateActions(certificate)
					} label: {
						Text(verbatim: certificate.network.name)
						if let fingerprint = certificate.fingerprint {
							Text(verbatim: fingerprint.grouped.joined(separator: "\n"))
								.font(.caption.monospaced())
								.textSelection(.enabled)
						} else {
							Text(.Settings.knownCertificatesNotCreated)
						}
					}
				}
				SettingsNote(.Settings.knownCertificatesYourCertificatesNote)
			}
			.padding(UISpacing.tight)
		} label: {
			Text(.Settings.knownCertificatesYourCertificates)
		}
		.confirmationDialog(
			Text(.Settings.knownCertificatesCreateNewConfirmationTitle(model.pendingReplacement?.network.name ?? "")),
			isPresented: Binding(
				get: { model.pendingReplacement != nil },
				set: {
					if $0 == false {
						model.pendingReplacement = nil
					}
				}
			),
			presenting: model.pendingReplacement
		) { certificate in
			Button(.Settings.knownCertificatesCreateNewAction, role: .destructive) {
				Task { await model.replaceCertificate(of: certificate) }
			}
			Button(PromptStrings.Action.cancel, role: .cancel) {}
		} message: { _ in
			Text(.Settings.knownCertificatesCreateNewConfirmationBody)
		}
	}

	private func ownCertificateActions(_ certificate: DCCKnownCertificatesModel.OwnCertificate) -> some View {
		HStack {
			if let fingerprint = certificate.fingerprint {
				Button(.Settings.knownCertificatesCopyFingerprint) { model.copy(fingerprint) }
					.accessibilityIdentifier("known-certificates-copy-\(certificate.id)")
				Button(.Settings.knownCertificatesCreateNew) { model.pendingReplacement = certificate }
					.accessibilityIdentifier("known-certificates-create-\(certificate.id)")
			}
		}
	}

	private var trustedTable: some View {
		VStack(alignment: .leading, spacing: UISpacing.comfortable) {
			Table(model.visibleTrusted, selection: $model.selection) {
				TableColumn(Text(.Settings.knownCertificatesColumnNetwork)) { Text(verbatim: $0.networkName) }
				TableColumn(Text(.Settings.knownCertificatesColumnNickname)) { Text(verbatim: $0.nickname) }
				TableColumn(Text(.Settings.knownCertificatesColumnFingerprint)) { certificate in
					Text(verbatim: certificate.fingerprint.formatted)
						.font(.body.monospaced())
						.lineLimit(1)
						.truncationMode(.middle)
						.help(Text(verbatim: certificate.fingerprint.formatted))
				}
				.width(min: 160, ideal: 220)
				TableColumn(Text(.Settings.knownCertificatesColumnFirstTrusted)) {
					Text($0.firstTrusted, format: .dateTime.year().month().day())
				}
				TableColumn(Text(.Settings.knownCertificatesColumnLastSeen)) {
					Text($0.lastSeen, format: .dateTime.year().month().day())
				}
			}
			.contextMenu(forSelectionType: DCCKnownCertificatesModel.TrustedCertificate.ID.self) { identifiers in
				if let certificate = model.trusted.first(where: { identifiers.contains($0.id) }), identifiers.count == 1 {
					Button(.Settings.knownCertificatesCopyFingerprint) { model.copy(certificate.fingerprint) }
				}
			}
			.onDeleteCommand(perform: model.selection.isEmpty ? nil : { Task { await model.removeSelected() } })
			.overlay {
				if model.trusted.isEmpty {
					ContentUnavailableView {
						Label(.Settings.knownCertificatesEmpty, systemImage: "lock.shield")
					} description: {
						Text(.Settings.knownCertificatesEmptyDescription)
					}
				}
			}
			.accessibilityIdentifier("known-certificates-table")

			HStack {
				Button(.Settings.knownCertificatesRemove) { Task { await model.removeSelected() } }
					.disabled(model.selection.isEmpty)
					.accessibilityIdentifier("known-certificates-remove")
				Button(.Settings.knownCertificatesRemoveAll) { model.confirmsRemoveAll = true }
					.disabled(model.trusted.isEmpty)
					.accessibilityIdentifier("known-certificates-remove-all")
			}
		}
		.confirmationDialog(Text(.Settings.knownCertificatesRemoveAllConfirmationTitle), isPresented: $model.confirmsRemoveAll) {
			Button(.Settings.knownCertificatesRemoveAllAction, role: .destructive) {
				Task { await model.removeAll() }
			}
			Button(PromptStrings.Action.cancel, role: .cancel) {}
		} message: {
			Text(.Settings.knownCertificatesRemoveAllConfirmationBody)
		}
	}
}
