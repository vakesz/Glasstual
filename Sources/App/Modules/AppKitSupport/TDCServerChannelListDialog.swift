/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\\_\\__|\\__,_|\\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import AppKit

@objc(TDCServerChannelListDialogEntry)
public final class ServerChannelListDialogEntry: NSObject {
	@objc public var channelName = ""
	@objc public var channelMemberCount = NSNumber(value: 0)
	@objc public var channelTopicUnformatted = ""
	@objc public var channelTopicFormatted = NSAttributedString()
}

@objc(TDCServerChannelListDialog)
@MainActor
public final class ServerChannelListDialog: WindowBase {
	@objc public private(set) var client: IRCClient!
	@objc public private(set) var clientId = ""
	@objc public var contentAlreadyReceived = false

	@IBOutlet private var updateButton: NSButton!
	@IBOutlet private var searchTextField: NSSearchField!
	@IBOutlet private var networkNameTextField: NSTextField!
	@IBOutlet private var channelListTable: BasicTableView!
	@IBOutlet private var channelListController: NSArrayController!

	private var isWaitingForWrites = false
	private var queuedWrites: [ServerChannelListDialogEntry] = []
	private var minimumUserCountLabel: NSTextField?
	private var minimumUserCountTextField: NSTextField?

	@available(*, unavailable)
	override public init() {
		fatalError("Use init(client:)")
	}

	@objc(initWithClient:)
	public init(client: IRCClient) {
		super.init()

		self.client = client
		clientId = client.uniqueIdentifier

		prepareInitialState()
	}

	@objc public var serverSideListArguments: String? {
		var minimumUserCount = 0

		if let minimumUserCountTextField {
			minimumUserCount = minimumUserCountTextField.integerValue
		}

		return Self.listArguments(
			forMinimumUserCount: UInt(minimumUserCountTextField?.integerValue ?? 0),
			pattern: searchTextField.stringValue,
			supportedTokens: client.supportInfo.extendedListTokens
		)
	}

	@objc(listArgumentsForMinimumUserCount:pattern:supportedTokens:)
	public class func listArguments(
		forMinimumUserCount minimumUserCount: UInt,
		pattern: String?,
		supportedTokens: [String]
	) -> String? {
		var conditions: [String] = []

		if minimumUserCount > 0, supportedTokens.contains("U") {
			conditions.append(">\(minimumUserCount - 1)")
		}

		let trimmedPattern = (pattern as NSString?)?.trim ?? ""

		if trimmedPattern.isEmpty == false, supportedTokens.contains("M") {
			let invalidCharacters = CharacterSet(charactersIn: ", ")
			if trimmedPattern.rangeOfCharacter(from: invalidCharacters) == nil {
				var patternValue = trimmedPattern

				if patternValue.contains("*") == false, patternValue.contains("?") == false {
					patternValue = "*\(patternValue)*"
				}

				conditions.append(patternValue)
			}
		}

		if conditions.isEmpty {
			return nil
		}

		return conditions.joined(separator: ",")
	}

	override public func show() {
		window.perform(NSSelectorFromString("restoreWindowStateForClass:"), with: type(of: self))
		super.show()
	}

	@objc public func clear() {
		channelListController.content = nil
		updateDialogTitle()
	}

