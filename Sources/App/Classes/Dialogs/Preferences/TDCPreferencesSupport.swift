/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\\_\\__|\\__,_|\\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *  * Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *  * Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *  * Neither the name of Textual, "Codeux Software, LLC", nor the
 *    names of its contributors may be used to endorse or promote products
 *    derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 *********************************************************************** */

import AppKit
import CocoaExtensions

enum PreferencesLayout {
	static let sidebarMinimumWidth = 200.0
	static let sidebarMaximumWidth = 260.0
	static let sidebarPreferredWidth = 215.0
	static let paneContentInset = 20.0
	static let windowMinimumWidth = 980.0
	static let windowMinimumHeight = 600.0
}

enum PreferencesIdentifiers {
	static let selectedPaneDefaultsKey = "TDCPreferencesController -> Selected Pane"
	static let toolbarBack = NSToolbarItem.Identifier("TDCPreferencesControllerBack")
	static let toolbarForward = NSToolbarItem.Identifier("TDCPreferencesControllerForward")
	static let paneCell = NSUserInterfaceItemIdentifier("TDCPreferencesControllerPaneCell")
	static let groupCell = NSUserInterfaceItemIdentifier("TDCPreferencesControllerGroupCell")
}

final class PreferencesSidebarItem: NSObject {
	let identifier: String?
	let title: String
	let symbolName: String?
	let children: [PreferencesSidebarItem]?

	init(
		identifier: String? = nil,
		title: String,
		symbolName: String? = nil,
		children: [PreferencesSidebarItem]? = nil
	) {
		self.identifier = identifier
		self.title = title
		self.symbolName = symbolName
		self.children = children
	}

	var isGroup: Bool {
		children != nil
	}
}

final class PreferencesPaneContainerView: NSView {
	override var isFlipped: Bool {
		true
	}
}

struct PreferencesPaneDescriptor: Equatable {
	let identifier: PreferencesPaneIdentifier
	let symbolName: String
	let contentViewKey: String
	let group: PreferencesPaneGroup
}

struct PreferencesSidebarEntry: Equatable {
	let identifier: String
	let title: String
	let symbolName: String
	let group: PreferencesPaneGroup
}

enum PreferencesPaneIdentifier: String, CaseIterable, Sendable {
	case addOns = "addons"
	case behavior
	case channelManagement
	case commandScope
	case compatibility
	case controls
	case defaultIRCopMessages
	case defaultIdentity
	case fileTransfers
	case floodControl
	case general
	case hidden
	case highlights
	case incomingData
	case inlineMedia
	case interface
	case logLocation
	case notifications
	case style
}

enum PreferencesPaneGroup: String, Sendable {
	case addOns = "addons"
	case advanced
	case main
}

