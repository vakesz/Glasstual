# Build configurations

Build settings are shared through layered xcconfig files. Keep project files
limited to target-specific metadata such as product names and Info.plist paths.

- `Common/Foundation.xcconfig` contains the Release defaults shared by every
  project. Release builds are universal, hardened, product-validated, and run
  the Clang static analyzer in deep mode.
- `Common/Foundation Debug.xcconfig` includes the Release defaults and replaces
  optimization, assertions, architecture selection, and signing behavior for
  development builds.
- `Common/Glasstual*.xcconfig` and `Common/XPC*.xcconfig` add settings for a
  particular product type.
- `Debug/` and `Standard Release/` select the bundle identifiers, feature set,
  and nested build schemes for their distribution channel.

The Xcode configuration name passed to command-line builds is `Debug` or
`Release`. `Glasstual (Debug)` and `Glasstual (Standard Release)` are scheme
names, not configuration names.

The legacy `Release (Sandboxed)` and plugin `Release (App Store)` entries use
the Standard Release xcconfigs so they do not fall back to Xcode SDK defaults.
The supported release workflow is the Developer ID `Release` configuration.
