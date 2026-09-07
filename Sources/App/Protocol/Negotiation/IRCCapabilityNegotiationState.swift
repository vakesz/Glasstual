/* *********************************************************************
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation

/** Everything `CAP` negotiation remembers for one connection.

 Requests are pipelined. Every capability the server has offered whose
 dependencies it has already acknowledged goes out as its own `CAP REQ` in one
 pass, and each `ACK` or `NAK` is matched back by name; `CAP END` follows the
 moment nothing is outstanding and nothing else is eligible. A `CAP DEL` naming
 an outstanding request counts as its refusal, so a withdrawal cannot leave a
 request waiting for an answer that is never coming. A server that simply never
 answers a `REQ` holds registration open until the client's own registration
 timeout fires — the same bound that already covers a server which never sends
 `CAP LS` at all.

 The bitset every caller reads through `IRCClient.capabilities` is stored rather
 than projected on each read: `isCapabilityEnabled(_:)` sits on the path of
 every inbound line, and the projection walks the registry to a fixed point.
 Each mutation below refreshes it, which is why the stores it derives from are
 private to this type. */
struct CapabilityNegotiationState {
	/// What `CAP LS`/`NEW` advertised, keyed by the name the server used.
	/// IRCv3 names are case-sensitive, so a key is already the spelling to
	/// echo back in a request.
	private(set) var offeredCapabilities: [String: [String]] = [:]

	/// Names a `CAP REQ` went out for whose answer has not arrived.
	private(set) var outstandingRequests: Set<String> = []

	/// Names the server refused. They are not asked for again until it
	/// re-advertises them.
	private(set) var refusedNames: Set<String> = []

	/// Names the server withdrew with `CAP DEL`. A late `ACK` for one of these
	/// must not bring it back; only a fresh advertisement can.
	private(set) var withdrawnNames: Set<String> = []

	/// Names the server acknowledged, in the order they arrived.
	private(set) var acknowledgedNames: [String] = []

	/// Bits that do not come from `CAP` at all: SASL results and the ISUPPORT
	/// tokens that stand in for a capability. They survive a `CAP DEL` of a
	/// name carrying the same bit, and vice versa.
	private(set) var facts: ClientIRCv3SupportedCapability = []

	/// `acknowledgedNames` projected onto the bitset, plus `facts`.
	private(set) var capabilities: ClientIRCv3SupportedCapability = []

	/// Whether a multi-line `CAP LS` is still arriving. Nothing may be
	/// requested until its last line lands.
	var isCollectingList = false

	/// Set while a SASL exchange is in progress: `CAP END` must not go out
	/// until the exchange has completed.
	var isPaused = false

	/// Whether `CAP END` has already been sent for this registration.
	var endSent = false

	private let registry: CapabilityRegistry

	init(registry: CapabilityRegistry = .defaultRegistry) {
		self.registry = registry
	}

	// MARK: - Queries

	func isAcknowledged(_ name: String) -> Bool {
		acknowledgedNames.contains(name)
	}

	func isOutstanding(_ name: String) -> Bool {
		outstandingRequests.contains(name)
	}

	func isWithdrawn(_ name: String) -> Bool {
		withdrawnNames.contains(name)
	}

	/// The advertisement to measure requests against: what the server offered,
	/// less anything it has already refused, so a dependent capability is not
	/// asked for on the strength of a dependency that will never be granted.
	var requestableOffer: [String: [String]] {
		offeredCapabilities.filter { refusedNames.contains($0.key) == false }
	}

	var enabledCapabilitiesStringValue: String {
		acknowledgedNames.joined(separator: ", ")
	}

	// MARK: - Advertisements

	/// Starts a fresh `CAP LS`. A continuation line adds to the table the first
	/// line opened; only a new listing clears it.
	mutating func beginListing() {
		guard isCollectingList == false else { return }
		offeredCapabilities.removeAll()
		isCollectingList = true
	}

	mutating func finishListing() {
		isCollectingList = false
	}

	/// Drops an advertisement that grew past the ceiling, along with anything
	/// queued off the back of it.
	mutating func discardListing() {
		offeredCapabilities.removeAll()
		isCollectingList = false
	}

	mutating func offer(_ name: String, values: [String]) {
		offeredCapabilities[name] = values
		withdrawnNames.remove(name)
		refusedNames.remove(name)
	}