	@objc public func addChannel(_ channel: String, count: UInt, topic: String?) {
		let newEntry = ServerChannelListDialogEntry()
		newEntry.channelName = channel
		newEntry.channelMemberCount = NSNumber(value: count)

		if let topic {
			newEntry.channelTopicUnformatted = topic
			newEntry.channelTopicFormatted =
				(topic as NSString).attributedString(
					withIRCFormatting: NSTableView.preferredGlobalTableViewFont(),
					preferredFontColor: .controlTextColor
				) ?? NSAttributedString()
		} else {
			newEntry.channelTopicUnformatted = ""
			newEntry.channelTopicFormatted = NSAttributedString()
		}

		objc_sync_enter(queuedWrites)
		queuedWrites.append(newEntry)
		objc_sync_exit(queuedWrites)

		if isWaitingForWrites == false {
			isWaitingForWrites = true
			performSelector(inCommonModes: #selector(queuedWritesTimer), with: nil, afterDelay: 1.0)
		}
	}

	private func prepareInitialState() {
		Bundle.main.loadNibNamed("TDCServerChannelListDialog", owner: self, topLevelObjects: nil)

		queuedWrites = []
		channelListTable.doubleAction = #selector(onJoin(_:))
		channelListTable.sortDescriptors = [
			NSSortDescriptor(key: "channelMemberCount", ascending: false, selector: #selector(NSNumber.compare(_:))),
		]
		networkNameTextField.stringValue = LocalizedKey("TDCServerChannelListDialog[7qf-r0]", client.networkNameAlt)
		prepareMinimumUserCountControls()
	}

	private func prepareMinimumUserCountControls() {
		guard client.supportInfo.extendedListSupportsToken("U") else {
			return
		}

		guard let contentView = window.contentView else {
			return
		}

		let label = NSTextField(labelWithString: LocalizedKey("TDCServerChannelListDialog[u7e-1s]"))
		label.translatesAutoresizingMaskIntoConstraints = false

		let formatter = NumberFormatter()
		formatter.numberStyle = .none
		formatter.minimum = 0
		formatter.maximum = 999_999
		formatter.allowsFloats = false

		let textField = NSTextField(string: "")
		textField.translatesAutoresizingMaskIntoConstraints = false
		textField.formatter = formatter
		textField.placeholderString = "0"
		textField.alignment = .right
		textField.toolTip = LocalizedKey("TDCServerChannelListDialog[u7e-2s]")
		textField.setAccessibilityLabel(LocalizedKey("TDCServerChannelListDialog[u7e-1s]"))

		contentView.addSubview(label)
		contentView.addSubview(textField)

		NSLayoutConstraint.activate([
			textField.widthAnchor.constraint(equalToConstant: 60),
			textField.trailingAnchor.constraint(equalTo: searchTextField.leadingAnchor, constant: -12),
			textField.centerYAnchor.constraint(equalTo: searchTextField.centerYAnchor),
			label.trailingAnchor.constraint(equalTo: textField.leadingAnchor, constant: -6),
			label.firstBaselineAnchor.constraint(equalTo: textField.firstBaselineAnchor),
			label.leadingAnchor.constraint(
				greaterThanOrEqualTo: networkNameTextField.trailingAnchor,
				constant: 20
			),
		])

		minimumUserCountLabel = label
		minimumUserCountTextField = textField
	}

	@objc private func queuedWritesTimer() {
		isWaitingForWrites = false
		writeQueuedWrites()
	}

	private func writeQueuedWrites() {
		objc_sync_enter(queuedWrites)

		guard queuedWrites.isEmpty == false else {
			objc_sync_exit(queuedWrites)
			return
		}

		let filterPredicate = channelListController.filterPredicate

		if let filterPredicate {
			var acceptedWrites: [ServerChannelListDialogEntry] = []

			for queuedWrite in queuedWrites where filterPredicate.evaluate(with: queuedWrite) {
				acceptedWrites.append(queuedWrite)
			}

			channelListController.add(contentsOf: acceptedWrites)
			queuedWrites.removeAll { acceptedWrites.contains($0) }
		} else {
			channelListController.add(contentsOf: queuedWrites)
			queuedWrites.removeAll()
		}

		objc_sync_exit(queuedWrites)
		updateDialogTitle()
	}

	private func updateDialogTitle() {
		let arrangedObjects = channelListController.arrangedObjects as? [Any] ?? []
		window.title = LocalizedKey("TDCServerChannelListDialog[ct4-wh]", formattedNumber(arrangedObjects.count))
	}

	@IBAction private func onClose(_: Any?) {
		close()
	}

	@IBAction private func onUpdate(_: Any?) {
		clear()

		let selector = NSSelectorFromString("serverChannelListDialogOnUpdate:")
		if let delegate, delegate.responds(to: selector) {
			delegate.perform(selector, with: self)
		}
	}

	@IBAction private func onJoinChannels(_ sender: Any?) {
		onJoin(sender)
	}

	@objc private func onJoin(_ sender: Any?) {
		let selectedRows = channelListTable.selectedRowIndexes
		let arrangedObjects = channelListController.arrangedObjects as? [ServerChannelListDialogEntry] ?? []
		var channelNames: [String] = []
		channelNames.reserveCapacity(selectedRows.count)

		for index in selectedRows {
			channelNames.append(arrangedObjects[index].channelName)
		}

		let joinSelector = NSSelectorFromString("serverChannelListDialog:joinChannels:")
		if let delegate, delegate.responds(to: joinSelector) {
			_ = delegate.perform(joinSelector, with: self, with: channelNames)
		}

		channelListTable.deselectAll(sender)
	}
}

extension ServerChannelListDialog: NSControlTextEditingDelegate {
	public func controlTextDidChange(_ obj: Notification) {
		guard obj.object as AnyObject? === searchTextField else {
			return
		}

		if searchTextField.stringValue.isEmpty {
			writeQueuedWrites()
		}
	}
}

extension ServerChannelListDialog: NSTableViewDelegate {
	public func tableView(
		_ tableView: NSTableView,
		selectionIndexesForProposedSelection proposedSelectionIndexes: IndexSet
	) -> IndexSet {
		tableView.selectionIndexes(
			forProposedSelection: proposedSelectionIndexes,
			maximumNumberOfSelections: 8
		)
	}
}

extension ServerChannelListDialog: NSWindowDelegate {
	public func windowWillClose(_: Notification) {
		cancelPerformRequests()
		channelListTable.dataSource = nil
		channelListTable.delegate = nil
		window.perform(NSSelectorFromString("saveWindowStateForClass:"), with: type(of: self))

		let selector = NSSelectorFromString("serverChannelDialogWillClose:")
		if let delegate, delegate.responds(to: selector) {
			delegate.perform(selector, with: self)
		}
	}
}