enum PreferencesPaneCatalog {
	static let panes = [
		PreferencesPaneDescriptor(
			identifier: .general,
			symbolName: "gearshape",
			contentViewKey: "contentViewGeneral",
			group: .main
		),
		PreferencesPaneDescriptor(
			identifier: .behavior,
			symbolName: "slider.horizontal.3",
			contentViewKey: "contentViewBehavior",
			group: .main
		),
		PreferencesPaneDescriptor(
			identifier: .notifications,
			symbolName: "bell",
			contentViewKey: "contentViewNotifications",
			group: .main
		),
		PreferencesPaneDescriptor(
			identifier: .highlights,
			symbolName: "text.magnifyingglass",
			contentViewKey: "contentViewHighlights",
			group: .main
		),
		PreferencesPaneDescriptor(
			identifier: .interface,
			symbolName: "macwindow",
			contentViewKey: "contentViewInterface",
			group: .main
		),
		PreferencesPaneDescriptor(
			identifier: .style,
			symbolName: "paintbrush",
			contentViewKey: "contentViewStyle",
			group: .main
		),
		PreferencesPaneDescriptor(
			identifier: .controls,
			symbolName: "keyboard",
			contentViewKey: "contentViewControls",
			group: .main
		),
		PreferencesPaneDescriptor(
			identifier: .addOns,
			symbolName: "puzzlepiece.extension",
			contentViewKey: "contentViewInstalledAddons",
			group: .addOns
		),
		PreferencesPaneDescriptor(
			identifier: .channelManagement,
			symbolName: "person.2",
			contentViewKey: "contentViewChannelManagement",
			group: .advanced
		),
		PreferencesPaneDescriptor(
			identifier: .commandScope,
			symbolName: "terminal",
			contentViewKey: "contentViewCommandScope",
			group: .advanced
		),
		PreferencesPaneDescriptor(
			identifier: .compatibility,
			symbolName: "wrench.and.screwdriver",
			contentViewKey: "contentViewCompatibility",
			group: .advanced
		),
		PreferencesPaneDescriptor(
			identifier: .floodControl,
			symbolName: "timer",
			contentViewKey: "contentViewFloodControl",
			group: .advanced
		),
		PreferencesPaneDescriptor(
			identifier: .incomingData,
			symbolName: "arrow.down.circle",
			contentViewKey: "contentViewIncomingData",
			group: .advanced
		),
		PreferencesPaneDescriptor(
			identifier: .fileTransfers,
			symbolName: "arrow.down.app",
			contentViewKey: "contentViewFileTransfers",
			group: .advanced
		),
		PreferencesPaneDescriptor(
			identifier: .inlineMedia,
			symbolName: "photo",
			contentViewKey: "contentViewInlineMedia",
			group: .advanced
		),
		PreferencesPaneDescriptor(
			identifier: .logLocation,
			symbolName: "folder",
			contentViewKey: "contentViewLogLocation",
			group: .advanced
		),
		PreferencesPaneDescriptor(
			identifier: .defaultIdentity,
			symbolName: "person.crop.circle",
			contentViewKey: "contentViewDefaultIdentity",
			group: .advanced
		),
		PreferencesPaneDescriptor(
			identifier: .defaultIRCopMessages,
			symbolName: "shield",
			contentViewKey: "contentViewDefaultIRCopMessages",
			group: .advanced
		),
		PreferencesPaneDescriptor(
			identifier: .hidden,
			symbolName: "eye.slash",
			contentViewKey: "contentViewHiddenPreferences",
			group: .advanced
		),
	]

	static func descriptor(for identifier: String) -> PreferencesPaneDescriptor? {
		guard let identifier = PreferencesPaneIdentifier(rawValue: identifier) else { return nil }
		return panes.first { $0.identifier == identifier }
	}

	static func pluginIdentifier(at index: Int) -> String {
		"plugin-\(index)"
	}

	static func pluginIndex(from identifier: String) -> Int? {
		guard identifier.hasPrefix("plugin-") else { return nil }
		return Int(identifier.dropFirst(7))
	}
}

nonisolated enum PreferencesValueValidation {
	static let scrollbackSaveRange = 100 ... 50000
	static let scrollbackVisibleRange = 100 ... 15000
	static let inlineMediaWidthRange = 40 ... 2000
	static let inlineMediaHeightRange = 0 ... 6000
	static let fileTransferPortRange = 1024 ... 65535

	static func clamped(_ value: Int, to range: ClosedRange<Int>, allowingZero: Bool = false) -> Int {
		if allowingZero, value == 0 {
			return 0
		}
		return min(max(value, range.lowerBound), range.upperBound)
	}
}

@objc(TXColorUnarchiveFromDataTransformer)
final nonisolated class ColorUnarchiveFromDataTransformer: NSSecureUnarchiveFromDataTransformer {
	static let register: Void = {
		ValueTransformer.setValueTransformer(
			ColorUnarchiveFromDataTransformer(),
			forName: NSValueTransformerName("TXColorUnarchiveFromData")
		)
	}()

	override static func transformedValueClass() -> AnyClass {
		NSColor.self
	}

	override static func allowsReverseTransformation() -> Bool {
		true
	}

	override static var allowedTopLevelClasses: [AnyClass] {
		super.allowedTopLevelClasses + [NSColor.self]
	}

	override func transformedValue(_ value: Any?) -> Any? {
		if let color = value as? NSColor {
			return color
		}
		guard let data = value as? Data else { return nil }
		return try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data)
	}

	override func reverseTransformedValue(_ value: Any?) -> Any? {
		guard let color = value as? NSColor else { return nil }
		return try? NSKeyedArchiver.archivedData(withRootObject: color, requiringSecureCoding: true)
	}
}
