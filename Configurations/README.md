# Build configuration

`Glasstual.xcodeproj` is generated from `project.yml` at the repository root
with [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew bundle`
installs it). Edit the spec or the files in this directory, then run:

```sh
xcodegen generate
```

The generated project is committed so the tree builds without XcodeGen, but
never edit it directly: the next `xcodegen generate` overwrites it.

## Files

- `Signing.xcconfig` is the only file a contributor edits. It sets the code
  signing style, identity, and Team ID for every target. CI overrides these
  on the `xcodebuild` command line for Developer ID builds.
- `Base.xcconfig` holds every setting shared by all targets: product
  identity, feature flags, language modes, warnings, and build behaviour.
- `Debug.xcconfig` and `Release.xcconfig` include `Base.xcconfig` and change
  optimisation, assertions, hardened runtime, and the build scheme token.
  These are the only two build configurations.
- `Version.generated.xcconfig` is written by `Scripts/UpdateVersion.sh` (a
  pre-action of the `Glasstual` scheme) and is ignored by git. It sets
  `CURRENT_PROJECT_VERSION` to the date of the last commit (`yymmdd.HH`),
  which becomes `CFBundleVersion`. `MARKETING_VERSION` (the user facing
  version) lives in `Base.xcconfig`. Without the generated file the version
  falls back to `0`.
- `Sandbox/Inherited.entitlements` is used by the bundled extensions and the
  Core Media plugin. The app and each XPC service keep their own entitlements
  next to their sources.

## Feature flags

Feature flags are plain build settings in `Base.xcconfig`
(`GLASSTUAL_BUILT_INSIDE_SANDBOX`, `GLASSTUAL_BUILT_WITH_ADVANCED_ENCRYPTION`,
`GLASSTUAL_BUILT_WITH_SPARKLE_ENABLED`, `GLASSTUAL_BUILT_AS_UNIVERSAL_BINARY`).
They are passed to the compilers through `GCC_PREPROCESSOR_DEFINITIONS` and
`SWIFT_ACTIVE_COMPILATION_CONDITIONS`, and the `BuildConfig` aggregate target
(`Scripts/GenerateBuildConfig.sh`) also writes them into `FeatureFlags.h`
together with `BuildConfig.h` (bundle identifier, group container, version)
for the code that includes those headers. Set a flag to `1` or `0`; there is
no per-flag xcconfig any more.

Sparkle is linked from Swift Package Manager but compiled out
(`GLASSTUAL_BUILT_WITH_SPARKLE_ENABLED = 0`) because this fork has no update
feed. The Release entitlements already carry the `-spks`/`-spki` mach-lookup
exceptions Sparkle 2 needs inside the sandbox, so enabling it again only
requires flipping the flag and setting `SUFeedURL`.

## Targets

The app, the three frameworks, the three XPC services, the Core Media plugin,
and the six bundled extensions are all targets of the single project with
real dependencies and embed phases. The app's product name and bundle
identifier come from `GLASSTUAL_PRODUCT_NAME` and
`GLASSTUAL_BUNDLE_IDENTIFIER` in `Base.xcconfig`; the group container is
derived from `DEVELOPMENT_TEAM`.
