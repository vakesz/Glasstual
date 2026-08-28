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
@testable import Glasstual
import Testing

/// The nibs name their classes, outlets and actions as strings, so those names
/// are the one part of the Objective-C surface that has to survive. This suite
/// reads the nibs and checks the names against the running application, which
/// is what makes it safe to drop `@objc` everywhere else.
@Suite("Nib runtime names")
@MainActor
struct NibRuntimeNameTests {
	private static func nibURLs() throws -> [URL] {
		let directory = URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.appending(path: "Sources/App/Resources/User Interface/en.lproj")

		return try FileManager.default
			.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
			.filter { $0.pathExtension == "xib" }
			.sorted { $0.lastPathComponent < $1.lastPathComponent }
	}

	private static func attributeValues(_ attribute: String, in url: URL) throws -> Set<String> {
		let document = try XMLDocument(contentsOf: url)
		let nodes = try document.nodes(forXPath: "//*[@\(attribute)]")

		return Set(nodes.compactMap { ($0 as? XMLElement)?.attribute(forName: attribute)?.stringValue })
	}

	/// AppKit's own classes and the placeholder proxies are named the same way
	/// but are not ours to keep alive.
	private static let foreignClasses: Set<String> = [
		"FirstResponder",
		"NSObject",
		"NSSecureTextField",
	]

	@Test("Every class a nib names is present in the Objective-C runtime")
	func nibClassesResolve() throws {
		let urls = try Self.nibURLs()
		#expect(urls.isEmpty == false)

		var missing: [String] = []
		for url in urls {
			for className in try Self.attributeValues("customClass", in: url)
				.subtracting(Self.foreignClasses)
				where NSClassFromString(className) == nil
			{
				missing.append("\(url.lastPathComponent): \(className)")
			}
		}

		#expect(missing.isEmpty, "Classes a nib names that the runtime does not have: \(missing.sorted())")
	}

	/// A nib connects an outlet by calling `setValue(_:forKey:)`, so a property
	/// that is no longer visible to the runtime raises
	/// NSUnknownKeyException while the nib loads.
	@Test("Every outlet a nib connects is key-value coding compliant on its owner")
	func nibOutletsAreCodingCompliant() throws {
		var missing: [String] = []
		var checked = 0

		for url in try Self.nibURLs() {
			let document = try XMLDocument(contentsOf: url)

			for node in try document.nodes(forXPath: "//outlet") {
				guard let element = node as? XMLElement,
				      let property = element.attribute(forName: "property")?.stringValue,
				      let owner = Self.ownerClassName(of: element),
				      Self.foreignClasses.contains(owner) == false,
				      let ownerClass = NSClassFromString(owner)
				else { continue }

				checked += 1

				if ownerClass.instancesRespond(to: NSSelectorFromString(property)) == false,
				   ownerClass.instancesRespond(to: NSSelectorFromString(Self.setter(for: property))) == false
				{
					missing.append("\(url.lastPathComponent): \(owner).\(property)")
				}
			}
		}

		#expect(checked > 100, "The nibs should declare far more outlets than this")
		#expect(missing.isEmpty, "Outlets a nib connects that no longer exist: \(missing.sorted())")
	}

	/// An outlet belongs to the object that declares it, which is the element
	/// immediately containing the `<connections>` block. `nil` means the owner
	/// is an AppKit class, whose outlets are not ours to keep.
	private static func ownerClassName(of element: XMLElement) -> String? {
		guard let connections = element.parent as? XMLElement, connections.name == "connections" else {
			return nil
		}

		return (connections.parent as? XMLElement)?.attribute(forName: "customClass")?.stringValue
	}

	private static func setter(for property: String) -> String {
		"set\(property.prefix(1).uppercased())\(property.dropFirst()):"
	}
}
