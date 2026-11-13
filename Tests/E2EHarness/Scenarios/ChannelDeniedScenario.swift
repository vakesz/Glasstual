import ApplicationServices
import Foundation

/// A JOIN the server denies until the user identifies: the denied channel
/// stays in the sidebar, and its context menu's Join Channel joins it once the
/// user has identified, without changing the selected channel first.
struct ChannelDeniedScenario: Scenario {
	let name = "channelDenied"
	let budget = Duration.seconds(150)

	func run(_ context: ScenarioContext) async throws {
		let peer = try await context.launchAgainstPeer(.channelDenied)
		try await context.server(AXID.RowState.disconnected)
		try await context.connect()
		try await context.awaitRegistered()
		try await context.send("/join #other")
		try await context.transcript(contains: "E2E_OTHER_READY")
		try await context.send("/join #retry")
		try await context.until("peer denied JOIN #retry with 477") {
			peer.evidence.deniedJoinPhases.contains(.denied)
		}
		try await context.selectRow("channel", "#retry")
		try await context.until("#retry is listed but not joined") {
			try context.rowState("channel", "#retry") == AXID.RowState.notJoined
		}
		try await context.transcript(contains: "E2E_JOIN_DENIED")
		try await context.selectRow("channel", "#other")
		try await context.send("/msg NickServ IDENTIFY E2E_SYNTHETIC")
		// /msg can select a query; the identified notice is read in #other.
		try await context.selectRow("channel", "#other")
		try await context.transcript(contains: "E2E_IDENTIFIED_READY")
		try await context.joinFromContextMenu("#retry", whileSelected: "#other")
		try await context.until("#retry joined and selected") {
			try context.rowState("channel", "#retry") == AXID.RowState.joined && context.isSelected("channel", "#retry")
		}
		try await context.transcript(contains: "E2E_RETRY_JOINED")
		try await context.quit(peerSeesQuit: true)
		guard peer.evidence.connections == 1,
		      peer.evidence.deniedJoinPhases == [.initial, .otherJoined, .denied, .identified, .joined]
		else {
			throw HarnessFailure
				.assertion("Denied JOIN phases were \(peer.evidence.deniedJoinPhases) over \(peer.evidence.connections) connections")
		}
	}
}

private extension ScenarioContext {
	/// Opens `channel`'s context menu while `selection` stays selected and
	/// chooses Join Channel.
	func joinFromContextMenu(_ channel: String, whileSelected selection: String) async throws {
		let row = try await until("\(channel) row in the sidebar") {
			try sidebar().flatMap { try driver.find(AXID.sidebarRow("channel", channel), in: $0) }
		}
		try driver.showMenu(row)
		do {
			try await until("Join Channel in the context menu") {
				try sidebar().flatMap { try driver.contextMenuItem("joinChannel", of: $0) }
					.map { try driver.isEnabled($0) } ?? false
			}
		} catch {
			// Tells a menu that never opened from one that left Join Channel out.
			let items = try? sidebar().flatMap { try driver.contextMenu(of: $0) }.map { menu in
				try driver.children(menu).compactMap { try driver.string($0, kAXIdentifierAttribute) }
			}
			note("context menu of \(channel): \(items.map { $0.joined(separator: ", ") } ?? "not open")")
			throw error
		}
		guard try isSelected("channel", selection), try isSelected("channel", channel) == false else {
			throw HarnessFailure.assertion("Opening the context menu changed the selected channel")
		}
		try await driver.press("Join Channel") {
			try sidebar().flatMap { try driver.contextMenuItem("joinChannel", of: $0) }
		}
	}
}
