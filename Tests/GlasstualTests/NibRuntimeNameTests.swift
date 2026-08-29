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

	/// A menu item or control sends its action selector to a target that has to
	/// answer it. An action whose target is named in the nib is checked against
	/// that class; one aimed at the first responder travels the chain, so it is
	/// enough that some class in the application answers it.
	/// The AppKit classes that answer the standard menu actions a main menu
	/// carries: the application itself, the window, and the text system.
	private static let appKitResponders: [AnyClass] = [
		NSApplication.self,
		NSResponder.self,
		NSWindow.self,
		NSText.self,
		NSTextView.self,
		UndoManager.self,
	]

	@Test("Every action a nib sends is answered by something in the application")
	func nibActionsAreAnswered() throws {
		var missing: [String] = []
		var checked = 0

		for url in try Self.nibURLs() {
			let document = try XMLDocument(contentsOf: url)
			let classes = try Self.attributeValues("customClass", in: url)
				.subtracting(Self.foreignClasses)
				.compactMap { NSClassFromString($0) }

			for node in try document.nodes(forXPath: "//action") {
				guard let element = node as? XMLElement,
				      let selectorName = element.attribute(forName: "selector")?.stringValue
				else { continue }

				let selector = NSSelectorFromString(selectorName)
				checked += 1

				/* AppKit answers its own editing, text and window actions; ours
				 have to be answered by a class the same nib names. */
				if Self.appKitResponders.contains(where: { $0.instancesRespond(to: selector) })
					|| classes.contains(where: { $0.instancesRespond(to: selector) })
				{
					continue
				}

				missing.append("\(url.lastPathComponent): \(selectorName)")
			}
		}

		#expect(checked > 100, "The nibs should send far more actions than this")
		#expect(missing.isEmpty, "Actions a nib sends that nothing answers: \(Set(missing).sorted())")
	}

	/// A Cocoa binding reads and writes its key path through key-value coding,
	/// so a bound property that is no longer visible to the runtime raises
	/// NSUnknownKeyException the first time the control draws. Key paths through
	/// `values.` belong to the shared user-defaults controller and key paths
	/// through `arrangedObjects` or `objectValue` to whatever a table row holds,
	/// so only the ones rooted at the nib's own object are ours to check.
	@Test("Every binding a nib makes against its owner is key-value coding compliant")
	func nibBindingsAreCodingCompliant() throws {
		var missing: [String] = []

		for url in try Self.nibURLs() {
			let document = try XMLDocument(contentsOf: url)

			for node in try document.nodes(forXPath: "//binding") {
				guard let element = node as? XMLElement,
				      let keyPath = element.attribute(forName: "keyPath")?.stringValue,
				      keyPath.hasPrefix("self."),
				      let owner = Self.bindingOwnerClassName(of: element),
				      let ownerClass = NSClassFromString(owner)
				else { continue }

				let property = String(keyPath.dropFirst("self.".count))

				if ownerClass.instancesRespond(to: NSSelectorFromString(property)) == false {
					missing.append("\(url.lastPathComponent): \(owner).\(property)")
				}
			}
		}

		#expect(missing.isEmpty, "Bound properties that no longer exist: \(missing.sorted())")
	}

	/// A `self.`-rooted binding is destined for the nib's File's Owner, which is
	/// the object the `<connections>` block hangs off — the same shape an outlet
	/// has, one level further out.
	private static func bindingOwnerClassName(of element: XMLElement) -> String? {
		guard let destination = element.attribute(forName: "destination")?.stringValue,
		      let document = element.rootDocument,
		      let owner = try? document.nodes(forXPath: "//*[@id='\(destination)']").first as? XMLElement
		else { return nil }

		return owner.attribute(forName: "customClass")?.stringValue
	}
}
