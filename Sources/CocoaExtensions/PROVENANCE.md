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
- `PortMapper.init()`, `localAddress` and `localAddressIsPrivate`, and the
  `NSObject` base class, which no selector, override or KVO observation needed
- `KeychainStore`'s `username:` parameter, which every caller passed as `nil`,
  and the `kSecAttrAccount` branch it selected
- The `TrustPanelPresenter.present(…)` forwarding overload, together with the
  `context:` parameter both overloads carried and the `Any?` the completion was
  handed back. The `TrustPanelCompletion` typealias and the `SecTrust` it handed
  back are gone as well: a caller that presented the panel already holds the
  trust, so the completion is `(Bool) -> Void` and defaults to nothing. The
  presenter is now an instance that holds itself while its sheet is up and
  offers `dismiss()`, in place of the `objc_setAssociatedObject` callback box
  and the `Unmanaged` pointer threaded through `contextInfo`
- `SecureTransportSupport.description(forCipherSuite:)`,
  `descriptions(forCipherListCollection:)` and
  `cipherSuites(inCollection:)`, three overloads that forwarded to the
  version beside them; each is now a default argument on that version.
  `description(forProtocolType:)` and `description(forCipherSuite:withProtocol:)`
  also lost their `Optional` return: both name an unrecognised value `"Unknown"`
  rather than returning `nil`
- `Accessibility.isVoiceOverEnabled`, the framework's whole `Accessibility`
  enum, which forwarded to `NSWorkspace.shared.isVoiceOverEnabled`. Its two
  callers ask the workspace directly. What the doc comment recorded is worth
  keeping: reading `com.apple.universalaccess` instead is denied by the app
  sandbox, and the denial is indistinguishable from "off", so that form always
  answered `false` in a shipping build
- `NSWindow.isBeneathMouse` and its private `windowBeneathMouse`, which had no
  caller, and `NSWindow.isInFullScreenMode`, inlined as
  `styleMask.contains(.fullScreen)` at its two call sites
- The whole `NSScreen` category -- `resolutionDescription`, `refreshRate` and
  the private `textualDisplayIdentifier` behind them -- which the System
  Profiler plugin was the only reader of
- `Bundle.textualDisplayName`, `Bundle.textual_formattedDisplayNames(for:)` and
  `Bundle.textual_openInstallationLocations(for:)`, which named and revealed
  loaded plugin bundles
- `Logging.defaultSubsystem`, `setDefaultSubsystem(toMainBundleCategory:)` and
  `logStackTrace(ofType:)`. Every logger in the tree names its own subsystem and
  category at the point it is declared, so nothing was left for a process-wide
  default to answer. `Logging` keeps `frameworkSubsystem`, which is what the
  framework's own loggers name
- `FileOperationOptions` entirely, with the `options:` parameter of
  `stageAndReplaceItem(at:withItemAt:)`. `symlinkPackages` was never passed, and
  neither was any other combination: the one behaviour in use replaces what is
  at the destination and sends the replaced copy to the Trash, which is what the
  call does now
- `CommandTokenizer.Options`, with the `options:` parameter of
  `nextQuotedToken()`. Every caller took the default, so the tokenizer states it:
  a token opens on `"`, a closing quote counts only before whitespace or the end
  of the line, and backslash runs collapse. `singleQuotes` had no caller at all
- `RegularExpression.hasNestedQuantifier(_:)` and the 300-line branch scanner
  behind it, a heuristic that refused a pattern shape while the user was typing
  it. `matchBudget` bounds what a pattern costs at match time, which is the
  defence that does not have to guess. `RegularExpression.string(_:isMatchedByRegex:)`
  went with it: it forwarded to `firstMatch(of:in:)` and had no caller outside
  the tests
- `KeychainItemClass`, which named the two `kSecClass` values.
  `internetPassword` was never selected, so every item is a generic password and
  nothing threads a `kind:` any more. `KeychainReadOutcome` went with it: only
  the tests ever asked whether a read found nothing or was refused, so
  `KeychainItem.password` answering `nil` for both is the whole surface.
  `PendingKeychainSecret.merged(over:)` had no caller
- `KeychainStore.migrateFromOtherAccessGroup(...)` and
  `removeCopiesOutsideAccessGroup(...)`. Nothing moves a secret between access
  groups or deletes a copy in another one: an item a build that predates this
  fork's container left behind stays where it is, and the read path does not
  look for it. The `entitledAccessGroups` lookup is back, as
  `KeychainStore.accessGroup`: it reads the first group of the process's
  `keychain-access-groups` entitlement and names it on every `SecItem` call, so
  a lookup answers with an item in that one group rather than with whichever of
  the process's groups the keychain picked
- `NSCoder.textual_decodeString(forKey:)` and `Numeric.data`, neither of which
  had a caller anywhere in the tree
- `Int64.textualPaddedByteCountDescription`, a one-line
  `formatted(.byteCount(style: .file))`. Its three callers now go through the
  application's own `LocalizedByteCount`, so the framework no longer owns a
  user-facing format
- `SystemInformation.systemBuildVersion`, `systemStandardVersion` and
  `systemOperatingSystemName`, with the private `SystemVersion` struct that read
  `/System/Library/CoreServices/SystemVersion.plist` to back the first of them.
  Nothing named the machine's OS version. `SystemInformation.xcstrings` and its
  one `operating-system-macos` key stay: the translations are preserved even
  though the code that read them is gone

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
- `RegularExpression.makeExpression(_:caseless:)` ->
  `RegularExpression.expression(for:caseless:)`, and public, so a caller that
  matches one pattern against many subjects shares the one cache
