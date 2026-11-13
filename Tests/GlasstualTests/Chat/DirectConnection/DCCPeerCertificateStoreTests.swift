// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@Suite("DCC peer certificate store")
struct DCCPeerCertificateStoreTests {
	private static let date = Date(timeIntervalSince1970: 1_800_000_000)

	private static func makeDirectory() throws -> URL {
		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent("DCCPeerCertificateStoreTests-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		return directory
	}

	private static func certificate() throws -> DCCPeerCertificate {
		try #require(DCCPeerCertificate(der: PeerCertificateFixture.ellipticCurve()))
	}

	@Test("Pins round-trip through a versioned XML property list")
	func roundTrip() async throws {
		let directory = try Self.makeDirectory()
		defer { try? FileManager.default.removeItem(at: directory) }
		let url = directory.appendingPathComponent("Pins.plist")
		let certificate = try Self.certificate()

		let store = DCCPeerCertificateStore(fileURL: url)
		try await store.remember(
			certificate, network: "net", nickname: "Peer", caseMapping: .rfc1459, account: "acct", at: Self.date
		)

		let text = try String(contentsOf: url, encoding: .utf8)
		#expect(text.hasPrefix("<?xml"))
		let file = try PropertyListDecoder().decode(DCCPeerCertificateFile.self, from: Data(contentsOf: url))
		#expect(file.version == DCCPeerCertificateFile.currentVersion)

		let reopened = DCCPeerCertificateStore(fileURL: url)
		let pins = await reopened.pins(network: "net", nickname: "peer", caseMapping: .rfc1459)
		#expect(pins.map(\.fingerprint) == [certificate.fingerprint])
		#expect(pins.first?.nickname == "Peer")
		#expect(pins.first?.account == "acct")
		#expect(pins.first?.firstTrusted == Self.date)
	}

	@Test("Networks are kept apart and forgetting one leaves the others")
	func networks() async throws {
		let store = DCCPeerCertificateStore(fileURL: nil)
		let certificate = try Self.certificate()
		try await store.remember(certificate, network: "a", nickname: "peer", caseMapping: .ascii, account: nil, at: Self.date)
		try await store.remember(certificate, network: "b", nickname: "peer", caseMapping: .ascii, account: nil, at: Self.date)

		#expect(await store.pins(network: "c", nickname: "peer", caseMapping: .ascii).isEmpty)
		try await store.forgetNetwork("a")
		#expect(await store.pins(network: "a", nickname: "peer", caseMapping: .ascii).isEmpty)
		#expect(await store.pins(network: "b", nickname: "peer", caseMapping: .ascii).count == 1)
		#expect(await store.all().keys.sorted() == ["b"])
	}

	@Test("Nicknames are folded with the network's casemapping")
	func casefolding() async throws {
		let store = DCCPeerCertificateStore(fileURL: nil)
		try await store.remember(
			Self.certificate(), network: "net", nickname: "[Peer]", caseMapping: .rfc1459, account: nil, at: Self.date
		)

		#expect(await store.pins(network: "net", nickname: "{peer}", caseMapping: .rfc1459).count == 1)
		#expect(await store.pins(network: "net", nickname: "[PEER]", caseMapping: .rfc1459).count == 1)
		#expect(await store.pins(network: "net", nickname: "[peer]", caseMapping: .ascii).isEmpty)
	}

	@Test("A pin made under one casemapping is found, and moved, under another")
	func casemappingChange() async throws {
		let store = DCCPeerCertificateStore(fileURL: nil)
		let certificate = try Self.certificate()
		try await store.remember(certificate, network: "net", nickname: "Peer", caseMapping: .ascii, account: nil, at: Self.date)

		#expect(await store.pins(network: "net", nickname: "PEER", caseMapping: .rfc7613).count == 1)
		let later = Self.date.addingTimeInterval(60)
		try await store.touch(certificate.fingerprint, network: "net", nickname: "PEER", caseMapping: .rfc7613, at: later)

		let all = await store.all()["net"] ?? [:]
		#expect(all.count == 1)
		#expect(all.values.first?.first?.lastSeen == later)
	}

	@Test("Remembering adds a pin, replacing keeps one and forgetting removes all")
	func changes() async throws {
		let store = DCCPeerCertificateStore(fileURL: nil)
		let first = try Self.certificate()
		let second = try Self.certificate()
		let third = try Self.certificate()

		try await store.remember(first, network: "net", nickname: "peer", caseMapping: .ascii, account: nil, at: Self.date)
		try await store.remember(second, network: "net", nickname: "peer", caseMapping: .ascii, account: nil, at: Self.date)
		try await store.remember(second, network: "net", nickname: "peer", caseMapping: .ascii, account: nil, at: Self.date)
		#expect(await store.pins(network: "net", nickname: "peer", caseMapping: .ascii).map(\.fingerprint)
			== [first.fingerprint, second.fingerprint])

		try await store.replace(with: third, network: "net", nickname: "peer", caseMapping: .ascii, account: nil, at: Self.date)
		#expect(await store.pins(network: "net", nickname: "peer", caseMapping: .ascii).map(\.fingerprint)
			== [third.fingerprint])

