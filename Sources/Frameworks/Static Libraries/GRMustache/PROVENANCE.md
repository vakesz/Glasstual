# GRMustache provenance

## Swift implementation

- Upstream: https://github.com/groue/GRMustache.swift
- Release: 7.0.0
- Commit: `4e3449141ce03cb1510f4752a26751bb9fbff9c2`
- Imported: 2026-08-27
- License: `../Documentation/LICENSE-GRMustache-Swift.txt`

The Swift files in `Sources` are built in-tree as the `Mustache` module. Public
factory functions were renamed to follow the repository's Swift naming rules,
and parser internals were split into focused state handlers so the complete
vendored source passes the same SwiftFormat and strict SwiftLint configuration
as first-party code.

The optional upstream Objective-C key-access helper is not included. Glasstual
renders dictionary, collection, and primitive contexts, all of which are
handled by the native Swift implementation without Objective-C KVC.

## Legacy compatibility

- Upstream: https://github.com/groue/GRMustache
- Commit previously shipped by Glasstual:
  `af9d138f6fc1d985a2c4089ad19b791a02827908`
- License: `../Documentation/LICENSE-libmustache.txt`

`Sources/LegacyStandardLibrary.swift` preserves the default filters and escape
functions that the Objective-C release installed in every template context.
This includes `isEmpty`, which is used by bundled Glasstual themes, and the
other documented functions that third-party themes may use.

Before the former binary was removed, representative templates were rendered
through both engines and compared byte for byte. The comparison covered escaped
and unescaped variables, regular and inverted sections, numeric values, arrays,
dotted names, `isEmpty`, dictionary partials, and the bundled
`newMessagePostedWithoutSender` template with its file-based partials.
