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

	@Test("A member list configures itself once, whatever asks it to")
	func memberListConfiguresExactlyOnce() {
		let memberList = MemberList(frame: NSRect(x: 0, y: 0, width: 150, height: 400))

		#expect(memberList.dataSource == nil)

		memberList.configure()

		#expect(memberList.dataSource === memberList)
		#expect(memberList.delegate === memberList)

		/* A second pass would install a second tracking area and re-register the
		 dragged types; the flag is what keeps `viewDidMoveToWindow` cheap when
		 the view moves between windows. */
		let trackingAreaCount = memberList.trackingAreas.count

		memberList.configure()
		memberList.configure()

		#expect(memberList.trackingAreas.count == trackingAreaCount)
	}

	@Test("A member cell is configured when the table vends it, not at nib load")
	func memberListCellConfiguresOnce() {
		let cell = MemberListCell(frame: NSRect(x: 0, y: 0, width: 150, height: 28))
		let nicknameField = NSTextField(labelWithString: "")
		cell.setValue(nicknameField, forKey: "cellTextField")

		cell.configure()

		#expect(nicknameField.usesSingleLineMode)
		#expect(nicknameField.lineBreakMode == .byTruncatingTail)

		/* The second call must not walk over a value set since. */
		nicknameField.lineBreakMode = .byWordWrapping
		cell.configure()

		#expect(nicknameField.lineBreakMode == .byWordWrapping)
	}

	@Test("The member info popover configures itself once")
	func memberInfoPopoverConfiguresOnce() {
		let popover = MemberListUserInfoPopover()

		popover.configure()
		#expect(popover.behavior == .transient)

		popover.behavior = .applicationDefined
		popover.configure()

		#expect(popover.behavior == .applicationDefined)
	}

	@Test("No AppKit class in the app still overrides awakeFromNib")
	func noAwakeFromNibOverridesRemain() {
		let classes: [AnyClass] = [
			MainWindow.self,
			MainWindowChannelView.self,
			MainWindowLoadingScreenView.self,
			MainWindowTextView.self,
			MemberList.self,
			MemberListCell.self,
			MemberListUserInfoPopover.self,
			ContentNavigationOutlineView.self,
			ValidatedComboBox.self,
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
		let container = NSView(frame: NSRect(x: 0, y: 0, width: 618, height: 25))
		container.translatesAutoresizingMaskIntoConstraints = false
		contentView.addSubview(container)

		contentView.setValue(container, forKey: "inputBarContainerView")
		contentView.setValue(
			container.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 7),
			forKey: "inputBarTopConstraint"
		)
		contentView.setValue(
			contentView.heightAnchor.constraint(equalToConstant: 38),
			forKey: "textViewHeightConstraint"
		)
		contentView.setValue(
			contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 35),
			forKey: "windowContentViewMinimumHeight"
		)

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

	// MARK: - Observation tasks

	@Test("A search-result cell drops its channel observations when the table reuses it")
	func spotlightCellCancelsObservationsOnReuse() {
		let window = NSWindow(
			contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
			styleMask: [.titled],
			backing: .buffered,
			defer: true
		)
		let cell = ChannelSpotlightSearchResultCellView(frame: NSRect(x: 0, y: 0, width: 300, height: 40))
		window.contentView?.addSubview(cell)

		let client = GLTTestClient()
		let channel = Channel(config: ChannelConfig(channelName: "#observed"))
		channel.setValue(client, forKey: "associatedClient")

		cell.objectValue = ChannelSpotlightSearchResult(channel: channel)

		let observations = cell.channelObservations
		#expect(observations.count == 2)

		cell.prepareForReuse()

		#expect(cell.channelObservations.isEmpty)

		for observation in observations {
			#expect(observation.isCancelled)
		}
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

	// MARK: - Subview ordering

	@Test("Reordering the channel view's subviews keeps them in item order")
	func channelViewOrdersSubviewsByItemIndex() {
		let channelView = MainWindowChannelView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
		let indexes = [3, 0, 2, 1]

		for index in indexes {
			let subview = MainWindowChannelViewSubview(frame: .zero)
			subview.itemIndex = index
			subview.uniqueIdentifier = "item-\(index)"
			channelView.addSubview(subview)
		}

		channelView.orderSubviewsByItemIndex()

		let ordered = channelView.subviews.compactMap { ($0 as? MainWindowChannelViewSubview)?.itemIndex }

		#expect(ordered == [0, 1, 2, 3])
	}

	@Test("Subviews that share an item index keep the order they arrived in")
	func channelViewOrderingIsStableForEqualIndexes() {
		let channelView = MainWindowChannelView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))

		for identifier in ["first", "second", "third"] {
			let subview = MainWindowChannelViewSubview(frame: .zero)
			subview.itemIndex = 0
			subview.uniqueIdentifier = identifier
			channelView.addSubview(subview)
		}

		channelView.orderSubviewsByItemIndex()

		let ordered = channelView.subviews.compactMap { ($0 as? MainWindowChannelViewSubview)?.uniqueIdentifier }

		#expect(ordered == ["first", "second", "third"])
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
