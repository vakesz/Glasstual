## What changed

<!-- One paragraph. Link the issue if there is one. -->

## How to test

<!-- Steps a reviewer can follow. Mention the network or server software if it matters. -->

## Checklist

- [ ] `make lint` and `make format-check` pass
- [ ] `make test` passes
- [ ] The app builds and launches in Debug
- [ ] Changes to `project.yml` were followed by `make generate` and the regenerated project is included
- [ ] New or migrated Swift is organized by domain or feature under `Sources/`
- [ ] No new Objective-C or C source or headers were added; temporary interop names its unmigrated consumer
- [ ] SwiftUI replacements preserve native commands, keyboard behavior, accessibility, restoration, and plugin contracts before AppKit code is removed
- [ ] Source moves and rewrites preserve upstream licenses, acknowledgements, and provenance
- [ ] New user-facing strings are in a feature- or table-namespaced String Catalog and use generated typed resources