	/// Records a `CAP DEL`. A request still outstanding for the name is
	/// answered by the withdrawal: nothing else is coming for it.
	mutating func withdraw(_ name: String) {
		offeredCapabilities.removeValue(forKey: name)
		if registry.capability(named: name) != nil {
			withdrawnNames.insert(name)
		}
		outstandingRequests.remove(name)
	}

	// MARK: - Requests

	mutating func noteRequested(_ name: String) {
		outstandingRequests.insert(name)
	}

	/// Marks a request answered.
	mutating func resolveRequest(_ name: String) {
		outstandingRequests.remove(name)
	}

	mutating func refuse(_ name: String) {
		guard registry.capability(named: name) != nil else { return }
		refusedNames.insert(name)
	}

	// MARK: - Acknowledgement

	/** Records an acknowledged name. Reports whether it took.

	 A name the server has withdrawn is refused: a `CAP DEL` and a late `ACK`
	 can cross, and the withdrawal is the newer fact. The ceiling is the same
	 one `CAP LS` is held to, because an `ACK` is server-controlled input too. */
	mutating func acknowledge(_ name: String) -> Bool {
		guard withdrawnNames.contains(name) == false,
		      acknowledgedNames.count < ClientNegotiationUtilities.maximumOfferedCapabilities
		else {
			return false
		}

		guard acknowledgedNames.contains(name) == false else { return true }

		acknowledgedNames.append(name)
		recomputeCapabilities()

		return true
	}

	mutating func revoke(_ name: String) {
		guard acknowledgedNames.contains(name) else { return }
		acknowledgedNames.removeAll { $0 == name }
		recomputeCapabilities()
	}

	// MARK: - Bitset entry points

	/** Turns a bitset into the names and facts that produce it.

	 Bits the registry knows are recorded as the acknowledged name that carries
	 them, so a later `CAP DEL` of that name takes them away again. Bits it does
	 not know are facts. */
	mutating func enable(_ capability: ClientIRCv3SupportedCapability) {
		facts.formUnion(capability.subtracting(registry.knownIdentifiers))

		var remaining = capability.intersection(registry.knownIdentifiers)

		/* A name carrying every remaining bit is the right name for them; one
		 carrying only some is used once no exact carrier is left, so a bitset
		 naming one capability is not filed under a vendor alias that overlaps. */
		claimNames(for: &remaining) { remaining, entry in remaining.contains(entry.identifier) }
		claimNames(for: &remaining) { remaining, entry in remaining.isDisjoint(with: entry.identifier) == false }

		recomputeCapabilities()
	}

	mutating func disable(_ capability: ClientIRCv3SupportedCapability) {
		facts.subtract(capability)
		acknowledgedNames.removeAll { name in
			guard let entry = registry.capability(named: name) else { return false }
			return entry.identifier.isDisjoint(with: capability) == false
		}
		recomputeCapabilities()
	}

	/// The setter behind the public `IRCClient.capabilities`, kept for plugin
	/// compatibility: it replaces the projection outright rather than merging.
	mutating func replaceProjection(with capability: ClientIRCv3SupportedCapability) {
		facts = []
		acknowledgedNames.removeAll()
		enable(capability)
	}

	mutating func addFacts(_ capability: ClientIRCv3SupportedCapability) {
		guard facts.contains(capability) == false else { return }
		facts.formUnion(capability)
		recomputeCapabilities()
	}

	mutating func removeFacts(_ capability: ClientIRCv3SupportedCapability) {
		guard facts.isDisjoint(with: capability) == false else { return }
		facts.subtract(capability)
		recomputeCapabilities()
	}

	// MARK: - Reset

	/// Returns the negotiation to what it was before the connection opened.
	mutating func reset() {
		offeredCapabilities.removeAll()
		outstandingRequests.removeAll()
		refusedNames.removeAll()
		withdrawnNames.removeAll()
		acknowledgedNames.removeAll()
		facts = []
		capabilities = []
		isCollectingList = false
		isPaused = false
		endSent = false
	}

	// MARK: - Private

	private mutating func claimNames(
		for remaining: inout ClientIRCv3SupportedCapability,
		matching supplies: (ClientIRCv3SupportedCapability, Capability) -> Bool
	) {
		for entry in registry.capabilities where supplies(remaining, entry) {
			if acknowledgedNames.contains(entry.name) == false {
				acknowledgedNames.append(entry.name)
			}
			remaining.subtract(entry.identifier)
		}
	}

	private mutating func recomputeCapabilities() {
		capabilities = registry.projection(of: acknowledgedNames).union(facts)
	}
}
