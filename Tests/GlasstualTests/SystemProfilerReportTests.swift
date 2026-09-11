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

import Darwin
import Foundation
@testable import Glasstual
import GlasstualPluginKit
import Testing

/// The System Info plugin is driven through its own ABI: its report types are
/// not visible from here, so what is asserted is what a user sees — that every
/// command still answers, including the two whose collection moved off the main
/// actor and now answer a moment later.
@Suite("System profiler reports")
@MainActor
struct SystemProfilerReportTests {
	@MainActor
	private final class SentLines {
		var lines: [String] = []
	}

	private func makeHost(defaults: UserDefaults, channel: PluginChannel) -> PluginHostContext {
		PluginHostContext(
			defaults: defaults,
			clients: { [] },
			selectedChannel: { channel },
			metrics: {
				PluginApplicationMetrics(
					messagesSent: 0,
					messagesReceived: 0,
					bandwidthIn: 0,
					bandwidthOut: 0,
					lastMessageReceived: 0,
					visibleLineCount: 0,
					usesDarkSidebar: false
				)
			},
			applicationSnapshot: { nil },
			themeSnapshot: { nil },
			observeConnectionState: { handler in
				handler(false)
				return PluginObservation(cancellation: {})
			},
			removesFormatting: { false }
		)
	}

	private func makeChannel() -> PluginChannel {
		PluginChannel(
			identifier: "channel",
			name: "#room",
			type: .channel,
			isActive: true,
			members: [],
			autoJoin: { false },
			setAutoJoin: { _ in },
			deactivate: {}
		)
	}

	private func makeClient(sending sent: SentLines) -> PluginClient {
		PluginClient(
			identifier: "client",
			userNickname: "tester",
			networkName: "Test Network",
			serverAddress: "irc.example.test",
			isConnected: true,
			isLoggedIn: true,
			isIRCop: false,
			localUser: nil,
			channels: [],
			isConnectedToZNC: false,
			zncCertificateChainData: nil,
			maximumNicknameLength: 30,
			nicknameMatchesZNCUser: { $0 == $1 },
			isChannelName: { $0.hasPrefix("#") },
			findChannel: { _ in nil },
			privateMessage: { _ in nil },
			utilityChannel: { _ in nil },
			isCapabilityEnabled: { _ in false },
			printDebug: { line, _ in sent.lines.append(line) },
			sendPrivateMessage: { line, _ in sent.lines.append(line) },
			sendCommand: { _ in },
			sendLine: { _ in },
			joinChannel: { _ in },
			printMessage: { _, _, _, _, _, _, _, completion in completion(PluginPrintResult(isHighlight: false)) },
			markUnread: { _, _ in },
			markHighlight: { _ in },
			refreshSidebar: {}
		)
	}

	/// Runs one command against a freshly loaded System Info plugin and returns
	/// the lines it sent, waiting for the ones it collects off the main actor.
	private func report(for command: String) async throws -> [String] {
		let bundleURL = PathInfo.bundledExtensionsURL
			.appendingPathComponent("System Info.bundle", isDirectory: true)
		let bundle = try #require(Bundle(url: bundleURL))
		let suiteName = "SystemProfilerReportTests.\(UUID().uuidString)"
		let defaults = try #require(UserDefaults(suiteName: suiteName))
		defer { defaults.removePersistentDomain(forName: suiteName) }

		let channel = makeChannel()
		let plugin = try #require(PluginItem.load(bundle, host: makeHost(defaults: defaults, channel: channel)))
		defer { plugin.unloadBundle() }
		let handler = try #require(plugin.primaryClass as? any PluginCommandHandling)

		let sent = SentLines()
		handler.userInputCommandInvoked(
			PluginCommandInvocation(
				client: makeClient(sending: sent),
				command: command,
				message: "",
				selectedChannel: channel,
				connectedClients: []
			)
		)

		/* `/sysinfo` and `/diskspace` collect off the main actor and print when
		 the collection lands, so the answer is awaited rather than assumed. */
		for _ in 0 ..< 100 where sent.lines.isEmpty {
			try await Task.sleep(for: .milliseconds(50))
		}

		return sent.lines
	}

	/// The two reports whose collection moved to a `@concurrent` function: what
	/// matters is that the report still reaches the channel.
	@Test("A report collected off the main actor still reaches the channel", arguments: ["SYSINFO", "DISKSPACE"])
	func collectedReportsStillArrive(_ command: String) async throws {
		let lines = try await report(for: command)

		#expect(lines.joined().isEmpty == false)
	}

