# Static libraries for Glasstual

This directory carries the prebuilt third-party libraries that the app links.

| Library | Version | Source | Used by |
| --- | --- | --- | --- |
| [GRMustache](https://github.com/groue/GRMustache) | af9d138f6fc1d985a2c4089ad19b791a02827908 | built from `Source/GRMustache/GRMustache.xcodeproj` | Glasstual (templating engine) |

libgpg-error, libgcrypt and libotr, together with the Encryption Kit framework
that linked them, were removed on 2026-08-22 (LGPL 2.1; see
`../PROVENANCE.md`). Their build scripts went with them.

## GRMustache

1. Check out the source code from GitHub.
2. Open `src/GRMustache.xcodeproj`, set the project to "GRMustache7-MacOS", and set build to "Any Mac".
3. Go to Project Info and set the Deployment Target to macOS 10.12.
4. Close the Xcode project.
5. Open Terminal, cd to the directory for GRMustache, and run `make lib/libGRMustache7-MacOS.a`.
6. Copy `lib/libGRMustache7-MacOS.a` to `Source/GRMustache/Libraries/libmustache.a` in this repo.
7. If you are building a different version of GRMustache, you will need to copy over the headers to `Source/GRMustache/Headers` and ensure that there have been no substantial changes.
8. Open `Sources/GRMustache/GRMustache.xcodeproj` in this repo.
9. Build the GRMustache wrapper.
10. Copy the `GRMustache.framework` build product to the `Libraries` directory in this repo.

## Licensing

See the `Documentation` directory.