		try await store.forget(network: "net", nickname: "peer", caseMapping: .ascii)
		#expect(await store.all().isEmpty)
	}

	@Test("An unreadable file is moved aside, never overwritten, and the store starts empty")
	func corruptFile() async throws {
		let directory = try Self.makeDirectory()
		defer { try? FileManager.default.removeItem(at: directory) }
		let url = directory.appendingPathComponent("Pins.plist")
		let garbage = Data("not a property list".utf8)
		try garbage.write(to: url)

		let store = DCCPeerCertificateStore(fileURL: url)
		#expect(await store.all().isEmpty)
		try await store.remember(
			Self.certificate(), network: "net", nickname: "peer", caseMapping: .ascii, account: nil, at: Self.date
		)

		let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
		let setAside = try #require(names.first { $0.hasPrefix("Pins.unreadable-") && $0.hasSuffix(".plist") })
		#expect(try Data(contentsOf: directory.appendingPathComponent(setAside)) == garbage)
		#expect(names.count == 2)
	}

	@Test("A file from a newer version is set aside rather than rewritten")
	func newerVersion() async throws {
		let directory = try Self.makeDirectory()
		defer { try? FileManager.default.removeItem(at: directory) }
		let url = directory.appendingPathComponent("Pins.plist")
		var newer = DCCPeerCertificateFile()
		newer.version = DCCPeerCertificateFile.currentVersion + 1
		try PropertyListEncoder().encode(newer).write(to: url)

		let store = DCCPeerCertificateStore(fileURL: url)
		#expect(await store.all().isEmpty)
		#expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).count == 1)
		#expect(FileManager.default.fileExists(atPath: url.path) == false)
	}

	@Test("Concurrent changes are serialized and none is lost")
	func concurrentRemember() async throws {
		let directory = try Self.makeDirectory()
		defer { try? FileManager.default.removeItem(at: directory) }
		let url = directory.appendingPathComponent("Pins.plist")
		let store = DCCPeerCertificateStore(fileURL: url)
		let certificates = try (0 ..< 8).map { _ in try Self.certificate() }

		try await withThrowingTaskGroup(of: Void.self) { group in
			for (index, certificate) in certificates.enumerated() {
				group.addTask {
					try await store.remember(
						certificate, network: "net", nickname: "peer\(index % 2)",
						caseMapping: .ascii, account: nil, at: .now
					)
				}
			}
			try await group.waitForAll()
		}

		let reopened = DCCPeerCertificateStore(fileURL: url)
		let all = await reopened.all()["net"] ?? [:]
		#expect(all.values.reduce(0) { $0 + $1.count } == 8)
	}
}
