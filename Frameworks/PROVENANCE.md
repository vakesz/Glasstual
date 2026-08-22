# Vendored frameworks

These directories were Git submodules pointing at Codeux Software repositories.
They were vendored on 2026-08-20 so that fixes can be applied in-tree. Upstream
copyright and license notices are unchanged; see each directory's LICENSE.txt.

| Directory | Upstream | Commit |
|---|---|---|
| `Cocoa Extensions` | https://github.com/Codeux-Software/Cocoa-Extensions | 6d956f9a0cad72f08aecbe70b101020e5f6f8fb1 |
| `Encryption Kit` | https://github.com/Codeux-Software/Encryption-Kit | 656af9005e152f7be9162c28321e3c03c83bf74a |
| `Static Libraries` | https://github.com/Codeux-Software/Static-Libraries | 57b2c193e7a6d996a86f8dc853f060a6368b3f5b |

Encryption Kit previously carried its own nested copy of Static Libraries; it
now links against `../Static Libraries`. `libssl.a` and `libtls.a` were dropped
because nothing links them.

`Auto Hyperlinks` (https://github.com/Codeux-Software/Auto-Hyperlinks,
commit 10c16555305ea775cd4600f0f21594d868b26d6e) was also vendored here but has
since been removed. Link detection now lives in
`Sources/App/Classes/Library/TLOLinkParser.swift` on top of `NSDataDetector`.

The framework bundle identifiers were renamed on 2026-08-22 from
`com.codeux.frameworks.CocoaExtensions` / `com.codeux.frameworks.encryptionKit`
to `com.vakesz.glasstual.frameworks.CocoaExtensions` /
`com.vakesz.glasstual.frameworks.EncryptionKit` (project.yml, the os_log
subsystem in XRLogging.m and the OTRKit cache path). Copyright notices and
licence text are unchanged.
