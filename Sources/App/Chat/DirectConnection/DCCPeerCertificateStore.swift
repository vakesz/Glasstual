// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
import os

/// The trust store's file: pins by network identifier, then by casefolded
/// nickname.
nonisolated struct DCCPeerCertificateFile: Codable, Equatable, Sendable {
	static let currentVersion = 1

	var version: Int
	var networks: [String: [String: [DCCPeerPin]]]

	init(networks: [String: [String: [DCCPeerPin]]] = [:]) {
		version = Self.currentVersion
		self.networks = networks
	}
}

/** The certificates the user decided to trust for secure DCC peers.

 Pins are kept per network and per nickname, in an XML property list beside
 the rest of the application's support files. They are not settings: export
 never carries them, because who the user exchanges files with is
 relationship metadata even though fingerprints are not secret.

 A file that cannot be read is moved aside and the store starts empty, so a
 damaged or newer file is never silently overwritten. Every change is written
 atomically before the call that made it returns. */
actor DCCPeerCertificateStore {
	private let fileURL: URL?
	private let fileManager = FileManager()
	private var file: DCCPeerCertificateFile?
	/// Set when an unreadable file could not be moved aside. Writing would
	/// replace it, so changes stay in memory instead and every write fails.
	private var isUnwritable = false

	/// `nil` keeps pins in memory only, which is what is left when the
	/// application has no support directory.
	init(fileURL: URL?) {
		self.fileURL = fileURL
	}

	/// The pins for `nickname` on `network`.
	///
	/// A nickname is filed under its fold in the casemapping the network
	/// announced when it was pinned. If that mapping has changed since, the
	/// ASCII fold, which every mapping agrees on for plain nicknames, finds it
	/// instead.
	func pins(network: String, nickname: String, caseMapping: ISupportCaseMapping) -> [DCCPeerPin] {
		let pins = loaded().networks[network] ?? [:]
		if let found = pins[Self.key(nickname, caseMapping)], found.isEmpty == false {
			return found
		}
		return pins[Self.key(nickname, .ascii)] ?? []
	}

	/// Adds `certificate` to the nickname's pins, keeping the others.
	func remember(
		_ certificate: DCCPeerCertificate,
		network: String,
		nickname: String,
		caseMapping: ISupportCaseMapping,
		account: String?,
		at date: Date
	) throws {
		try update(network: network, nickname: nickname, caseMapping: caseMapping) { pins in
			guard pins.contains(where: { $0.fingerprint == certificate.fingerprint }) == false else { return }
			pins.append(DCCPeerPin(certificate: certificate, nickname: nickname, account: account, at: date))
		}
	}

	/// Makes `certificate` the nickname's only pin.
	func replace(
		with certificate: DCCPeerCertificate,
		network: String,
		nickname: String,
		caseMapping: ISupportCaseMapping,
		account: String?,
		at date: Date
	) throws {
		try update(network: network, nickname: nickname, caseMapping: caseMapping) { pins in
			pins = [DCCPeerPin(certificate: certificate, nickname: nickname, account: account, at: date)]
		}
	}

	/// Records that a pinned certificate was presented again.
	func touch(
		_ fingerprint: DCCCertificateFingerprint,
		network: String,
		nickname: String,
		caseMapping: ISupportCaseMapping,
		at date: Date
	) throws {
		try update(network: network, nickname: nickname, caseMapping: caseMapping) { pins in
			guard let index = pins.firstIndex(where: { $0.fingerprint == fingerprint }) else { return }
			pins[index].lastSeen = date
		}
	}

	/// Removes every pin for the nickname on the network.
	func forget(network: String, nickname: String, caseMapping: ISupportCaseMapping) throws {
		try update(network: network, nickname: nickname, caseMapping: caseMapping) { pins in
			pins.removeAll()
		}
	}

	/// Removes every pin on the network, for when its configuration is deleted.
	func forgetNetwork(_ network: String) throws {
		var contents = loaded()
		guard contents.networks.removeValue(forKey: network) != nil else { return }
		try write(contents)
	}

	/// Every pin, by network and then casefolded nickname.
	func all() -> [String: [String: [DCCPeerPin]]] {
		loaded().networks
	}

	/// Removes one pin, named by the key ``all()`` files it under.
	func remove(_ fingerprint: DCCCertificateFingerprint, network: String, nicknameKey: String) throws {
		var contents = loaded()
		guard var nicknames = contents.networks[network], var pins = nicknames[nicknameKey] else { return }
		pins.removeAll { $0.fingerprint == fingerprint }
		nicknames[nicknameKey] = pins.isEmpty ? nil : pins
		contents.networks[network] = nicknames.isEmpty ? nil : nicknames
		guard contents != loaded() else { return }
		try write(contents)
	}

	/// Removes every pin on every network.
	func forgetAll() throws {
		guard loaded().networks.isEmpty == false else { return }
		try write(DCCPeerCertificateFile())
	}

	// MARK: - Storage

	private static func key(_ nickname: String, _ caseMapping: ISupportCaseMapping) -> String {
		IRCCaseFolding.fold(nickname, using: caseMapping)
	}

	private func update(
		network: String,
		nickname: String,
		caseMapping: ISupportCaseMapping,
		_ change: (inout [DCCPeerPin]) -> Void
	) throws {
		var contents = loaded()
		var nicknames = contents.networks[network] ?? [:]
		let current = Self.key(nickname, caseMapping)
		let ascii = Self.key(nickname, .ascii)
		/* A pin filed under the ASCII fold by an earlier casemapping is the one
		 a lookup finds, so a change applies to it and moves it under the current
		 fold rather than leaving two lists for one person. */
		let existingKey = nicknames[current]?.isEmpty == false || nicknames[ascii] == nil ? current : ascii
		var pins = nicknames.removeValue(forKey: existingKey) ?? []
		change(&pins)
		if pins.isEmpty == false {
			nicknames[current] = pins
		}
		contents.networks[network] = nicknames.isEmpty ? nil : nicknames
		guard contents != loaded() else { return }
		try write(contents)
	}

	private func loaded() -> DCCPeerCertificateFile {
		if let file {
			return file
		}
		let contents = read()
		file = contents
		return contents
	}

	private func read() -> DCCPeerCertificateFile {
		guard let fileURL, let data = try? Data(contentsOf: fileURL) else {
			return DCCPeerCertificateFile()
		}
		do {
			let contents = try PropertyListDecoder().decode(DCCPeerCertificateFile.self, from: data)
			guard contents.version == DCCPeerCertificateFile.currentVersion else {
				throw CocoaError(.fileReadCorruptFile)
			}
			return contents
		} catch {
			moveAside(fileURL, because: error)
			return DCCPeerCertificateFile()
		}
	}

	private func write(_ contents: DCCPeerCertificateFile) throws {
		guard isUnwritable == false else {
			throw CocoaError(.fileWriteNoPermission)
		}
		if let fileURL {
			let encoder = PropertyListEncoder()
			encoder.outputFormat = .xml
			try fileManager.createDirectory(
				at: fileURL.deletingLastPathComponent(),
				withIntermediateDirectories: true
			)
			try encoder.encode(contents).write(to: fileURL, options: .atomic)
		}
		file = contents
	}

	private func moveAside(_ fileURL: URL, because error: Error) {
		let formatter = ISO8601DateFormatter()
		formatter.formatOptions = [.withFullDate, .withTime]
		let stamp = formatter.string(from: .now)
		let name = fileURL.deletingPathExtension().lastPathComponent + ".unreadable-\(stamp)"
		let destination = fileURL.deletingLastPathComponent()
			.appendingPathComponent(name)
			.appendingPathExtension(fileURL.pathExtension)

		DirectConnectionLog.transport.error(
			"The DCC peer certificate store is unreadable and was set aside: \(error.localizedDescription, privacy: .public)"
		)
		do {
			try fileManager.moveItem(at: fileURL, to: destination)
		} catch {
			isUnwritable = true
			DirectConnectionLog.transport.error(
				"Could not set the unreadable DCC peer certificate store aside: \(error.localizedDescription, privacy: .public)"
			)
		}
	}
}

extension ServerConfig {
	/// Removes the secure DCC pins filed under this network once its
	/// configuration is deleted. The caller does not wait for the file.
	func forgetDCCPeerCertificates() {
		let network = uniqueIdentifier
		Task {
			do {
				try await DCCPeerCertificateStore.shared.forgetNetwork(network)
			} catch {
				DirectConnectionLog.transport.error(
					"Could not remove a deleted network's DCC peer certificates: \(error.localizedDescription, privacy: .public)"
				)
			}
		}
	}
}
