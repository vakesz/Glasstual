# Vendored templating source for Glasstual

This directory originated as a collection of prebuilt static libraries. Its
remaining dependency is now built from Swift source as part of the XcodeGen
project.

| Library | Version | Source | Used by |
| --- | --- | --- | --- |
| [GRMustache.swift](https://github.com/groue/GRMustache.swift) | 7.0.0 (`4e3449141ce03cb1510f4752a26751bb9fbff9c2`) | `GRMustache/Sources` | Glasstual theme and inline-content templates |

libgpg-error, libgcrypt and libotr, together with the Encryption Kit framework
that linked them, were removed on 2026-08-22 (LGPL 2.1; see
`../PROVENANCE.md`). Their build scripts went with them.

## GRMustache

`GRMustache/Sources` contains the source-built Swift module. The former
Objective-C headers, `libmustache.a`, and `GRMustache.framework` bundle are no
longer part of the repository. XcodeGen defines the module target and its
consumers; no checked-in project or prebuilt wrapper needs updating.

The port retains the legacy standard-library functions used by Glasstual and
third-party themes. See `GRMustache/PROVENANCE.md` for the exact upstream source,
local compatibility changes, and verification scope.

## Licensing

Both upstream eras remain acknowledged:

- `Documentation/LICENSE-GRMustache-Swift.txt` covers the Swift implementation.
- `Documentation/LICENSE-libmustache.txt` preserves the license shipped with
  the former Objective-C implementation and covers the compatibility behavior
  carried forward from it.
