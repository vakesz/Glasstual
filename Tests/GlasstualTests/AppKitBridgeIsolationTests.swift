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
import SwiftUI
import Testing

/// A notification that has to be handled before the post returns, in the shape
/// Foundation needs to deliver it on the main actor.
private struct SynchronousProbeMessage: NotificationCenter.MainActorMessage {
	typealias Subject = NSObject

	static let notificationName = Notification.Name("GlasstualBridgeTestSynchronous")

	static var name: Notification.Name {
		notificationName
	}

	static func makeMessage(_: Notification) -> Self? {
		Self()
	}
}

/// What a main-actor notification handler saw, in order.
@MainActor
private final class NotificationCollector {
	private(set) var values: [Int] = []

	func append(_ value: Int) {
		values.append(value)
	}
}

/// The seams that used to be nib-time hooks, KVO change handlers and a C
/// comparator, now that each of them is main-actor isolated by declaration.
@MainActor
@Suite("AppKit bridges without runtime checks")
struct AppKitBridgeIsolationTests {
	// MARK: - Nib-free configuration

	@Test("No AppKit class in the app still overrides awakeFromNib")
	func noAwakeFromNibOverridesRemain() {
		let classes: [AnyClass] = [
			MainWindow.self,
			MainWindowTextView.self,
			TextViewIRCFormattingMenu.self,
			ApplicationController.self,
		]

		for subject in classes {
			let ownImplementation = class_getMethodImplementation(subject, #selector(NSObject.awakeFromNib))
			let inheritedImplementation = class_getMethodImplementation(
				class_getSuperclass(subject),
				#selector(NSObject.awakeFromNib)
			)

			#expect(
				ownImplementation == inheritedImplementation,
				"\(subject) still overrides awakeFromNib"
			)
		}
	}

	// MARK: - TextKit 2 input field

	@Test("The input field is built in code and backed by TextKit 2")
	func inputFieldUsesTextKit2() {
		let contentView = MainWindowTextViewContentView(frame: NSRect(x: 0, y: 0, width: 800, height: 38))
		contentView.configure()

		let textView = contentView.textView

		/* The whole point of building it in code: a nib-decoded NSTextView is
		 always TextKit 1, whatever `usesTextKit2` in the xib says. */
		#expect(textView.textLayoutManager != nil)
		#expect(textView.allowsUndo)
		#expect(textView.enclosingScrollView != nil)

		/* Asking again must hand back the same field, not build a second one. */
		#expect(contentView.textView === textView)
	}

	@Test("The main window shell is programmatic")
	func mainWindowShellIsProgrammatic() {
		let window = MainWindow(
			contentRect: NSRect(x: 0, y: 0, width: 800, height: 477),
			styleMask: [.titled, .closable, .miniaturizable, .resizable],
			backing: .buffered,
			defer: false
		)

		#expect(window.serverList.numberOfRows == 0)
		#expect(window.memberList.numberOfRows == 0)
		#expect(window.inputTextField.textLayoutManager != nil)
		#expect(window.loadingScreen.viewIsVisible == false)
		#expect(window.formattingMenu.formatterMenu.submenu?.items.isEmpty == false)
		#expect(Bundle.main.path(forResource: "TVCMainWindow", ofType: "nib") == nil)
	}

	@Test("Notifications posted in one turn all reach the handler")
	func notificationBurstIsNotDropped() async {
		let subscriptions = NotificationSubscriptions()
		let name = Notification.Name("GlasstualBridgeTestBurst-\(UUID().uuidString)")
		let collector = NotificationCollector()

		subscriptions.observe(name) { notification in
			collector.append(notification.userInfo?["index"] as? Int ?? -1)
		}
		defer { subscriptions.cancelAll() }

		/* The subscription is set up by a task, so it has to get its turn on the
		 main actor before anything is posted. */
		await yieldRepeatedly()

		for index in 0 ..< 5 {
			NotificationCenter.default.post(name: name, object: nil, userInfo: ["index": index])
		}

		await yieldRepeatedly()

		/* One value at a time is what `AsyncPublisher` asks for, and a
		 notification publisher drops what it cannot deliver; without the buffer
		 in between only the first of these five arrives. */
		#expect(collector.values == [0, 1, 2, 3, 4])
	}

	@Test("A synchronous subscription runs on the main actor before the post returns")
	func synchronousObservationRunsInlineOnTheMainActor() {
		let subscriptions = NotificationSubscriptions()
		let collector = NotificationCollector()

		subscriptions.observeSynchronously(SynchronousProbeMessage.self) {
			/* The point of the message shape: this is checked isolation, not an
			 assumption about whichever thread posted. */
			MainActor.preconditionIsolated()
			collector.append(1)
		}
		defer { subscriptions.cancelAll() }

		NotificationCenter.default.post(name: SynchronousProbeMessage.notificationName, object: nil)

		/* Nothing has been awaited, so a deferred delivery would leave this
		 empty — the contract these notifications carry is that the work is done
		 by the time the post returns. */
		#expect(collector.values == [1])

		subscriptions.cancelAll()
		NotificationCenter.default.post(name: SynchronousProbeMessage.notificationName, object: nil)

		#expect(collector.values == [1])
	}

	private func yieldRepeatedly() async {
		for _ in 0 ..< 500 {
			await Task.yield()
		}
	}

	// MARK: - Opened files

	@Test("An opened file is recognised by kind")
	func openedFilesAreClassified() throws {
		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent("GlasstualImportTests-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: directory) }

		let script = directory.appendingPathComponent("Example.scpt")
		try Data().write(to: script)

		let bundle = directory.appendingPathComponent("Example.bundle", isDirectory: true)
		try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)

		let style = directory.appendingPathComponent("Example.css")
		try Data().write(to: style)

		#expect(ResourceFileImporter.kind(of: script) == .script)
		#expect(ResourceFileImporter.kind(of: bundle) == .extensionBundle)
		#expect(ResourceFileImporter.kind(of: style) == nil)
	}

	@Test("The application no longer answers the untitled-document question")
	func applicationDoesNotHandleUntitledFiles() {
		/* The importer was an NSDocument subclass, which made AppKit offer an
		 untitled document on reopen; the delegate had to say no. With the
		 document class gone there is nothing to say no to. */
		#expect(
			ApplicationController.instancesRespond(
				to: NSSelectorFromString("applicationShouldOpenUntitledFile:")
			) == false
		)
	}

	// MARK: - Resource cache

	@Test("A cached property list is read from disk once")
	func resourceContentsAreCachedOnce() {
		ResourceManager.removeAllCachedResources()
		defer { ResourceManager.removeAllCachedResources() }

		#expect(ResourceManager.hasCachedResource(named: "StaticStore") == false)

		let first = ResourceManager.dictionary(fromResources: "StaticStore")
		#expect(first != nil)
		#expect(ResourceManager.hasCachedResource(named: "StaticStore"))

		let second = ResourceManager.dictionary(fromResources: "StaticStore")
		#expect(first as NSDictionary? == second as NSDictionary?)
	}
}