	/** `/netstats` reads `if_data64` through `NET_RT_IFLIST2` instead of the
	 32-bit counters `getifaddrs` reports, which wrap every four gigabytes — a
	 figure one session passes — after which the report showed the remainder
	 rather than what had moved.

	 The counters belong to the machine running the test, so it is the machine
	 that decides how much can be said. Where one of its interfaces has passed
	 the wrap, the figure for that interface cannot be the remainder; where none
	 has, the two readings are indistinguishable and all that is left to check is
	 that the report arrives. */
	@Test("Network statistics answer from the 64-bit counters")
	func networkStatisticsAnswer() async throws {
		let lines = try await report(for: "NETSTATS")
		let reply = lines.joined()

		#expect(reply.isEmpty == false)

		/* Well clear of the thresholds, so that the counters moving between the
		 report's reading and this one cannot put the two readings on opposite
		 sides of one. */
		for interface in Self.reportedInterfaces()
			where interface.received > 40_000_000 && interface.sent > 4_000_000
		{
			let segment = try #require(
				Self.segment(forInterface: interface.name, in: reply),
				"\(interface.name) moved \(interface.received) bytes in and is missing from: \(reply)"
			)

			guard interface.received > UInt64(UInt32.max) else { continue }

			let wrapped = Self.formattedByteCount(interface.received % (UInt64(UInt32.max) &+ 1))

			#expect(segment.contains(wrapped) == false, "\(interface.name) is reporting a wrapped counter")
			// Anything past the wrap is at least 4.29 GB, however it is rounded.
			#expect(segment.contains("GB") || segment.contains("TB"))
		}
	}

	/// One interface's byte counters, as the plugin's own reading of
	/// `NET_RT_IFLIST2` finds them. Read here so the test can say what the
	/// report has to contain rather than trusting the report to say it.
	private struct InterfaceCounters {
		let name: String
		let received: UInt64
		let sent: UInt64
	}

	/// The interfaces `/netstats` reports: up, running, not loopback, and past
	/// the thresholds that keep an idle interface out of the list.
	private static func reportedInterfaces() -> [InterfaceCounters] {
		var name: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
		var size = 0
		guard sysctl(&name, UInt32(name.count), nil, &size, nil, 0) == 0, size > 0 else { return [] }

		var buffer = [UInt8](repeating: 0, count: size)
		guard sysctl(&name, UInt32(name.count), &buffer, &size, nil, 0) == 0 else { return [] }

		return buffer.withUnsafeBytes { raw -> [InterfaceCounters] in
			var result: [InterfaceCounters] = []
			var offset = 0

			while offset + 4 <= size {
				let length = Int(raw.loadUnaligned(fromByteOffset: offset, as: UInt16.self))
				let type = raw.loadUnaligned(fromByteOffset: offset + 3, as: UInt8.self)
				guard length > 0, offset + length <= size else { break }
				defer { offset += length }
				guard Int32(type) == RTM_IFINFO2, length >= MemoryLayout<if_msghdr2>.size else { continue }

				let message = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
				guard message.ifm_flags & (IFF_UP | IFF_RUNNING) != 0 else { continue }

				var interfaceName = [CChar](repeating: 0, count: Int(IFNAMSIZ))
				guard if_indextoname(UInt32(message.ifm_index), &interfaceName) != nil else { continue }
				let nameBytes = interfaceName.prefix { $0 != 0 }.map(UInt8.init(bitPattern:))
				guard let interface = String(bytes: nameBytes, encoding: .utf8),
				      interface.hasPrefix("lo") == false,
				      message.ifm_data.ifi_ibytes >= 20_000_000,
				      message.ifm_data.ifi_obytes >= 2_000_000
				else { continue }

				result.append(InterfaceCounters(
					name: interface,
					received: message.ifm_data.ifi_ibytes,
					sent: message.ifm_data.ifi_obytes
				))
			}

			return result
		}
	}

	/// What the report says about one interface: from its name to the start of
	/// the next entry.
	private static func segment(forInterface name: String, in reply: String) -> String? {
		guard let start = reply.range(of: "[\(name)]") else { return nil }
		let rest = reply[start.upperBound...]
		let end = rest.range(of: " — ")?.lowerBound ?? rest.endIndex

		return String(rest[..<end])
	}

	/// The plugin's own spelling of a byte count, so the two can be compared.
	private static func formattedByteCount(_ count: UInt64) -> String {
		ByteCountFormatter.string(fromByteCount: Int64(clamping: count), countStyle: .file)
	}

	/// The commands that never left the main actor still answer synchronously.
	@Test("The reports that stayed on the main actor still answer", arguments: ["SYSMEM", "UPTIME"])
	func mainActorReportsStillAnswer(_ command: String) async throws {
		let lines = try await report(for: command)

		#expect(lines.joined().isEmpty == false)
	}
}
