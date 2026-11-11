// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppIntents

/// A configured server, as the Focus filter's network picker lists it.
nonisolated struct FocusNetworkEntity: AppEntity {
	static let typeDisplayRepresentation = TypeDisplayRepresentation(name: LocalizedStringResource("network", table: "FocusFilter"))
	static let defaultQuery = FocusNetworkQuery()

	let id: String
	let name: String

	var displayRepresentation: DisplayRepresentation {
		DisplayRepresentation(title: "\(name)")
	}
}

nonisolated struct FocusNetworkQuery: EntityQuery {
	func entities(for identifiers: [String]) async throws -> [FocusNetworkEntity] {
		await FocusNetworkCatalog.networks().filter { identifiers.contains($0.id) }
	}

	func suggestedEntities() async throws -> [FocusNetworkEntity] {
		await FocusNetworkCatalog.networks()
	}
}

nonisolated enum FocusNetworkCatalog {
	@MainActor
	static func networks() -> [FocusNetworkEntity] {
		(AppServices.chatSession?.sessions ?? []).map {
			FocusNetworkEntity(id: $0.config.uniqueIdentifier, name: $0.networkNameAlt)
		}
	}
}

nonisolated extension FocusFilterState.Mode: AppEnum {
	static let typeDisplayRepresentation = TypeDisplayRepresentation(name: LocalizedStringResource("mode", table: "FocusFilter"))
	static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
		.muteNotifications: DisplayRepresentation(title: LocalizedStringResource("mode-mute", table: "FocusFilter")),
		.setAway: DisplayRepresentation(title: LocalizedStringResource("mode-away", table: "FocusFilter")),
		.muteAndSetAway: DisplayRepresentation(title: LocalizedStringResource("mode-mute-and-away", table: "FocusFilter")),
	]
}

nonisolated extension FocusFilterState.ConversationKind: AppEnum {
	static let typeDisplayRepresentation = TypeDisplayRepresentation(name: LocalizedStringResource("kind", table: "FocusFilter"))
	static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
		.all: DisplayRepresentation(title: LocalizedStringResource("kind-all", table: "FocusFilter")),
		.channels: DisplayRepresentation(title: LocalizedStringResource("kind-channels", table: "FocusFilter")),
		.directMessages: DisplayRepresentation(title: LocalizedStringResource("kind-direct-messages", table: "FocusFilter")),
	]
}

/** The filter System Settings offers under Focus. The system runs `perform()`
 when a Focus that carries it turns on, and again with no mode when it
 turns off; the result is handed to the sessions as a `FocusFilterState`. */
struct GlasstualFocusFilter: SetFocusFilterIntent {
	static let title = LocalizedStringResource("title", table: "FocusFilter")
	static let description: IntentDescription? = IntentDescription(LocalizedStringResource("summary", table: "FocusFilter"))

	/** Left unset, the filter is off. The system runs `perform()` once more with
	 no values when the Focus ends, and a filter with every default would look
	 the same as that. */
	@Parameter(title: LocalizedStringResource("mode", table: "FocusFilter"))
	var mode: FocusFilterState.Mode?

	@Parameter(title: LocalizedStringResource("networks", table: "FocusFilter"))
	var networks: [FocusNetworkEntity]?

	@Parameter(title: LocalizedStringResource("kind", table: "FocusFilter"), default: .all)
	var conversationKind: FocusFilterState.ConversationKind

	@Parameter(title: LocalizedStringResource("exempt", table: "FocusFilter"), default: false)
	var exemptsHighlightsAndDirectMessages: Bool

	@Parameter(title: LocalizedStringResource("away-message", table: "FocusFilter"))
	var awayMessage: String?

	var displayRepresentation: DisplayRepresentation {
		DisplayRepresentation(title: LocalizedStringResource("title", table: "FocusFilter"))
	}

	var state: FocusFilterState? {
		guard let mode else { return nil }
		return FocusFilterState(
			mode: mode,
			networkIdentifiers: Set((networks ?? []).map(\.id)),
			conversationKind: conversationKind,
			exemptsHighlightsAndDirectMessages: exemptsHighlightsAndDirectMessages,
			awayMessage: awayMessage
		)
	}

	@MainActor
	func perform() async throws -> some IntentResult {
		AppServices.chatSession?.setFocusFilter(state)
		return .result()
	}
}

@MainActor
extension GlasstualFocusFilter {
	/// Re-reads the filter the active Focus carries, which the system does not
	/// deliver again to a launching app. An empty read changes nothing, so it
	/// cannot undo a filter the system delivered while this one was pending. A
	/// read that finds a filter is applied only if nothing was delivered while
	/// it ran, because the Focus may have ended in the meantime.
	static func restoreActiveFilter() async {
		let generation = AppServices.chatSession?.focusFilterGeneration ?? 0
		guard let state = try? await GlasstualFocusFilter.current.state else { return }
		AppServices.chatSession?.restoreFocusFilter(state, readAtGeneration: generation)
	}
}
