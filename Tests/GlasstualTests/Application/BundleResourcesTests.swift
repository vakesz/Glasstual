// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Bundled resources", .serialized)
struct BundleResourcesTests {
	@Test("The bundled property lists load through the resource manager")
	func bundleResourcesLoadsKnownPropertyLists() {
		let networks = BundleResources.dictionary(fromResources: "IRCNetworks", cacheValue: false)
		let networkList = BundleResources.array(fromResources: "IRCNetworks", cacheValue: false)
		let staticStore = BundleResources.dictionary(fromResources: "StaticStore")

		#expect(networks != nil || networkList != nil)
		#expect(staticStore != nil)
		#expect((staticStore?.count ?? 0) > 0)
	}

	/// Each key is a contract between `StaticStore.plist` and the constant that
	/// names it, and a key that stops resolving reads as an empty list rather
	/// than as an error: NickServ identification would stop being recognised and
	/// the forbidden-command guard would stop forbidding anything, both silently.
	@Test(
		"Every declared key of the static store resolves to a list",
		arguments: [
			StaticStoreResource.spellingIgnoresKey,
			StaticStoreResource.forbiddenScriptCommandsKey,
			StaticStoreResource.nickServNeedsIdentificationTokensKey,
			StaticStoreResource.nickServIdentifiedTokensKey,
		]
	)
	func staticStoreKeysResolve(key: String) {
		let values = BundleResources.array(fromResources: StaticStoreResource.name, key: key, cacheValue: false)

		#expect(values?.isEmpty == false)
	}

	@Test("A cached resource is served from the cache, and the wrong type reads as nothing")
	func bundleResourcesCachesAndRejectsWrongTypes() {
		/* The cache is process-wide; empty it on the way out as well so the
		 entry this test plants does not answer another one's lookup. */
		BundleResources.removeAllCachedResources()
		defer { BundleResources.removeAllCachedResources() }

		let first = BundleResources.dictionary(fromResources: "StaticStore", cacheValue: true)
		let second = BundleResources.dictionary(fromResources: "StaticStore", cacheValue: true)

		#expect(first != nil)
		#expect(first as NSDictionary? == second as NSDictionary?)
		#expect(BundleResources.hasCachedResource(named: "StaticStore"))
		#expect(BundleResources.array(fromResources: "StaticStore", cacheValue: false) == nil)
		#expect(BundleResources.dictionary(fromResources: "DoesNotExistAnywhere", cacheValue: false) == nil)
		#expect(BundleResources.hasCachedResource(named: "DoesNotExistAnywhere") == false)
	}
}
