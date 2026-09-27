# Cocoa Extensions provenance

The Swift sources in this directory adapt
[Codeux Software/Cocoa-Extensions](https://github.com/Codeux-Software/Cocoa-Extensions)
at commit `6d956f9a0cad72f08aecbe70b101020e5f6f8fb1`.
They follow this repository's concurrency, formatting and lint rules.

Keep the full source notices, [LICENSE.txt](LICENSE.txt),
[ACKNOWLEDGEMENT.txt](ACKNOWLEDGEMENT.txt) and upstream revision with the code.
String Catalog attribution is in
[LocalizationCatalogNotices.md](LocalizationCatalogNotices.md).

## Sources

| Files | Responsibility |
| --- | --- |
| `AppKitExtensions.swift` | AppKit view, window, menu and pasteboard extensions. |
| `ColorExtensions.swift` | Color conversion. |
| `DataExtensions.swift` | Data conversion and hashes. |
| `FoundationExtensions.swift` | Foundation and file-system extensions. |
| `StringExtensions.swift` | String, character-set and address utilities. |
| `CommandTokenizer.swift` | Command token parsing. |
| `KeychainStore.swift` | Generic-password storage in the process's entitled access group. |
| `Logging.swift` | Framework log identifier. |
| `PortMapper.swift` | Port mapping through DNS-SD. |
| `RegularExpression.swift` | Cached expressions with bounded matching. |
| `SecureTransportSupport.swift` | TLS cipher policy, client-certificate chains, names and error descriptions. |
| `SystemSleepState.swift` | System sleep observation. |
| `TrustPanelPresenter.swift` | Certificate trust sheet. |

The following files are maintained by this project:

- `LineFramer.swift` bounds byte-stream framing for IRC and DCC CHAT.
- `LogSubsystem.swift` defines app and connection-host log identifiers.
- `PropertyListModel.swift` defines property-list model conversion.
- `PropertyListValue.swift` defines Codable property-list values and carries
  Textual copyright notices.

## Third-party attribution

These notices appear in full in the corresponding source files:

- `SecureTransportSupport.swift` includes cipher-suite naming derived from
  Chromium's `ssl_cipher_suite_names.cc`, copyright 2013 The Chromium Authors,
  under the 3-clause BSD license.
- `AppKitExtensions.swift`, `DataExtensions.swift` and
  `StringExtensions.swift` include LimeChat code, copyright 2008 - 2010
  Satoshi Nakagawa, under the New BSD License.
- `PortMapper.swift` includes Apple sample code, copyright 2007 Apple Inc.,
  under the license in its header.
