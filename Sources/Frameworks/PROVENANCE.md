# Vendored frameworks

These directories were Git submodules pointing at Codeux Software repositories.
They were vendored on 2026-08-20 so that fixes can be applied in-tree. Upstream
copyright and license notices are unchanged; see each directory's LICENSE.txt.
Vendored source follows the same Swift migration, organization, formatting, and
lint rules as the rest of `Sources/`. Preserve its license and acknowledgement
files when moving or rewriting it.

| Directory | Upstream | Commit |
|---|---|---|
| `Cocoa Extensions` | https://github.com/Codeux-Software/Cocoa-Extensions | 6d956f9a0cad72f08aecbe70b101020e5f6f8fb1 |
| `Static Libraries` | https://github.com/Codeux-Software/Static-Libraries | 57b2c193e7a6d996a86f8dc853f060a6368b3f5b |

`libssl.a` and `libtls.a` were dropped from Static Libraries because nothing
links them.

`Encryption Kit` (https://github.com/Codeux-Software/Encryption-Kit, commit
656af9005e152f7be9162c28321e3c03c83bf74a) was vendored here too, together with
`libotr.a`, `libgcrypt.a` and `libgpg-error.a` (and their headers and
documentation) in Static Libraries. All of it was removed on 2026-08-22: those
three libraries are LGPL 2.1, which is incompatible with Mac App Store
distribution, so Off-the-Record messaging support was dropped from the app.
Static Libraries now carries a source-built Swift 6 module based on
GRMustache.swift 7.0.0
(`4e3449141ce03cb1510f4752a26751bb9fbff9c2`). It replaces the former
GRMustache.framework, libmustache archive, and three redundant copies of the
Objective-C headers. Compatibility functions retained from the previous
GRMustache source (`af9d138f6fc1d985a2c4089ad19b791a02827908`) preserve existing
Glasstual and third-party theme behavior. Both upstream MIT notices remain in
`Static Libraries/Documentation`; exact source and adaptation details are in
`Static Libraries/GRMustache/PROVENANCE.md`.

`Auto Hyperlinks` (https://github.com/Codeux-Software/Auto-Hyperlinks,
commit 10c16555305ea775cd4600f0f21594d868b26d6e) was also vendored here but has
since been removed. Link detection now lives in
`Sources/App/Features/ChannelView/LinkParser.swift` on top of `NSDataDetector`.

The framework bundle identifier was renamed on 2026-08-22 from
`com.codeux.frameworks.CocoaExtensions` to
`com.vakesz.glasstual.frameworks.CocoaExtensions` (project.yml and the os_log
subsystem in `Cocoa Extensions/Classes/XRLogging.swift`). Copyright notices and
licence text are unchanged.
