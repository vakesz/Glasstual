# Vendored framework provenance

`Sources/CocoaExtensions` is vendored from
[Codeux Software/Cocoa-Extensions](https://github.com/Codeux-Software/Cocoa-Extensions)
at commit `6d956f9a0cad72f08aecbe70b101020e5f6f8fb1`.

Its source is maintained in-tree and follows the repository's Swift,
concurrency, formatting and lint rules. Preserve the framework's
`LICENSE.txt`, `ACKNOWLEDGEMENT.txt`, source copyright notices and this upstream
revision when moving or rewriting it.

## Members removed from the vendored source

Parity with upstream is a record, not a reason to carry code nothing calls.
These members were part of the Objective-C categories and have no caller in
this tree; they are listed here so a future diff against upstream reads as a
deliberate removal rather than a missing port.

- `NSFont.textual_fontIsAvailable`
- `NSObject.textual_isEqualIgnoringCase`, `textual_cancelPerformRequests`,
  both `textual_performSelectorInCommonModes` overloads
- `NSArrayController.textual_removeAllArrangedObjects`,
  `textual_replaceObject(atArrangedObjectIndex:with:)`,
  `textual_moveObject(atArrangedObjectIndex:to:)`
- `NSCoder.textual_decodeDictionary(forKey:)`
- `NSLayoutConstraint.textualArchivedConstant` and its
  `textual_archiveConstant` / `textual_restoreArchivedConstant` /
  `textual_zeroOutConstant` companions, with their associated-object key
- `NSColor.textual_calibratedDeviceColor`
- `NSTableView.selectionIndexes(forProposedSelection:maximumCount:)`
- `NSOutlineView.isGroupItem(_:)` and `items(inContainingGroupOf:)`, the latter
  a rename of `items(inGroup:)`
- `NSWindow.ceIsActiveForDrawing`, `ceRunningInHighResolutionMode`, and the
  associated-object default-size pair `ce_saveSizeAsDefault` /
  `ce_restoreDefaultSize`
- `NSTextField.trimmedStringValue` / `trimmedFirstTokenStringValue` and
  `NSTextView.scrollView`, a rename of `enclosingScrollView`
- `FileManager.directoryExists(at:)` / `directoryExists(atPath:)` and the
  `FileOperationOptions.moveToDestination` branch nothing selected
- `SecureTransportSupport.appendCipherSuites(inCollection:includeDeprecated:to:)`,
  which configured `sec_protocol_options` before the `NetworkConnection`
  transport replaced it with `tls.cipherSuites(_:)`
- The `UserDefaults` `NSNumber`-boxing accessors for `short`, `unsignedShort`,
  `long`, `unsignedLong`, `longLong` and `unsignedLongLong`, which
  `UserDefaults` covers natively
- The whole `NSTableView` / `NSOutlineView` category, which was
  `TableCompatibility.swift`: `selectItem(at:)`, `invalidateSelectionBackground`,
  `rowBeneathMouse`,
  `selectRowIndexes(_:byExtendingSelection:scrollingToSelection:)`,
  `selectedItems`, `groupItems`, `items(inGroup:)` and
  `indexesOfItems(inGroup:)`. The application's lists are SwiftUI, and the
  transcript and member list are their own adapters, so nothing here has a
  caller
- The whole `UserDefaults` colour category, which was
  `UserDefaultsCompatibility.swift`: `setColor(_:forKey:)` and `color(forKey:)`.
  Colour preferences are read and written through `PreferenceColor`
- `Data.withoutNewlinesAtEnd` and `Data.splitNetworkLines()`, which framed
  lines for the socket the `NetworkConnection` transport replaced
- `NSWindow.ceIsOccluded` and `ceTitlebarFrame`
- `String.rangesOfFirstOccurrences(ofCharactersIn:options:)` and
  `String.Encoding.ianaCharsetName(forRawValue:)`
- `NSMutableAttributedString.nextTokenAsString()` /
  `nextQuotedTokenAsString()`, the attributed-string face of
  `CommandTokenizer`; commands are tokenized as plain text
- `FileManager.replaceItem(at:withItemAt:)` and its `options:` overload, which
  wrapped `stageAndReplaceItem(at:withItemAt:options:validate:)` in a `Bool`
- `RegularExpression.compilationCount(of:caseless:)` and the per-pattern
  compile counter behind it, `string(_:rangeOfRegex:)` with its `withoutCase:`
  overload, and `string(_:replacedByRegex:with:)`
- `PortMapper.init()`, `localAddress` and `localAddressIsPrivate`
- `KeychainStore`'s `username:` parameter, which every caller passed as `nil`,
  and the `kSecAttrAccount` branch it selected
- The `TrustPanelPresenter.present(…)` forwarding overload, together with the
  `context:` parameter both overloads carried and the `Any?` the completion was
  handed back: every caller passed `nil`, so `TrustPanelCompletion` is now
  `(SecTrust, Bool) -> Void`
- `SecureTransportSupport.description(forCipherSuite:)`,
  `descriptions(forCipherListCollection:)` and
  `cipherSuites(inCollection:)`, three overloads that forwarded to the
  version beside them; each is now a default argument on that version.
  `description(forProtocolType:)` and `description(forCipherSuite:withProtocol:)`
  also lost their `Optional` return: both name an unrecognised value `"Unknown"`
  rather than returning `nil`

Narrowed rather than removed: `String.IPv4AddressBytes` / `IPv6AddressBytes`
(read only by `isIPv4Address` / `isIPv6Address`),
`RegularExpression.boundedInput(_:limit:)` (applied by the bounded entry points)
and `SecureTransportSupport.isBadCertificateErrorCode(_:)` (asked by
`description(forBadCertificateErrorCode:)`) are now `private`.

## Members renamed

The vendored categories carried the Objective-C `textual_` and `ce` prefixes,
which a Swift extension does not need. The behaviour is unchanged; only the
names are:

- `NSColor.textual_color(hexadecimalValue:)` -> `NSColor.color(hexadecimal:)`
- `NSColor.textualHexadecimalValue` -> `NSColor.hexadecimalString`
- `NSColor.textual_calibratedColor(red:green:blue:alpha:)` ->
  `NSColor.calibratedColor(red:green:blue:alpha:)`
- `NSMenuItem.textualUserInfo` -> `NSMenuItem.userInfoString`
- `NSMenuItem.textual_setUserInfo(_:recursively:)` ->
  `NSMenuItem.setUserInfoString(_:recursively:)`
- `NSScreen.textualScreenResolutionString` -> `NSScreen.resolutionDescription`
- `NSScreen.textualScreenRefreshRate` -> `NSScreen.refreshRate`
- `NSFont.textual_fontTraitIsSet(_:)` -> `NSFont.hasTrait(_:)`
- `NSWindow.ce_exactlyCenter()` -> `NSWindow.centerOnScreen()`
- `NSWindow.ceIsInactive` -> `NSWindow.isInactive`
- `NSWindow.ceDeepestWindow` -> `NSWindow.frontmostAttachedSheet`
- `NSWindow.ceIsInFullscreenMode` -> `NSWindow.isInFullScreenMode`
- `NSWindow.ceIsBeneathMouse` / `ceWindowBeneathMouse` ->
  `NSWindow.isBeneathMouse` / `windowBeneathMouse`

## Files renamed or merged

The vendored layout carried two names for the same job. One file per type, and
no `SW` prefix or `Compatibility` suffix:

- `SWDataHelper.swift` + `DataCompatibility.swift` → `DataHelper.swift`
- `SWStringHelper.swift` + `StringHelper.swift` → `StringHelper.swift`
- `AppKitCompatibility.swift` → `AppKitHelper.swift`,
  `ColorCompatibility.swift` → `ColorHelper.swift`,
  `FileManagerCompatibility.swift` → `FileManagerHelper.swift`,
  `FoundationCompatibility.swift` → `FoundationHelper.swift`,
  `PasteboardCompatibility.swift` → `PasteboardHelper.swift`

## Files removed

- `FileSystemMonitor.swift`, the whole `XRFileSystemMonitor` FSEvents wrapper.
  Nothing in the application or the services watched a directory; its only
  callers were its own tests. It was also the sole reason the isolation gate
  carried an exemption — `FSEventStreamSetDispatchQueue` demands a serial
  `DispatchQueue`, so the queue's line was marked `// lock-queue: fsevents` and
  a second SwiftLint rule policed where that marker could sit. Both the marker
  and the `misplaced_fsevents_queue_marker` rule went with the file, and
  `Mutex<Value>` is now the only permitted lock with no exception. A future
  port of this type has to solve the queue, not re-open the exemption.
- `Static Libraries/LICENSE.txt`, and the now-empty directory around it. The
  file described a `Libraries` subdirectory, a `README.md` and a
  `Documentation` directory that this tree has never contained; no vendored
  static library was left for it to cover. The licences that are still in force
  travel with their source: `Sources/CocoaExtensions/LICENSE.txt`,
  `Sources/CocoaExtensions/ACKNOWLEDGEMENT.txt` and the per-file notices listed
  below.

## Third-party work inside the vendored source

Upstream's own acknowledgements travel in `ACKNOWLEDGEMENT.txt`; these files
carry a second copyright notice of their own, which stays with them:

- `SecureTransportSupport.swift` — cipher-suite naming derived from Chromium's
  `ssl_cipher_suite_names.cc`, © 2013 The Chromium Authors, 3-clause BSD
- `DataHelper.swift`, `PasteboardHelper.swift` and `StringHelper.swift` —
  portions derived from LimeChat, © 2008 - 2010 Satoshi Nakagawa, New BSD
