# Vendored framework provenance

`Cocoa Extensions` is vendored from
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
