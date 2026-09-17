// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** A lookup keyed by a name whose spelling the server decides.

 The server says which two spellings of a name are the same one: under RFC 1459
 `nick[home]` and `nick{home}` are one person and under `ascii` they are two.
 Every lookup here folds through the caller's rule, so the callers do not each
 remember to.

 A `005` can change that rule mid-session, which can merge two keys that were
 distinct. ``rekeyed(by:naming:)`` is what refiles the index under the new rule:
 earlier entries win a collision, ordered by name, so the same `005` always
 produces the same index, and it hands back the entries that lost so the caller
 can take them out of wherever else they are. */
struct CasefoldedIndex<Value> {
	private var storage: [String: Value] = [:]

	init() {}

	subscript(foldedName name: String) -> Value? {
		get { storage[name] }
		set { storage[name] = newValue }
	}

	var count: Int {
		storage.count
	}

	var isEmpty: Bool {
		storage.isEmpty
	}

	var values: some Collection<Value> {
		storage.values
	}

	mutating func removeValue(forFoldedName name: String) {
		storage.removeValue(forKey: name)
	}

	mutating func removeAll() {
		storage.removeAll()
	}

	mutating func reserveCapacity(_ capacity: Int) {
		storage.reserveCapacity(capacity)
	}

	/** Refiles every entry under `fold`, keeping the first of each collision.

	 Returns the entries a collision displaced, in no particular order. They are
	 no longer in the index, so whatever else holds them by name has to let them
	 go too. */
	mutating func rekeyed(by fold: (String) -> String, naming name: (Value) -> String) -> [Value] {
		var rekeyed: [String: Value] = [:]
		rekeyed.reserveCapacity(storage.count)
		var displaced: [Value] = []

		for value in storage.values.sorted(by: { name($0) < name($1) }) {
			let foldedName = fold(name(value))

			if rekeyed[foldedName] == nil {
				rekeyed[foldedName] = value
			} else {
				displaced.append(value)
			}
		}

		storage = rekeyed

		return displaced
	}

	/// Builds the index again from `values`. Earlier values win a collision,
	/// which is the order a linear scan over the same list would have returned.
	mutating func rebuild(from values: some Sequence<Value>, by fold: (String) -> String, naming name: (Value) -> String) {
		var rebuilt: [String: Value] = [:]

		for value in values {
			let foldedName = fold(name(value))

			if rebuilt[foldedName] == nil {
				rebuilt[foldedName] = value
			}
		}

		storage = rebuilt
	}
}