- `NSColor.textualChannelByte(_:)` / `textualChannel(_:)`, both private, ->
  `channelByte(_:)` / `channel(_:)`
- `NSWorkspace.textual_nameOfApplication(toOpen:)` ->
  `NSWorkspace.nameOfApplication(opening:)`
- `NSData.textualSha1` / `textualSha256` / `textualSha512` ->
  `NSData.sha1Hex` / `sha256Hex` / `sha512Hex`, with the private
  `textual_hexadecimalString(for:)` helper renamed `hexadecimalString(for:)` and
  the private `textualData` bridge inlined
- `NSNumber.textualIntegerStringValueWithLeadingZero` -> `NSNumber.twoDigitString`
- `NSPasteboard.textualStringContent` -> `NSPasteboard.stringContent`
- `CharacterSet.textualHexadecimal` -> `CharacterSet.hexadecimalDigits`,
  `textualPercentEncoded` -> `unreservedURICharacters`,
  `textualAlphanumericDashPeriod` -> `hostNameCharacters`,
  `textualLetter` -> `asciiLetters`
- `CipherSuiteCollection` names what each case is instead of when it was
  written: `.none` -> `.system` (it never meant "no suites" — it means the
  platform's own group), `.mozilla2015` -> `.intermediate`, and `.default` and
  `.mozilla2017` -> one `.modern`, the two having named byte-identical lists.
  Raw values changed with them; nothing reads the old ones
- `SecureTransportSupport.isCipherSuiteDeprecated(_:)` ->
  `isCipherSuiteLegacy(_:)`, and it now answers for every suite without forward
  secrecy rather than only for the six the fallback offers

## Members added here

- `SecureTransportSupport.legacyCipherSuites`,
  `namesNoSharedCipherSuite(errorCode:)` and
  `retriesWithLegacyCipherSuites(afterErrorCode:legacySuitesAlreadyOffered:peerCertificateSeen:)`,
  with the `no-shared-cipher-suite` entry of `SecureTransportErrorCodes.xcstrings`.
  Together they are the judgement behind the transport's one automatic dial
  without forward secrecy: which failure means the two sides agreed on no cipher
  suite, and what may be offered when it does. `cipherSuites(inCollection:)`
  lost its `includeDeprecated:` parameter in the same change — the suites it
  used to add are reached through `legacyCipherSuites` and by nothing a user can
  choose
- `String.nonEmpty` in `StringExtensions.swift`, which reads an empty string as
  the absent value it stands for on the wire. It came from the application's own
  `UI/NonEmptyString.swift` when that folder was dissolved: it extends
  Foundation and nothing about it is UI
- `ComparisonResult.ordered(by:)` in `FoundationExtensions.swift`, which flips an
  ascending result for a descending `SortOrder`. It came from the application's
  own `UI/ComparisonResult+SortOrder.swift` in the same change, for the same
  reason; every `SortComparator` a table column is built from needs the flip

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

The `Helper` suffix then said nothing that the framework being extended does not
say better, and eight of those files were a dozen lines of code under a
thirty-line notice each. One file per extended framework, and a file of its own
for each standalone type:

- `AppKitHelper.swift` + `NSWindowHelper.swift` + `NSTextViewHelper.swift` +
  `PasteboardHelper.swift` → `AppKitExtensions.swift`. It carries the widest of
  the four Codeux copyright ranges and the LimeChat notice `PasteboardHelper.swift`
  brought with it
- `FoundationHelper.swift` + `ErrorHelper.swift` + `NumericHelper.swift` +
  `URLHelper.swift` → `FoundationExtensions.swift`, again with the widest
  copyright range of the four
- `ColorHelper.swift` → `ColorExtensions.swift`,
  `StringHelper.swift` → `StringExtensions.swift`,
  `DataHelper.swift` → `DataExtensions.swift`
- `FileManagerHelper.swift` → `FileReplacement.swift`, after which
  `stageAndReplaceItem(at:withItemAt:)` is what the file is about
- `SystemInformation.swift` → `SystemSleepState.swift`. Once the OS-version
  accessors went, the type answered one question — whether the machine is
  asleep — so it is named for it: `beginObservingSleepState()` is
  `beginObserving()` and `systemIsSleeping` is `isSleeping`
- `NSWorkspace.textual_nameOfApplication(toOpen:)` moved from
  `FoundationExtensions.swift` to `AppKitExtensions.swift`. One file per
  extended framework, and `NSWorkspace` is not Foundation

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
- `.gitignore`, the upstream repository's own ignore file. It listed
  `*.mode1v3`, `*.pbxuser`, `*.perspectivev3`, `*.pyc`, `build`,
  `Build Results`, `xcuserdata` and `*.xcworkspace` — none of which can appear
  inside a source directory here, and the last of which fought the
  repository-root `.gitignore`. It is neither a licence nor a provenance
  record, so it carries nothing that had to be preserved.

## Files authored here

These are not vendored, and a diff against upstream should read them as
additions rather than as drift:

- `PropertyListModel.swift`, written for this tree
- `PropertyListValue.swift`, which carries a Textual lineage but has been
  rewritten around `Codable`

## Third-party work inside the vendored source

Upstream's own acknowledgements travel in `ACKNOWLEDGEMENT.txt`; these files
carry a second copyright notice of their own, which stays with them:

- `SecureTransportSupport.swift` — cipher-suite naming derived from Chromium's
  `ssl_cipher_suite_names.cc`, © 2013 The Chromium Authors, 3-clause BSD
- `DataHelper.swift`, `PasteboardHelper.swift` and `StringHelper.swift` —
  portions derived from LimeChat, © 2008 - 2010 Satoshi Nakagawa, New BSD
